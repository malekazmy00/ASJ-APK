/// يطابق core/models.py -> InventoryItem (جدول inventory_items)
/// + الأعمدة الجديدة (راجع migrations/002 و003).
/// ملاحظة: الاسم الكودي/موديل القطعة نفسها (part_model) مش هنا — هو
/// صفة لنوع القطعة زي البراند بالظبط، فمكانه specs_knowledge_base
/// (راجع KnowledgeBaseEntry.partModel) مش هنا.
class InventoryItem {
  final int? itemId;
  final String itemType;
  final String partNumber;
  final String? description; // للإدخال من غير رقم قطعة
  final String? notes;
  final String entryType; // Part / Equipment
  final String? location;
  final String? condition;
  final String? imagePath; // مؤجل استخدامه حالياً (راجع قرار تأجيل الصور)
  final String? ocrText;
  final String status;
  final String? serialNumber;
  final String ownershipStatus; // Owned / Maintenance / Custody / Trial
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InventoryItem({
    this.itemId,
    this.itemType = 'بوردة',
    required this.partNumber,
    this.description,
    this.notes,
    this.entryType = 'Part',
    this.location,
    this.condition,
    this.imagePath,
    this.ocrText,
    this.status = 'Available',
    this.serialNumber,
    this.ownershipStatus = 'Owned',
    this.createdAt,
    this.updatedAt,
  });

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      itemId: map['item_id'] as int?,
      itemType: map['item_type'] as String? ?? 'بوردة',
      partNumber: map['part_number'] as String? ?? 'PENDING',
      description: map['description'] as String?,
      notes: map['notes'] as String?,
      entryType: map['entry_type'] as String? ?? 'Part',
      location: map['location'] as String?,
      condition: map['condition'] as String?,
      imagePath: map['image_path'] as String?,
      ocrText: map['ocr_text'] as String?,
      status: map['status'] as String? ?? 'Available',
      serialNumber: map['serial_number'] as String?,
      ownershipStatus: map['ownership_status'] as String? ?? 'Owned',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'item_type': itemType,
      'part_number': partNumber,
      if (description != null) 'description': description,
      if (notes != null) 'notes': notes,
      'entry_type': entryType,
      if (location != null) 'location': location,
      if (condition != null) 'condition': condition,
      if (serialNumber != null) 'serial_number': serialNumber,
      'status': status,
      'ownership_status': ownershipStatus,
    };
  }
}