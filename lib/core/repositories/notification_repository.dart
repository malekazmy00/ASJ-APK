import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification.dart';

/// يطابق repositories/notification_repo.py + منطق جديد: الإشعارات
/// دلوقتي فعلاً بتتسجل (كانت الشاشة بس من غير أي إدخال)، وكل نوع
/// إشعار بيتفحص أولاً من notification_settings قبل ما يتسجل، عشان
/// الأدمن يقدر يوقف نوع معين من الإعدادات من غير أي تعديل كود.
class NotificationRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<AppNotification>> getRecent({int limit = 50}) async {
    final rows = await _client
        .from('admin_notifications')
        .select()
        .order('timestamp', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => AppNotification.fromMap(r)).toList();
  }

  Future<void> markAllRead() async {
    await _client.from('admin_notifications').update({'is_read': true}).neq('notif_id', -1);
  }

  Future<void> clearAll() async {
    await _client.from('admin_notifications').delete().neq('notif_id', -1);
  }

  /// إنشاء إشعار جديد — بيتجاهل الإنشاء بصمت لو النوع ده موقوف من الإعدادات.
  Future<void> create({
    required String notifType,
    required String message,
    int? relatedId,
  }) async {
    final enabled = await _isTypeEnabled(notifType);
    if (!enabled) return;
    // TASK-018: نحدد timestamp صراحة من العميل كمان (defense-in-depth
    // فوق DEFAULT now() المضاف في migrations/018) — عشان أي إشعار
    // بيتسجل من هنا (مش من الـ RPCs) ميرجعش يطلع بـ NULL لو الـ DEFAULT
    // اتشال بالغلط لأي سبب مستقبلاً.
    await _client.from('admin_notifications').insert({
      'message': message,
      'notif_type': notifType,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (relatedId != null) 'related_id': relatedId,
    });
  }

  Future<bool> _isTypeEnabled(String notifType) async {
    final row = await _client
        .from('notification_settings')
        .select('enabled')
        .eq('notif_type', notifType)
        .maybeSingle();
    if (row == null) return true; // نوع جديد لسه مش مسجّل = افتراضي شغال
    return row['enabled'] as bool? ?? true;
  }

  Future<Map<String, bool>> getAllSettings() async {
    final rows = await _client.from('notification_settings').select();
    return {for (final r in rows as List) r['notif_type'] as String: r['enabled'] as bool? ?? true};
  }

  Future<void> setTypeEnabled(String notifType, bool enabled) async {
    await _client
        .from('notification_settings')
        .update({'enabled': enabled})
        .eq('notif_type', notifType);
  }
}