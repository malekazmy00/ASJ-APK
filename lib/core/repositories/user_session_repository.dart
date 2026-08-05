import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_session.dart';

/// يدير جدول user_sessions الجديد (المرحلة 3: تتبع جلسات المستخدمين
/// الفعلية، مش بس last_login).
class UserSessionRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// يُستدعى فور نجاح تسجيل الدخول (راجع AuthController.login).
  Future<int?> openSession(String username) async {
    final rows = await _client
        .from('user_sessions')
        .insert({'username': username})
        .select('id');
    final list = rows as List;
    if (list.isEmpty) return null;
    return list.first['id'] as int?;
  }

  /// heartbeat بسيط لتحديث آخر نشاط - يُستدعى دورياً أو عند كل عملية مهمة.
  Future<void> touchSession(int sessionId) async {
    await _client
        .from('user_sessions')
        .update({'last_activity_at': DateTime.now().toIso8601String()})
        .eq('id', sessionId);
  }

  Future<void> closeSession(int sessionId) async {
    await _client
        .from('user_sessions')
        .update({'logout_at': DateTime.now().toIso8601String()})
        .eq('id', sessionId);
  }

  Future<List<UserSession>> getByUsername(String username, {int limit = 100}) async {
    final rows = await _client
        .from('user_sessions')
        .select()
        .eq('username', username)
        .order('login_at', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => UserSession.fromMap(r)).toList();
  }
}
