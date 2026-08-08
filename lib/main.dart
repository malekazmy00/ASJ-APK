import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/auth_persistence.dart';
import 'features/auth/presentation/auth_providers.dart';

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