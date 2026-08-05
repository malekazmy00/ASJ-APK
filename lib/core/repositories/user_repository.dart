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
}
