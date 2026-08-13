import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// تخزين آمن لتوكن الدخول (JWT) بمعزل عن AuthPersistence اللي بيخزن
/// بيانات المستخدم العادية (اسم/دور/صلاحيات) في SharedPreferences.
/// التوكن نفسه أهم بكتير أمنياً — هو اللي بيثبت الهوية على السيرفر في
/// كل عملية حساسة — فمحتاج Keychain (iOS) / Keystore (Android) مش
/// SharedPreferences العادي (اللي بيتخزن كـ plain text على الجهاز).
class SecureTokenStorage {
  static const _key = 'app_token';
  static const _storage = FlutterSecureStorage();

  static Future<void> save(String token) => _storage.write(key: _key, value: token);

  static Future<String?> read() => _storage.read(key: _key);

  static Future<void> clear() => _storage.delete(key: _key);

  /// فحص محلي بسيط (من غير أي تحقق من التوقيع — التحقق الحقيقي
  /// دايماً بيحصل على السيرفر مع كل عملية حساسة) بس عشان تجربة
  /// المستخدم: لو التوكن المحفوظ منتهي شكلياً، نطلب دخول تاني بدل ما
  /// نوري الشاشة الرئيسية لثانية وبعدين كل نداء يفشل بـ 401.
  static bool isExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
      final exp = payload['exp'] as int?;
      if (exp == null) return true;
      return DateTime.now().millisecondsSinceEpoch >= exp * 1000;
    } catch (_) {
      return true;
    }
  }
}
