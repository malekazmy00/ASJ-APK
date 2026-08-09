import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/enums.dart';
import '../models/transaction_log.dart';

/// يطابق repositories/log_repo.py — المصدر المشترك لتايم لاين تتبع
/// القطعة وتتبع المستخدم.
///
/// الجولة الثالثة (نقطة ١٠): إضافة getUnified() — سجل موحّد بيجمع كل
/// مصادر السجل المتفرقة (transactions_log، engineer_queries،
/// user_sessions، pending_approvals) في قايمة واحدة، مع فلتر نوع
/// الحدث + فترة زمنية + مستخدم، كلهم قابلين للدمج مع بعض.
class LogRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> logAction({
    int? itemId,
    required ActionType actionType,
    required String username,
    String details = '',
    String? exitType,
  }) async {
    await _client.from('transactions_log').insert({
      'item_id': itemId,
      'action_type': actionType.dbValue,
      'username': username,
      'details': details,
      if (exitType != null) 'exit_type': exitType,
    });
  }

  Future<List<TransactionLog>> getByItem(int itemId) async {
    final rows = await _client
        .from('transactions_log')
        .select()
        .eq('item_id', itemId)
        .order('timestamp', ascending: false);
    return (rows as List).map((r) => TransactionLog.fromMap(r)).toList();
  }

  Future<List<TransactionLog>> getByUser(String username) async {
    final rows = await _client
        .from('transactions_log')
        .select()
        .eq('username', username)
        .order('timestamp', ascending: false);
    return (rows as List).map((r) => TransactionLog.fromMap(r)).toList();
  }

  /// تتبع القطعة بالرقم (وليس بالـ item_id فقط) — يجمع كل الحركات لكل
  /// القطع اللي تحمل نفس part_number عبر جدول inventory_items أولاً.
  Future<List<TransactionLog>> getByPartNumber(String partNumber) async {
    final itemRows = await _client
        .from('inventory_items')
        .select('item_id')
        .eq('part_number', partNumber);
    final itemIds =
        (itemRows as List).map((r) => r['item_id'] as int).toList();
    if (itemIds.isEmpty) return [];

    final rows = await _client
        .from('transactions_log')
        .select()
        .inFilter('item_id', itemIds)
        .order('timestamp', ascending: false);
    return (rows as List).map((r) => TransactionLog.fromMap(r)).toList();
  }

  /// سجل نشاط عام زمني (كل الحركات لكل القطع/المستخدمين) — مش مربوط
  /// بقطعة أو مستخدم معين، مع فلتر فترة اختياري (اليوم/٧ أيام/٣٠ يوم).
  /// لسه موجودة للتوافق مع الاستخدام الحالي (بدون فلتر النوع/المستخدم
  /// المُضاف في getUnified).
  Future<List<TransactionLog>> getRecent({DateTime? since, int limit = 300}) async {
    var q = _client.from('transactions_log').select();
    if (since != null) q = q.gte('timestamp', since.toIso8601String());
    final rows = await q.order('timestamp', ascending: false).limit(limit);
    return (rows as List).map((r) => TransactionLog.fromMap(r)).toList();
  }

  // ============================================================
  // الجولة الثالثة (نقطة ١٠) — السجل الموحّد
  // ============================================================

  /// قايمة أنواع الأحداث المتاحة للفلتر المنسدل — مفتاح 'ALL' معناه
  /// كل الأنواع مع بعض. الأنواع اللي مالهاش قيمة dbValue من ActionType
  /// (QUERY, SESSION, APPROVAL) مصدرها جداول تانية غير transactions_log.
  static const Map<String, String> unifiedEventTypeLabels = {
    'ALL': 'الكل',
    'INSERT': 'إضافة قطعة',
    'UPDATE': 'تعديل',
    'DELETE': 'حذف',
    'OUT': 'صرف',
    'RETURN': 'استرجاع',
    'SEARCH': 'بحث (مسجّل كحركة)',
    'LOGIN': 'دخول',
    'LOGOUT': 'خروج',
    'EXPORT': 'تصدير',
    'IMPORT': 'استيراد',
    'USER_MGMT': 'إدارة مستخدمين',
    'DB_RESTORE': 'استعادة قاعدة بيانات',
    'QUERY': 'استعلام وبحث (تفصيلي)',
    'SESSION': 'فتح تطبيق (جلسة)',
    'APPROVAL': 'طلب موافقة',
  };

  bool _isTxLogType(String type) => ![
        'QUERY',
        'SESSION',
        'APPROVAL',
      ].contains(type);

  /// السجل الموحّد: يجمع من كل المصادر المتفرقة في قايمة واحدة مرتبة
  /// زمنياً، كل عنصر بشكل موحّد {timestamp, type, username, item_id,
  /// details}. [eventType] = null أو 'ALL' يعني كل الأنواع.
  Future<List<Map<String, dynamic>>> getUnified({
    String? eventType,
    DateTime? since,
    DateTime? until,
    String? username,
    int limit = 300,
  }) async {
    final wantAll = eventType == null || eventType == 'ALL';
    final entries = <Map<String, dynamic>>[];

    // المصدر الأساسي: transactions_log (إضافة/صرف/استرجاع/تعديل/بحث
    // مسجّل/دخول-خروج/تصدير-استيراد/إدارة مستخدمين)
    if (wantAll || _isTxLogType(eventType)) {
      var q = _client.from('transactions_log').select();
      if (!wantAll) q = q.eq('action_type', eventType);
      if (since != null) q = q.gte('timestamp', since.toIso8601String());
      if (until != null) q = q.lte('timestamp', until.toIso8601String());
      if (username != null && username.isNotEmpty) q = q.eq('username', username);
      final rows = await q.order('timestamp', ascending: false).limit(limit);
      for (final r in rows as List) {
        entries.add({
          'timestamp': r['timestamp'],
          'type': r['action_type'],
          'username': r['username'],
          'item_id': r['item_id'],
          'details': r['details'],
        });
      }
    }

    // الاستعلامات التفصيلية (سبب البحث، الجهاز المطلوب، إلخ) —
    // مصدرها engineer_queries مش transactions_log
    if (wantAll || eventType == 'QUERY') {
      var q = _client.from('engineer_queries').select();
      if (since != null) q = q.gte('timestamp', since.toIso8601String());
      if (until != null) q = q.lte('timestamp', until.toIso8601String());
      if (username != null && username.isNotEmpty) q = q.eq('username', username);
      final rows = await q.order('timestamp', ascending: false).limit(limit);
      for (final r in rows as List) {
        entries.add({
          'timestamp': r['timestamp'],
          'type': 'QUERY',
          'username': r['username'],
          'item_id': null,
          'details': '${r['part_number'] ?? ''} — ${r['query_reason'] ?? ''}',
        });
      }
    }

    // جلسات فتح/قفل التطبيق
    if (wantAll || eventType == 'SESSION') {
      var q = _client.from('user_sessions').select();
      if (since != null) q = q.gte('login_at', since.toIso8601String());
      if (until != null) q = q.lte('login_at', until.toIso8601String());
      if (username != null && username.isNotEmpty) q = q.eq('username', username);
      final rows = await q.order('login_at', ascending: false).limit(limit);
      for (final r in rows as List) {
        entries.add({
          'timestamp': r['login_at'],
          'type': 'SESSION',
          'username': r['username'],
          'item_id': null,
          'details':
              'جهاز: ${r['device_info'] ?? 'غير معروف'} — IP: ${r['ip_address'] ?? 'غير معروف'}',
        });
      }
    }

    // طلبات الموافقة (تعديل رقم قطعة/سريال/استيراد قاعدة معرفة)
    if (wantAll || eventType == 'APPROVAL') {
      var q = _client.from('pending_approvals').select();
      if (since != null) q = q.gte('created_at', since.toIso8601String());
      if (until != null) q = q.lte('created_at', until.toIso8601String());
      if (username != null && username.isNotEmpty) {
        q = q.eq('requested_by', username);
      }
      final rows = await q.order('created_at', ascending: false).limit(limit);
      for (final r in rows as List) {
        entries.add({
          'timestamp': r['created_at'],
          'type': 'APPROVAL',
          'username': r['requested_by'],
          'item_id': null,
          'details': '${r['approval_type'] ?? ''} — ${r['status'] ?? ''}',
        });
      }
    }

    entries.sort((a, b) {
      final ta = DateTime.tryParse(a['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });

    if (entries.length > limit) return entries.sublist(0, limit);
    return entries;
  }
}