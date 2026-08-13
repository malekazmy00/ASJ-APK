/// الأدوار الثلاثة في النظام، مطابقة لما هو معمول به حالياً.
enum UserRole { worker, engineer, admin }

UserRole userRoleFromString(String value) {
  switch (value.toLowerCase()) {
    case 'engineer':
      return UserRole.engineer;
    case 'admin':
      return UserRole.admin;
    case 'worker':
    default:
      return UserRole.worker;
  }
}

/// يمثل صف واحد من جدول `users` في Supabase.
/// ملاحظة مهمة: المفتاح الأساسي في الجدول الحقيقي هو `username` نفسه
/// (String) وليس `id` (uuid) — الجدول لا يستخدم Supabase Auth أصلاً،
/// بل نظام Argon2 + JWT مخصص. راجع features/auth/data/auth_service.dart
/// لتفاصيل كيفية التعامل مع هذا الاختلاف.
class AppUser {
  final String username;
  final UserRole role;
  final bool canExport;
  final bool canTrack;
  final bool canEdit;
  final String status;

  /// توكن الدخول الموقّع من السيرفر (JWT) — بيثبت الهوية في أي عملية
  /// حساسة (admin functions, open-session, change-password...). ملحوظة
  /// مهمة: مش بيتخزن جوه toMap()/SharedPreferences مع باقي بيانات
  /// اليوزر — بيتخزن بشكل منفصل عبر SecureTokenStorage (Keychain/
  /// Keystore) لأنه أهم بكتير أمنياً من باقي البيانات دي.
  final String? token;

  const AppUser({
    required this.username,
    required this.role,
    this.canExport = false,
    this.canTrack = false,
    this.canEdit = false,
    this.status = 'Active',
    this.token,
  });

  factory AppUser.fromMap(Map<String, dynamic> map, {String? token}) {
    return AppUser(
      username: map['username'] as String? ?? '',
      role: userRoleFromString(map['role'] as String? ?? 'worker'),
      canExport: map['can_export'] as bool? ?? false,
      canTrack: map['can_track'] as bool? ?? false,
      canEdit: map['can_edit'] as bool? ?? false,
      status: map['status'] as String? ?? 'Active',
      token: token,
    );
  }

  AppUser copyWithToken(String? newToken) {
    return AppUser(
      username: username,
      role: role,
      canExport: canExport,
      canTrack: canTrack,
      canEdit: canEdit,
      status: status,
      token: newToken,
    );
  }

  /// لتخزين حالة الدخول محلياً (SharedPreferences) عشان الحساب يفضل
  /// مسجّل دخول حتى بعد إغلاق التطبيق فعلياً، من غير الحاجة لكلمة
  /// المرور تاني — الخروج الوحيد الحقيقي هو زرار الخروج الصريح.
  /// ملحوظة: التوكن عمداً مش موجود هنا — راجع تعليق `token` فوق.
  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'role': role.name,
      'can_export': canExport,
      'can_track': canTrack,
      'can_edit': canEdit,
      'status': status,
    };
  }
}