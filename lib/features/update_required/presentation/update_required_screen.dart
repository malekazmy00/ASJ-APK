import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/asj_logo.dart';

/// شاشة إجبار التحديث (الجولة الثالثة، نقطة ٢٢) — بتظهر بدل التطبيق
/// كله لو النسخة المثبتة أقدم من الحد الأدنى المسموح بيه على
/// Supabase (app_config.min_required_version)، ومفيش طريقة تتخطاها
/// غير تثبيت نسخة أحدث فعلياً.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AsjLogo(size: 56),
                  const SizedBox(height: 24),
                  const Icon(Icons.system_update_alt,
                      size: 56, color: AppColors.primary),
                  const SizedBox(height: 20),
                  const Text(
                    'فيه نسخة جديدة من التطبيق',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'النسخة اللي عندك قديمة ومحتاجة تحديث قبل ما تقدر تستخدم التطبيق. كلّم المسؤول عندك عشان يبعتلك آخر نسخة (APK) وثبّتها بدل الحالية.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}