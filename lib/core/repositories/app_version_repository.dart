import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_logger.dart';

/// الجولة الثالثة (نقطة ٢٢) — إجبار التحديث: يقارن نسخة التطبيق
/// المثبتة بأقل نسخة مسموح بيها، المخزّنة في جدول app_config على
/// Supabase (مفتاح 'min_required_version'). لو التطبيق المثبت أقدم،
/// لازم يحدّث قبل ما يدخل خالص.
///
/// **عشان تحدّث الحد الأدنى لاحقاً وتوقف نسخة قديمة**: شغّل على
/// Supabase SQL Editor:
///   UPDATE app_config SET value = '0.2.0' WHERE key = 'min_required_version';
/// (غيّر '0.2.0' برقم النسخة اللي عايز تجبر عليها — أي تطبيق مثبت
/// عنده نسخة أقدم هيتوقف تلقائياً من غير أي حاجة تانية).
///
/// **ملحوظة مهمة**: كل مرة تعمل build جديد بميزات فعلية عايز تضمن إن
/// كل حد يستخدمها، لازم كمان ترفع رقم `version:` في pubspec.yaml قبل
/// الـ build (زي 0.1.0 → 0.2.0) — رقم النسخة في pubspec هو اللي بيتقارن
/// بالحد الأدنى ده، مش رقم عشوائي.
class AppVersionRepository {
  final _client = Supabase.instance.client;

  /// بيرجع true لو التطبيق المثبت أقدم من الحد الأدنى المطلوب. أي
  /// فشل في الفحص نفسه (مفيش نت، القاعدة واقعة...) بيرجع false —
  /// أفضل نسيب المستخدم يدخل بدل ما نقفل التطبيق بالكامل بسبب فشل
  /// فحص، مش بسبب النسخة فعلاً قديمة.
  Future<bool> isUpdateRequired() async {
    try {
      final rows = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'min_required_version')
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return false;
      final minVersion = list.first['value'] as String?;
      if (minVersion == null || minVersion.trim().isEmpty) return false;

      final info = await PackageInfo.fromPlatform();
      return _isOlder(info.version, minVersion.trim());
    } catch (e, st) {
      AppLogger.logError('AppVersionRepository.isUpdateRequired', e, st);
      return false;
    }
  }

  /// مقارنة نسخ بسيطة على شكل "1.2.3" — رقم برقم، ولو عدد الأجزاء
  /// مختلف بين النسختين بيكمّل الناقص بصفر (مثلاً "1.2" == "1.2.0").
  bool _isOlder(String current, String minimum) {
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final m = minimum.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final len = c.length > m.length ? c.length : m.length;
    for (var i = 0; i < len; i++) {
      final cv = i < c.length ? c[i] : 0;
      final mv = i < m.length ? m[i] : 0;
      if (cv != mv) return cv < mv;
    }
    return false; // متساويين بالظبط
  }
}