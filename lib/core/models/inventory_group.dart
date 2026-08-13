/// TASK-320: تمثيل مكتوب (typed) لنتيجة تجميع المخزون، بدل
/// Map<String, dynamic> خام. نفس البيانات بالظبط اللي كانت بترجع من
/// InventoryRepository.getGroupedInventory قبل كده، لكن بأنواع محددة
/// عشان نقلل احتمال أخطاء runtime (زي "as int" على قيمة null غير
/// متوقعة) — مفيش أي تغيير في البيانات نفسها أو شكل الشاشة.
class InventoryGroup {
  final String groupKey;
  final String displayName;
  final String? itemType;
  final String? brand;
  final bool hasPartNumber;
  final int totalCount;
  final int availableCount;
  final int? minItemId;
  final DateTime? minCreatedAt;
  final DateTime? maxUpdatedAt;

  const InventoryGroup({
    required this.groupKey,
    required this.displayName,
    this.itemType,
    this.brand,
    this.hasPartNumber = false,
    this.totalCount = 0,
    this.availableCount = 0,
    this.minItemId,
    this.minCreatedAt,
    this.maxUpdatedAt,
  });

  factory InventoryGroup.fromMap(Map<String, dynamic> map) {
    return InventoryGroup(
      groupKey: map['group_key'] as String,
      displayName: map['display_name'] as String? ?? 'غير محدد',
      itemType: map['item_type'] as String?,
      brand: map['brand'] as String?,
      hasPartNumber: map['has_part_number'] as bool? ?? false,
      totalCount: map['total_count'] as int? ?? 0,
      availableCount: map['available_count'] as int? ?? 0,
      minItemId: map['min_item_id'] as int?,
      minCreatedAt: map['min_created_at'] as DateTime?,
      maxUpdatedAt: map['max_updated_at'] as DateTime?,
    );
  }
}
