import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/app_logger.dart';
import 'core/services/auth_persistence.dart';
import 'core/repositories/app_version_repository.dart';
import 'features/auth/presentation/auth_providers.dart';
import 'features/update_required/presentation/update_required_screen.dart';

// TASK-313: DSN بتاع مشروع Sentry (asj-store) — مش سر، آمن يتحط هنا
// في كود العميل (Sentry نفسها بتوضح كده)، عكس APP_JWT_SECRET.
const _sentryDsn =
    'https://aad7bdc8bcd84306391a25cd6c158bc9@o4511900213706752.ingest.us.sentry.io/4511900261089280';

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      // نسبة عيّنة تتبع الأداء (transactions) — مش كل الأخطاء، الأخطاء
      // نفسها بتتسجل دايماً. نسبة معقولة بدون استهلاك حصة مجانية بسرعة.
      options.tracesSampleRate = 0.2;
      options.environment = kReleaseMode ? 'production' : 'debug';
    },
    appRunner: _bootstrap,
  );
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TASK-307: قبل كده كان بيعرض exceptionAsString() + الـ stack كامل
  // للمستخدم النهائي — ده تسريب معلومات داخلية (أسماء classes، ملفات،
  // تفاصيل الخطأ الحقيقي) في نسخة Production. دلوقتي:
  //  - المستخدم يشوف رسالة عامة بس.
  //  - التفاصيل الكاملة (exception + stack) بتتسجل عبر AppLogger، اللي
  //    بقى موصّل فعلياً بـ Sentry (TASK-313) — يعني أي خطأ من دول
  //    بيوصلنا على الداشبورد، مش بس في الـ console.
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.logError('FlutterError', details.exception, details.stack);
  };

  // أخطاء برّه Flutter widget tree (async errors في الـ isolate
  // الرئيسي) — SentryFlutter.init بيوصلها تلقائياً في الأصل، لكن
  // بنمرّرها هنا كمان عبر AppLogger عشان تتسجل بنفس الشكل والسياق
  // الموحّد زي باقي الأخطاء في المشروع.
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.logError('PlatformDispatcher', error, stack);
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    AppLogger.logError('ErrorWidget', details.exception, details.stack);
    return Material(
      color: Colors.red.shade50,
      child: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              'حدث خطأ غير متوقع.\nيرجى إعادة المحاولة.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  };

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // الجولة الثالثة (نقطة ٢٢): فحص أقل نسخة مطلوبة قبل أي حاجة تانية —
  // لو التطبيق قديم، نعرض شاشة "التحديث مطلوب" بس ونوقف هنا، حتى قبل
  // شاشة الدخول نفسها. فشل الفحص نفسه (مفيش نت مثلاً) بيسيب المستخدم
  // يدخل عادي (راجع AppVersionRepository.isUpdateRequired).
  final needsUpdate = await AppVersionRepository().isUpdateRequired();

  if (needsUpdate) {
    runApp(const _UpdateRequiredApp());
    return;
  }

  // استعادة الدخول قبل أول رسم للتطبيق، عشان الحساب يبان مسجّل دخول
  // على طول من غير أي وميض لشاشة الدخول لو كان فعلاً مسجّل قبل كده.
  final restoredUser = await AuthPersistence.restoreUser();

  runApp(
    ProviderScope(
      overrides: [
        initialUserProvider.overrideWithValue(restoredUser),
      ],
      child: const AsjApp(),
    ),
  );
}

/// تطبيق بديل مصغّر (مش نفس AsjApp) — بيتفادى تحميل أي جزء من التطبيق
/// الأساسي (router/riverpod providers) خالص لما التحديث يبقى إجباري،
/// عشان نضمن مفيش أي مسار ملتوي يتخطى الفحص.
class _UpdateRequiredApp extends StatelessWidget {
  const _UpdateRequiredApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale('ar'),
      supportedLocales: [Locale('ar'), Locale('en')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: UpdateRequiredScreen(),
    );
  }
}

class AsjApp extends ConsumerWidget {
  const AsjApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'ASJ Medical Systems Store',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: router,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // أي لمسة في أي حتة في التطبيق تصفّر عداد خمول الـ 30 دقيقة
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (ref.read(authControllerProvider) != null) {
              ref.read(authControllerProvider.notifier).registerInteraction();
            }
          },
          child: child,
        );
      },
    );
  }
}