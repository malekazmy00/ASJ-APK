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
/// ملاحظة أمان مهمة (بصراحة كاملة): هذا التصميم لا يستخدم Supabase Auth
/// ولا auth.uid()، وبالتالي سياسات RLS المبنية على auth.uid() لن تعمل
/// هنا. نموذج الثقة الحالي مطابق تماماً لما هو معمول به في نسخة
/// Streamlit الحالية: التحقق من الصلاحيات يتم على مستوى التطبيق (بعد
/// تسجيل الدخول عبر الدالة)، وليس على مستوى قاعدة البيانات. هذا ليس
/// تراجعاً عن الوضع الحالي، لكنه يستاهل تقوية لاحقاً (مثلاً: توليد
/// custom JWT من الدالة والتحقق منه في RLS) إذا حبينا نرفع مستوى الأمان
/// مستقبلاً.
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

    return AppUser.fromMap(data['user'] as Map<String, dynamic>);
  }

  Future<void> signOut() async {
    // لا يوجد Supabase Auth session للخروج منها؛ حالة الدخول محفوظة
    // فقط داخل AuthController (Riverpod) على الجهاز.
  }
}
