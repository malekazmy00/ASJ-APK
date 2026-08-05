/// يطابق جدول user_sessions الجديد (راجع migrations/001).
class UserSession {
  final int? id;
  final String username;
  final DateTime? loginAt;
  final DateTime? lastActivityAt;
  final DateTime? logoutAt;
  final String? deviceInfo;

  const UserSession({
    this.id,
    required this.username,
    this.loginAt,
    this.lastActivityAt,
    this.logoutAt,
    this.deviceInfo,
  });

  factory UserSession.fromMap(Map<String, dynamic> map) {
    return UserSession(
      id: map['id'] as int?,
      username: map['username'] as String? ?? '',
      loginAt: map['login_at'] != null
          ? DateTime.tryParse(map['login_at'].toString())
          : null,
      lastActivityAt: map['last_activity_at'] != null
          ? DateTime.tryParse(map['last_activity_at'].toString())
          : null,
      logoutAt: map['logout_at'] != null
          ? DateTime.tryParse(map['logout_at'].toString())
          : null,
      deviceInfo: map['device_info'] as String?,
    );
  }

  /// مدة الجلسة (لحد الخروج، أو لحد آخر نشاط لو لسه مفتوحة).
  Duration? get duration {
    final start = loginAt;
    if (start == null) return null;
    final end = logoutAt ?? lastActivityAt;
    if (end == null) return null;
    return end.difference(start);
  }
}
