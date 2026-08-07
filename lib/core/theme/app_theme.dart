import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// نظام الألوان الأساسي للتطبيق — أبيض/فيروزي(سماوي)/كحلي، هوية ASJ
/// الفعلية (مأخوذة من style.css الأصلي). الشكل الجديد (راجع round 2):
/// خلفية بيضا بالكامل، فواصل فيروزي، والكحلي بقى لون "التفعيل/التحديد"
/// (التبويب النشط، الحالة المختارة) بدل ما يكون خلفية شاملة للـ AppBar.
class AppColors {
  static const Color primary = Color(0xFF0A2540); // كحلي - لون "النشط/المُحدَّد"
  static const Color primaryDark = Color(0xFF061A2E);
  static const Color accent = Color(0xFF00D2FF); // سماوي/فيروزي - الفواصل والحدود
  static const Color textMuted = Color(0xFF64748B);
  static const Color background = Colors.white;
  static const Color surface = Colors.white;
  static const Color danger = Color(0xFFD64550);
  static const Color warning = Color(0xFFE0A100);
  static const Color success = Color(0xFF2E8B57);

  // ألوان الأدوار القديمة - محتفظ بيها لأي كود قديم لسه بيرجعلها،
  // مش مستخدمة في التصميم الموحّد الجديد.
  static const Color roleWorker = Color(0xFF3D5AFE);
  static const Color roleEngineer = Color(0xFF00897B);
  static const Color roleAdmin = Color(0xFF8E24AA);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE9EEF1), width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
          minimumSize: const Size(0, 40),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.accent, width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          minimumSize: const Size(0, 38),
          textStyle: const TextStyle(fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          minimumSize: const Size(0, 36),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE9EEF1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE9EEF1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}