/// يطابق core/models.py -> Notification (جدول admin_notifications)
/// + عمودي notif_type وrelated_id الجداد (migrations/003).
class AppNotification {
  final int? notifId;
  final String message;
  final bool isRead;
  final DateTime? timestamp;
  final String? notifType;
  final int? relatedId; // id في pending_approvals لو الإشعار محتاج تأكيد

  const AppNotification({
    this.notifId,
    required this.message,
    this.isRead = false,
    this.timestamp,
    this.notifType,
    this.relatedId,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      notifId: map['notif_id'] as int?,
      message: map['message'] as String? ?? '',
      isRead: map['is_read'] as bool? ?? false,
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString())
          : null,
      notifType: map['notif_type'] as String?,
      relatedId: map['related_id'] as int?,
    );
  }
}