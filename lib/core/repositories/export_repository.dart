import 'package:supabase_flutter/supabase_flutter.dart';

/// بيانات التصدير الخام — بيرجع كل صف كـ Map زي ما هو من القاعدة
/// (من غير تحويل لموديل)، عشان التصدير يفضل متزامن تلقائياً مع أي
/// عمود جديد يتضاف للجدول من غير ما نعدّل الكود هنا.
class ExportRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getFullInventory() async {
    final rows = await _client.from('inventory_items').select().order('item_id');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getAvailableInventory() async {
    final rows = await _client
        .from('inventory_items')
        .select()
        .eq('status', 'Available')
        .order('item_id');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getDispatchedInventory() async {
    final rows = await _client
        .from('inventory_items')
        .select()
        .eq('status', 'Out')
        .order('item_id');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getKnowledgeBase() async {
    final rows = await _client
        .from('specs_knowledge_base')
        .select()
        .order('Part_Number');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getTransactionLog() async {
    final rows = await _client
        .from('transactions_log')
        .select()
        .order('timestamp', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }
}