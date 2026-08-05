/// يطابق core/models.py -> KnowledgeBase (جدول specs_knowledge_base).
/// تنبيه: أسماء الأعمدة في القاعدة نفسها بحروف كبيرة (Part_Number, Brand,
/// ...) كما هي، لازم تُستخدم بنفس الحالة (case) بالضبط في كل استعلام.
class KnowledgeBaseEntry {
  final String partNumber;
  final String? brand;
  final String? category;
  final String? compatibleModel;
  final String? additionalCompatibility;
  final String? marketValue;
  final String? geminiInsights;
  final DateTime? lastUpdated;

  const KnowledgeBaseEntry({
    required this.partNumber,
    this.brand,
    this.category,
    this.compatibleModel,
    this.additionalCompatibility,
    this.marketValue,
    this.geminiInsights,
    this.lastUpdated,
  });

  factory KnowledgeBaseEntry.fromMap(Map<String, dynamic> map) {
    return KnowledgeBaseEntry(
      partNumber: map['Part_Number'] as String? ?? '',
      brand: map['Brand'] as String?,
      category: map['Category'] as String?,
      compatibleModel: map['Compatible_Model'] as String?,
      additionalCompatibility: map['Additional_Compatibility'] as String?,
      marketValue: map['market_value'] as String?,
      geminiInsights: map['Gemini_Insights'] as String?,
      lastUpdated: map['last_updated'] != null
          ? DateTime.tryParse(map['last_updated'].toString())
          : null,
    );
  }
}
