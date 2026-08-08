import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_session.dart';

/// يدير جدول user_sessions الجديد (المرحلة 3: تتبع جلسات المستخدمين
/// الفعلية، مش بس last_login).
class UserSessionRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// يُستدعى فور نجاح تسجيل الدخول (راجع AuthController.login). بيعدي
  /// على Edge Function `open-session` بدل إدراج مباشر، عشان الـ IP
  /// يتقرا من السيرفر (التطبيق نفسه مش عنده وسيلة موثوقة يعرف بيها
  /// عنوان الـ IP بتاعه).
  Future<int?> openSession(String username, {String? deviceInfo}) async {
    try {
      final response = await _client.functions.invoke(
        'open-session',
        body: {'username': username, if (deviceInfo != null) 'deviceInfo': deviceInfo},
      );
      final data = response.data as Map<String, dynamic>?;
      if (data?['success'] == true) return data?['sessionId'] as int?;
      return null;
    } catch (_) {
      return null;
    }
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