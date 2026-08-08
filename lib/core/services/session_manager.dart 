import 'dart:async';
import 'package:flutter/material.dart';
import '../repositories/user_session_repository.dart';

/// يدير دورة حياة الجلسة الفعلية:
/// - يفضل السيشن مفتوح طول ما التطبيق شغال في الخلفية (مفيش أي إغلاق
///   تلقائي بسبب تصغير التطبيق فقط).
/// - يقفل السيشن تلقائياً لو مفيش أي تفاعل (لمس) لمدة 30 دقيقة.
/// - يحاول يقفل السيشن لو التطبيق اتقفل فعلياً (أفضل مجهود ممكن —
///   Android مش بيضمن استدعاء أي كود دايماً عند القتل المفاجئ للعملية).
class SessionManager extends WidgetsBindingObserver {
  SessionManager._();
  static final SessionManager instance = SessionManager._();

  final _sessionRepo = UserSessionRepository();
  int? _sessionId;
  Timer? _inactivityTimer;
  VoidCallback? onInactivityLogout;

  static const _inactivityDuration = Duration(minutes: 30);

  void start(int? sessionId, {VoidCallback? onInactivityLogout}) {
    _sessionId = sessionId;
    this.onInactivityLogout = onInactivityLogout;
    WidgetsBinding.instance.addObserver(this);
    _resetInactivityTimer();
  }

  Future<void> stop() async {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    if (_sessionId != null) {
      try {
        await _sessionRepo.closeSession(_sessionId!);
      } catch (_) {
        // تجاهل الفشل - الأهم إن حالة الدخول محلياً تتصفّر
      }
    }
    _sessionId = null;
  }

  /// ينده عليها أي تفاعل حقيقي من المستخدم (لمسة، بحث، حفظ... إلخ)
  /// عشان يصفّر عداد الخمول ويحدّث آخر نشاط في القاعدة.
  void registerInteraction() {
    if (_sessionId == null) return;
    _resetInactivityTimer();
    unawaited(_sessionRepo.touchSession(_sessionId!));
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityDuration, () async {
      await stop();
      onInactivityLogout?.call();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_sessionId == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        // رجع للواجهة - يعتبر تفاعل، يحدّث آخر نشاط ويصفّر عداد الخمول
        registerInteraction();
        break;
      case AppLifecycleState.detached:
        // أفضل مجهود ممكن لتسجيل قفل الجلسة عند إغلاق التطبيق فعلياً
        unawaited(stop());
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // التطبيق في الخلفية بس - السيشن يفضل مفتوح عادي، من غير أي قفل
        break;
    }
  }
}