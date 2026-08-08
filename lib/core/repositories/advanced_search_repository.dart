import 'package:supabase_flutter/supabase_flutter.dart';

/// بحث متقدم (أدمن فقط): يدور في أي نص مخزّن حتى لو ملاحظة حرة أو
/// نص تحليل Gemini، مش بس الحقول المنظّمة زي البحث العادي.
class AdvancedSearchRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> searchInventory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final rows = await _client
        .from('inventory_items')
        .select()
        .or(
          'part_number.ilike.%$trimmed%,'
          'serial_number.ilike.%$trimmed%,'
          'description.ilike.%$trimmed%,'
          'notes.ilike.%$trimmed%,'
          'location.ilike.%$trimmed%',
        )
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> searchKnowledgeBase(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final rows = await _client
        .from('specs_knowledge_base')
        .select()
        .or(
          'Part_Number.ilike.%$trimmed%,'
          'Part_Model.ilike.%$trimmed%,'
          'Brand.ilike.%$trimmed%,'
          'Category.ilike.%$trimmed%,'
          'Compatible_Model.ilike.%$trimmed%,'
          'Additional_Compatibility.ilike.%$trimmed%,'
          'Gemini_Insights.ilike.%$trimmed%',
        )
        .limit(100);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> searchQueries(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final rows = await _client
        .from('engineer_queries')
        .select()
        .or(
          'part_number.ilike.%$trimmed%,'
          'part_category.ilike.%$trimmed%,'
          'target_device.ilike.%$trimmed%,'
          'merchant_name.ilike.%$trimmed%,'
          'comments.ilike.%$trimmed%',
        )
        .order('timestamp', ascending: false)
        .limit(100);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> searchLog(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final rows = await _client
        .from('transactions_log')
        .select()
        .ilike('details', '%$trimmed%')
        .order('timestamp', ascending: false)
        .limit(100);
    return (rows as List).cast<Map<String, dynamic>>();
  }
}