import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/app_user.dart';
import '../../../core/repositories/user_session_repository.dart';
import '../data/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// يحمل المستخدم الحالي بعد تسجيل الدخول (null = غير مسجل دخول).
/// كمان بيفتح/يقفل صف في user_sessions (المرحلة 3: تتبع الجلسات الفعلي).
class AuthController extends StateNotifier<AppUser?> {
  AuthController(this._authService, this._sessionRepo) : super(null);

  final AuthService _authService;
  final UserSessionRepository _sessionRepo;
  bool isLoading = false;
  String? errorMessage;
  int? _currentSessionId;

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
        try {
          _currentSessionId = await _sessionRepo.openSession(user.username);
        } catch (_) {
          _currentSessionId = null;
        }
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

  Future<void> logout() async {
    if (_currentSessionId != null) {
      try {
        await _sessionRepo.closeSession(_currentSessionId!);
      } catch (_) {
        // تجاهل فشل إغلاق الجلسة - الأهم إن تسجيل الخروج نفسه ينجح
      }
    }
    _currentSessionId = null;
    await _authService.signOut();
    state = null;
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AppUser?>((ref) {
  return AuthController(
    ref.read(authServiceProvider),
    UserSessionRepository(),
  );
});