import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_session.dart';
import '../services/app_logger.dart';

/// يدير جدول user_sessions الجديد (المرحلة 3: تتبع جلسات المستخدمين
/// الفعلية، مش بس last_login).
class UserSessionRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// يُستدعى فور نجاح تسجيل الدخول (راجع AuthController.login). بيعدي
  /// على Edge Function `open-session` بدل إدراج مباشر، عشان الـ IP
  /// يتقرا من السيرفر (التطبيق نفسه مش عنده وسيلة موثوقة يعرف بيها
  /// عنوان الـ IP بتاعه).
  ///
  /// TASK-303: الـ username مبقاش بيتبعت في الـ body خالص — الدالة على
  /// السيرفر بتستخرجه من التوكن الموقّع (x-app-token) نفسه، فمفيش حد
  /// يقدر يفتح session باسم حساب مش بتاعه.
  Future<int?> openSession(String token, {String? deviceInfo}) async {
    try {
      final response = await _client.functions.invoke(
        'open-session',
        body: {if (deviceInfo != null) 'deviceInfo': deviceInfo},
        headers: {'x-app-token': token},
      );
      final data = response.data as Map<String, dynamic>?;
      if (data?['success'] == true) return data?['sessionId'] as int?;
      return null;
    } catch (e, st) {
      AppLogger.logError('UserSessionRepository.openSession', e, st);
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

  /// TASK-310: جلسة detached مش ضمانة (Android ممكن يقتل العملية من
  /// غير ما يدّي فرصة لـ stop() ينفّذ). بدل ما نثق في logout_at IS NULL
  /// كدليل إن السيشن لسه شغالة، بننادي RPC بسيطة على السيرفر بتقفل أي
  /// سيشن last_activity_at بتاعها أقدم من 30 دقيقة ومفيهاش logout_at
  /// أصلاً — best-effort، بتتنادى بعد كل فتح سيشن جديد وقبل عرض تقارير
  /// النشاط، عشان البيانات تفضل صحيحة حتى بعد crash/force-kill.
  Future<void> closeStaleSessions() async {
    try {
      await _client.rpc('close_stale_sessions');
    } catch (e, st) {
      AppLogger.logError('UserSessionRepository.closeStaleSessions', e, st);
    }
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