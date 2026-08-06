import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/enums.dart';
import '../models/transaction_log.dart';

/// يطابق repositories/log_repo.py — المصدر المشترك لتايم لاين تتبع
/// القطعة وتتبع المستخدم (المرحلة 3).
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
  Future<List<TransactionLog>> getRecent({DateTime? since, int limit = 300}) async {
    var q = _client.from('transactions_log').select();
    if (since != null) q = q.gte('timestamp', since.toIso8601String());
    final rows = await q.order('timestamp', ascending: false).limit(limit);
    return (rows as List).map((r) => TransactionLog.fromMap(r)).toList();
  }
}