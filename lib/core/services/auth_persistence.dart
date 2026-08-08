import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';

/// تخزين محلي بسيط: حالة الدخول الكاملة (عشان الحساب يفضل مسجّل
/// دخول بعد إغلاق التطبيق فعلياً)، واسم المستخدم المتذكَّر لوحده
/// (يفضل موجود حتى بعد تسجيل الخروج الصريح، عشان يظهر جاهز في
/// شاشة الدخول المرة الجاية).
class AuthPersistence {
  static const _userKey = 'asj_logged_in_user';
  static const _rememberedUsernameKey = 'asj_remembered_username';

  static Future<void> saveUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toMap()));
    await prefs.setString(_rememberedUsernameKey, user.username);
  }

  static Future<AppUser?> restoreUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    try {
      return AppUser.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// بيتشال وقت الخروج الصريح بس — اسم المستخدم المتذكَّر يفضل زي ما هو.
  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }

  static Future<String?> getRememberedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rememberedUsernameKey);
  }
}