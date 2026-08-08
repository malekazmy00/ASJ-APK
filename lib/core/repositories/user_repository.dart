import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';

/// يطابق repositories/user_repo.py (عدا التحقق من كلمة المرور، اللي
/// ينتقل لـ Edge Function login-user لأنه يحتاج مكتبة Argon2 على السيرفر).
class UserRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<AppUser>> getAll() async {
    final rows = await _client.from('users').select().order('username');
    return (rows as List).map((r) => AppUser.fromMap(r)).toList();
  }

  Future<void> updatePermissions(
    String username, {
    bool? canExport,
    bool? canTrack,
    bool? canEdit,
  }) async {
    final fields = <String, dynamic>{};
    if (canExport != null) fields['can_export'] = canExport;
    if (canTrack != null) fields['can_track'] = canTrack;
    if (canEdit != null) fields['can_edit'] = canEdit;
    if (fields.isEmpty) return;
    await _client.from('users').update(fields).eq('username', username);
  }

  Future<void> updateStatus(String username, String status) async {
    await _client.from('users').update({'status': status}).eq('username', username);
  }

  Future<void> updateRole(String username, String role) async {
    await _client.from('users').update({'role': role}).eq('username', username);
  }

  /// تحكم فردي لكل حساب في ظهور تبويب معيّن، فوق افتراضي الدور
  /// (جدول user_tab_overrides الجديد). null = مفيش تخصيص، يتبع افتراضي الدور.
  Future<Map<String, bool>> getTabOverrides(String username) async {
    final rows = await _client
        .from('user_tab_overrides')
        .select('tab_id, enabled')
        .eq('username', username);
    return {for (final r in rows as List) r['tab_id'] as String: r['enabled'] as bool};
  }

  Future<void> setTabOverride(
    String username,
    String tabId,
    bool enabled, {
    required String updatedBy,
  }) async {
    await _client.from('user_tab_overrides').upsert({
      'username': username,
      'tab_id': tabId,
      'enabled': enabled,
      'updated_by': updatedBy,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> clearTabOverride(String username, String tabId) async {
    await _client
        .from('user_tab_overrides')
        .delete()
        .eq('username', username)
        .eq('tab_id', tabId);
  }
}