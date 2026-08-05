import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification.dart';

/// يطابق repositories/notification_repo.py.
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
}
