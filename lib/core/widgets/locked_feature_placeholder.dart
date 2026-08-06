import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// يُعرض جوه أي تبويب ظاهر شكلياً لكل المستخدمين لكن مش متاح للمستخدم
/// الحالي دلوقتي (سواء بسبب الدور أو صلاحية لسه متفعّلتش). رسالة واحدة
/// موحّدة دايماً — من غير ما نوضح السبب أو نميّز الشكل حسب نوع القفل.
class LockedFeaturePlaceholder extends StatelessWidget {
  const LockedFeaturePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 46, color: AppColors.textMuted),
            const SizedBox(height: 14),
            const Text(
              'الميزة غير مفعّلة حالياً',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'يمكنك التواصل مع الأدمن.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}