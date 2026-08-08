import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/app_user.dart';
import '../../../core/repositories/user_session_repository.dart';
import '../../../core/services/auth_persistence.dart';
import '../../../core/services/device_info_helper.dart';
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
    if (initialUser != null) {
      // استعادة دخول سابق بعد إغلاق فعلي للتطبيق - نفتح سيشن جديد
      // بأفضل مجهود ممكن، من غير ما نطلب كلمة مرور تاني.
      _openSessionAndTrack(initialUser.username);
    }
  }

  final AuthService _authService;
  final UserSessionRepository _sessionRepo;
  bool isLoading = false;
  String? errorMessage;

  Future<void> _openSessionAndTrack(String username) async {
    try {
      final device = await getDeviceDescription();
      final sessionId = await _sessionRepo.openSession(username, deviceInfo: device);
      SessionManager.instance.start(sessionId, onInactivityLogout: () {
        state = null;
        AuthPersistence.clearUser();
      });
    } catch (_) {
      // فشل فتح السيشن مش لازم يمنع الاستخدام — تجاهل بصمت
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
      if (user != null) {
        await AuthPersistence.saveUser(user);
        await _openSessionAndTrack(user.username);
      }
      return user != null;
    } catch (e) {
      // مؤقت للتشخيص: بنوري تفاصيل الخطأ الحقيقي بدل رسالة عامة، عشان
      // نعرف السبب الفعلي (شبكة/رابط غلط/مفتاح غلط) بدل التخمين.
      errorMessage = 'فشل تسجيل الدخول: $e';
      return false;
    } finally {
      isLoading = false;
    }
  }

  /// الطريقة الوحيدة الحقيقية لإنهاء الدخول — زرار الخروج الصريح بس.
  Future<void> logout() async {
    await SessionManager.instance.stop();
    await AuthPersistence.clearUser();
    await _authService.signOut();
    state = null;
  }

  /// أي تفاعل حقيقي من المستخدم (بحث، حفظ، تنقّل...) بيصفّر عداد الخمول.
  void registerInteraction() {
    SessionManager.instance.registerInteraction();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AppUser?>((ref) {
  return AuthController(
    ref.read(authServiceProvider),
    UserSessionRepository(),
    ref.read(initialUserProvider),
  );
});