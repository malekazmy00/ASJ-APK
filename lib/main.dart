import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/auth_persistence.dart';
import 'core/repositories/app_version_repository.dart';
import 'features/auth/presentation/auth_providers.dart';
import 'features/update_required/presentation/update_required_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.red.shade50,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Text(
              '${details.exceptionAsString()}\n\n${details.stack}',
              style: const TextStyle(color: Colors.red, fontSize: 10),
              textDirection: TextDirection.ltr,
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