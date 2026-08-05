import 'enums.dart';

/// يطابق core/models.py -> TransactionLog (جدول transactions_log).
/// هذا هو المصدر المشترك للتايم لاين في: تتبع القطعة، تتبع المستخدم،
/// وأي شاشة نشاط عامة (المرحلة 3).
class TransactionLog {
  final int? logId;
  final int? itemId;
  final ActionType actionType;
  final String? username;
  final String? details;
  final DateTime? timestamp;

  const TransactionLog({
    this.logId,
    this.itemId,
    required this.actionType,
    this.username,
    this.details,
    this.timestamp,
  });

  factory TransactionLog.fromMap(Map<String, dynamic> map) {
    return TransactionLog(
      logId: map['log_id'] as int?,
      itemId: map['item_id'] as int?,
      actionType: ActionType.fromDb(map['action_type'] as String?),
      username: map['username'] as String?,
      details: map['details'] as String?,
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString())
          : null,
    );
  }
}
