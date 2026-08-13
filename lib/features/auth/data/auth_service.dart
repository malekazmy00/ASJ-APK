import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/app_user.dart';

/// قرار معماري (بديل عن الخيار السابق القائم على Supabase Auth):
/// جدول `users` الحالي مفتاحه الأساسي `username` نفسه، وكلمة المرور
/// مخزنة كـ hash بـ Argon2 داخل عمود `password` — تماماً كما في النظام
/// الأصلي (core/security.py). للحفاظ على نفس البيانات والمستخدمين
/// الحاليين بدون أي هجرة أو إعادة تسجيل، تم الإبقاء على نفس آلية
/// التحقق، لكن عبر Supabase Edge Function باسم `login-user`
/// (راجع supabase/functions/login-user/index.ts) بدل تنفيذ Argon2 على
/// الجهاز مباشرة (غير آمن ولوجستياً غير عملي في Dart/Flutter).
///
/// ملاحظة أمان (محدّثة): هذا التصميم لسه ما بيستخدمش Supabase Auth ولا
/// auth.uid()، وسياسات RLS المبنية عليه لسه معطّلة عمداً — نموذج الثقة
/// لسه على مستوى التطبيق مش الداتابيز، زي نسخة Streamlit الأصلية.
/// لكن بقى فيه طبقة توثيق حقيقية فوق كده: login-user بعد نجاح التحقق
/// بيولّد custom JWT موقّع من السيرفر (راجع supabase/functions/_shared/
/// auth.ts)، وأي Edge Function حساسة (admin-create-user، admin-reset-
/// password، open-session، resolve-approval، change-password) بقت
/// بتتحقق من التوكن ده بنفسها قبل أي تنفيذ — مش بس بتفترض إن الطلب
/// جاي من واجهة الأدمن.
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<AppUser?> signIn({
    required String username,
    required String password,
  }) async {
    final response = await _client.functions.invoke(
      'login-user',
      body: {'username': username, 'password': password},
    );

    if (response.status != 200) return null;

    final data = response.data as Map<String, dynamic>?;
    if (data == null || data['success'] != true) return null;

    return AppUser.fromMap(
      data['user'] as Map<String, dynamic>,
      token: data['token'] as String?,
    );
  }

  Future<void> signOut() async {
    // لا يوجد Supabase Auth session للخروج منها؛ حالة الدخول محفوظة
    // فقط داخل AuthController (Riverpod) على الجهاز.
  }
}
