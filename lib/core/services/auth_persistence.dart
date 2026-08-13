import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import 'app_logger.dart';
import 'secure_token_storage.dart';

/// تخزين محلي: حالة الدخول (عرض فقط — اسم/دور/صلاحيات في
/// SharedPreferences) واسم المستخدم المتذكَّر لوحده (يفضل موجود حتى
/// بعد تسجيل الخروج الصريح، عشان يظهر جاهز في شاشة الدخول المرة
/// الجاية).
///
/// TASK-302 (محدّث): وجود بيانات محلية هنا مبقاش لوحده كافي يعتبر
/// المستخدم "مسجّل دخول". لازم كمان توكن موقّع من السيرفر (JWT) لسه
/// ساري — محفوظ بشكل منفصل عبر SecureTokenStorage (Keychain/Keystore،
/// أأمن من SharedPreferences العادي). لو التوكن مفقود أو منتهي شكلياً،
/// restoreUser() بترجّع null (يعني المستخدم يحتاج يدخل تاني) حتى لو
/// بيانات AppUser القديمة لسه موجودة محلياً. الأهم: حتى لو التوكن نفسه
/// موجود وسليم شكلياً، كل عملية حساسة (admin/session/password) بتتحقق
/// منه على السيرفر بنفسها في كل مرة — مش بتثق في مجرد وجوده على الجهاز.
class AuthPersistence {
  static const _userKey = 'asj_logged_in_user';
  static const _rememberedUsernameKey = 'asj_remembered_username';

  static Future<void> saveUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toMap()));
    await prefs.setString(_rememberedUsernameKey, user.username);
    if (user.token != null) {
      await SecureTokenStorage.save(user.token!);
    }
  }

  static Future<AppUser?> restoreUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;

    final token = await SecureTokenStorage.read();
    if (token == null || SecureTokenStorage.isExpired(token)) {
      // مفيش توكن ساري — مش هنعتبره مسجّل دخول، ونشيل البيانات
      // المحلية القديمة عشان مايفضلش شكل "مسجّل دخول" وهمي.
      await clearUser();
      return null;
    }

    try {
      return AppUser.fromMap(jsonDecode(raw) as Map<String, dynamic>, token: token);
    } catch (e, st) {
      AppLogger.logError('AuthPersistence.restoreUser', e, st);
      return null;
    }
  }

  /// بيتشال وقت الخروج الصريح بس — اسم المستخدم المتذكَّر يفضل زي ما هو.
  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await SecureTokenStorage.clear();
  }

  static Future<String?> getRememberedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rememberedUsernameKey);
  }
}