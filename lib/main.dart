import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // مهم للتشخيص: افتراضياً Flutter بيستبدل أي widget بيفشل أثناء البناء
  // بمربع رمادي فاضي في وضع Release (بدون أي تفاصيل عن سبب الفشل).
  // الكود ده بيوريك رسالة الخطأ الحقيقية جوه التطبيق نفسه بدل المربع
  // الرمادي، عشان نقدر نشخص أي مشكلة فعلية من سكرين شوت بدل التخمين.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.red.shade50,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Text(
              details.exceptionAsString(),
              sty
