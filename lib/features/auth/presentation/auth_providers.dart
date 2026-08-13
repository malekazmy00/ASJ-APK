import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/notification_repository.dart';
import '../../../core/repositories/user_session_repository.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/auth_persistence.dart';
import '../../../core/services/device_info_helper.dart';
import '../../../core/services/error_messages.dart';
import '../../../core/services/session_manager.dart';
import '../data/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// يُعبّى في main() قبل runApp من AuthPersistence.restoreUser() —
/// عشان أول رسم للتطبيق يبان فيه المستخدم مسجّل دخول على طول من غير
/// أي وميض لشاشة الدخول لو كان فعلاً مسجّل قبل كده.
final initialUserProvider = Provider<AppUser?>((ref) => null);

/// يحمل المستخدم الحالي بعد تسجيل الدخول (null = غير مسجل دخول).
/// السيشن الحقيقي (user_sessions) بيتفتح/يتقفل عبر SessionManager، اللي
/// بيخلي الحساب مفتوح طول ما التطبيق شغال في الخلفية، ومايقفلش إلا
/// بخروج صريح أو خمول 30 دقيقة.
class AuthController extends StateNotifier<AppUser?> {
  AuthController(this._authService, this._sessionRepo, AppUser? initialUser)
      : super(initialUser) {
    if (initialUser != null && initialUser.token != null) {
      // استعادة دخول سابق بعد إغلاق فعلي للتطبيق - نفتح سيشن جديد
      // بأفضل مجهود ممكن، من غير ما نطلب كلمة مرور تاني. مفيش إشعار
      // "تسجيل دخول" هنا عمداً — ده مش دخول صريح من المستخدم، وإطلاق
      // إشعار عليه هيغرق الأدمن بإشعارات كل ما حد يفتح التطبيق تاني.
      _openSessionAndTrack(initialUser.username, initialUser.token!);
    }
  }

  final AuthService _authService;
  final UserSessionRepository _sessionRepo;
  final _notifRepo = NotificationRepository();
  bool isLoading = false;
  String? errorMessage;

  Future<void> _openSessionAndTrack(String username, String token) async {
    try {
      final device = await getDeviceDescription();
      final sessionId = await _sessionRepo.openSession(token, deviceInfo: device);
      SessionManager.instance.start(sessionId, onInactivityLogout: () {
        state = null;
        AuthPersistence.clearUser();
        _notifRepo.create(
          notifType: NotificationEventType.sessionEnd.dbValue,
          message: '$username — انتهت الجلسة تلقائياً بعد خمول',
        );
      });
    } catch (e, stackTrace) {
      // C-06: كان catch (_) صامت تماماً — بقى بيسجّل الخطأ الحقيقي عبر
      // AppLogger بدل ما يختفي بصمت. فشل فتح الـ session نفسه لسه مش
      // لازم يمنع استخدام التطبيق (best-effort)، بس دلوقتي على الأقل
      // ممكن نلاحظ لو بيحصل بكثرة وقت المراجعة/الاختبار.
      AppLogger.logError('AuthController._openSessionAndTrack ($username)', e, stackTrace);
    }
  }

  Future<bool> login(String username, String password) async {
    isLoading = true;
    errorMessage = null;
    try {
      final user = await _authService.signIn(
        username: username,
        password: password,
      );
      state = user;
      if (user != null && user.token != null) {
        await AuthPersistence.saveUser(user);
        await _openSessionAndTrack(user.username, user.token!);
        await _notifRepo.create(
          notifType: NotificationEventType.login.dbValue,
          message: '$username سجّل دخول',
        );
      }
      return user != null;
    } catch (e, st) {
      // H-08: كان بيوري exception الخام للمستخدم ("فشل تسجيل الدخول:
      // $e") — ممكن يسرّب تفاصيل داخلية (اسم function، نوع خطأ
      // Supabase...). دلوقتي التفاصيل الكاملة بتتسجل عبر AppLogger
      // (تفيد وقت التشخيص)، والمستخدم بيشوف رسالة عربية مفهومة بس.
      AppLogger.logError('AuthController.login', e, st);
      errorMessage = friendlyErrorMessage(e);
      return false;
    } finally {
      isLoading = false;
    }
  }

  /// الطريقة الوحيدة الحقيقية لإنهاء الدخول — زرار الخروج الصريح بس.
  Future<void> logout() async {
    final username = state?.username;
    await SessionManager.instance.stop();
    await AuthPersistence.clearUser();
    await _authService.signOut();
    state = null;
    if (username != null) {
      await _notifRepo.create(
        notifType: NotificationEventType.sessionEnd.dbValue,
        message: '$username سجّل خروج',
      );
    }
  }

  /// أي تفاعل حقيقي من المستخدم (بحث، حفظ، تنقّل...) بيصفّر عداد الخمول.
  void registerInteraction() {
    SessionManager.instance.registerInteraction();
  }

  /// توكن الدخول الحالي — تستخدمه أي شاشة بتنادي Edge Function حساسة
  /// (admin-create-user، admin-reset-password، resolve-approval،
  /// change-password...) عشان تبعته في هيدر x-app-token.
  String? get token => state?.token;
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AppUser?>((ref) {
  return AuthController(
    ref.read(authServiceProvider),
    UserSessionRepository(),
    ref.read(initialUserProvider),
  );
});