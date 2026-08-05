/// يطابق core/models.py -> EngineerQuery (جدول engineer_queries).
class EngineerQuery {
  final int? queryId;
  final String username;
  final String partNumber;
  final String? partCategory;
  final String? partDescription;
  final String queryReason;
  final String? requestedBy;
  final String? targetDevice;
  final String? merchantName;
  final String? merchantPhone;
  final String? comments;
  final String status;
  final DateTime? timestamp;

  const EngineerQuery({
    this.queryId,
    required this.username,
    required this.partNumber,
    this.partCategory,
    this.partDescription,
    required this.queryReason,
    this.requestedBy,
    this.targetDevice,
    this.merchantName,
    this.merchantPhone,
    this.comments,
    this.status = 'Pending',
    this.timestamp,
  });

  factory EngineerQuery.fromMap(Map<String, dynamic> map) {
    return EngineerQuery(
      queryId: map['query_id'] as int?,
      username: map['username'] as String? ?? '',
      partNumber: map['part_number'] as String? ?? '',
      partCategory: map['part_category'] as String?,
      partDescription: map['part_description'] as String?,
      queryReason: map['query_reason'] as String? ?? '',
      requestedBy: map['requested_by'] as String?,
      targetDevice: map['target_device'] as String?,
      merchantName: map['merchant_name'] as String?,
      merchantPhone: map['merchant_phone'] as String?,
      comments: map['comments'] as String?,
      status: map['status'] as String? ?? 'Pending',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString())
          : null,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'username': username,
      'part_number': partNumber,
      if (partCategory != null) 'part_category': partCategory,
      if (partDescription != null) 'part_description': partDescription,
      'query_reason': queryReason,
      if (requestedBy != null) 'requested_by': requestedBy,
      if (targetDevice != null) 'target_device': targetDevice,
      if (merchantName != null) 'merchant_name': merchantName,
      if (merchantPhone != null) 'merchant_phone': merchantPhone,
      if (comments != null) 'comments': comments,
      'status': status,
    };
  }
}
