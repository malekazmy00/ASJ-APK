/// يطابق core/models.py -> Notification (جدول admin_notifications).
class AppNotification {
  final int? notifId;
  final String message;
  final bool isRead;
  final DateTime? timestamp;

  const AppNotification({
    this.notifId,
    required this.message,
    this.isRead = false,
    this.timestamp,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      notifId: map['notif_id'] as int?,
      message: map['message'] as String? ?? '',
      isRead: map['is_read'] as bool? ?? false,
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString())
          : null,
    );
  }
}
