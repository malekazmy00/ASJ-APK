import 'enums.dart';

/// يطابق جدول pending_approvals الجديد (migrations/003).
class PendingApproval {
  final int? id;
  final ApprovalType approvalType;
  final Map<String, dynamic> payload;
  final String? requestedBy;
  final ApprovalStatus status;
  final DateTime? createdAt;
  final String? resolvedBy;
  final DateTime? resolvedAt;

  const PendingApproval({
    this.id,
    required this.approvalType,
    required this.payload,
    this.requestedBy,
    this.status = ApprovalStatus.pending,
    this.createdAt,
    this.resolvedBy,
    this.resolvedAt,
  });

  factory PendingApproval.fromMap(Map<String, dynamic> map) {
    return PendingApproval(
      id: map['id'] as int?,
      approvalType: ApprovalType.fromDb(map['approval_type'] as String?),
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
      requestedBy: map['requested_by'] as String?,
      status: ApprovalStatus.fromDb(map['status'] as String?),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      resolvedBy: map['resolved_by'] as String?,
      resolvedAt: map['resolved_at'] != null
          ? DateTime.tryParse(map['resolved_at'].toString())
          : null,
    );
  }
}