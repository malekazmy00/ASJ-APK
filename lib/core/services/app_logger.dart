import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// نقطة تسجيل موحّدة لأي خطأ بيتم "امتصاصه" عمداً (best-effort — يعني
/// فشله متعمد إنه ما يوقفش المستخدم) بدل ما يختفي بصمت في catch (_) {}.
/// راجع C-06 في المراجعة: catch (_) صامت في auth/session/persistence
/// بيمنعنا نلاحظ لو الفشل بيحصل بكثرة.
///
/// TASK-313: متوصّلة دلوقتي بـ Sentry فعلياً (راجع SentryFlutter.init في
/// main.dart) — أي استدعاء لـ logError من أي مكان في المشروع (كل
/// المواضع اللي كانت catch (_) {} أو بتوري رسالة عامة للمستخدم) بيوصل
/// تلقائياً لداشبورد Sentry، من غير ما نحتاج نلحق كل catch لوحده.
class AppLogger {
  static void logError(String context, Object error, [StackTrace? stackTrace]) {
    debugPrint('[$context] $error${stackTrace != null ? '\n$stackTrace' : ''}');
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) => scope.setTag('context', context),
    );
  }
}
