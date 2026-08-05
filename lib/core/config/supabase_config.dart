/// إعدادات الاتصال بـ Supabase.
///
/// مهم: لا تضع القيم الحقيقية هنا مباشرة في كود مرفوع لريبو عام.
/// استخدم متغيرات بيئة عبر --dart-define عند البناء على Codemagic:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
