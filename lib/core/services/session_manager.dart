import 'dart:async';
import 'package:flutter/material.dart';
import '../repositories/user_session_repository.dart';
import 'app_logger.dart';

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
  DateTime? _lastTouchAt;

  static const _inactivityDuration = Duration(minutes: 30);
  // TASK-311: كل لمسة (onPointerDown) في التطبيق كانت بتعمل UPDATE في
  // user_sessions من غير أي throttling — مستخدم بيتفاعل بكثرة ممكن
  // ينتج عشرات الكتابات في الداتابيز في دقيقة واحدة من غير داعي حقيقي.
  // دلوقتي أقصى تحديث فعلي لآخر نشاط مرة كل 45 ثانية بس — عداد الخمول
  // المحلي (Timer) نفسه لسه بيتصفّر مع كل تفاعل زي ما هو، مستقل تماماً
  // عن الـ throttling ده.
  static const _touchThrottle = Duration(seconds: 45);

  void start(int? sessionId, {VoidCallback? onInactivityLogout}) {
    _sessionId = sessionId;
    this.onInactivityLogout = onInactivityLogout;
    _lastTouchAt = null;
    WidgetsBinding.instance.addObserver(this);
    _resetInactivityTimer();
    // TASK-310: تنضيف best-effort لأي جلسات قديمة اتقفلت فعلياً
    // (crash/force-kill) بس لسه شكلها "شغالة" في القاعدة.
    unawaited(_sessionRepo.closeStaleSessions());
  }

  Future<void> stop() async {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    if (_sessionId != null) {
      try {
        await _sessionRepo.closeSession(_sessionId!);
      } catch (e, st) {
        // الأهم إن حالة الدخول محلياً تتصفّر حتى لو الإغلاق فشل على
        // السيرفر (best-effort) — لكن دلوقتي على الأقل بنسجّل السبب.
        AppLogger.logError('SessionManager.stop', e, st);
      }
    }
    _sessionId = null;
  }

  /// ينده عليها أي تفاعل حقيقي من المستخدم (لمسة، بحث، حفظ... إلخ)
  /// عشان يصفّر عداد الخمول محلياً، ويحدّث آخر نشاط في القاعدة بحد
  /// أقصى مرة كل [_touchThrottle] (TASK-311).
  void registerInteraction() {
    if (_sessionId == null) return;
    _resetInactivityTimer();

    final now = DateTime.now();
    if (_lastTouchAt != null && now.difference(_lastTouchAt!) < _touchThrottle) {
      return;
    }
    _lastTouchAt = now;
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