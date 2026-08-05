import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_item.dart';

/// يطابق repositories/item_repo.py من النظام الأصلي.
class InventoryRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<InventoryItem>> getByPartNumber(String partNumber) async {
    final rows = await _client
        .from('inventory_items')
        .select()
        .eq('part_number', partNumber)
        .order('created_at');
    return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
  }

  /// بحث نصي مرن (زي البحث الذكي عند المهندس) على part_number أو item_type.
  Future<List<InventoryItem>> smartSearch(String query) async {
    final rows = await _client
        .from('inventory_items')
        .select()
        .or('part_number.ilike.%$query%,item_type.ilike.%$query%')
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
  }

  Future<List<InventoryItem>> getFiltered({
    String? status,
    String? itemType,
    String? searchText,
    int limit = 200,
  }) async {
    var q = _client.from('inventory_items').select();
    if (status != null && status.isNotEmpty) {
      q = q.eq('status', status);
    }
    if (itemType != null && itemType.isNotEmpty) {
      q = q.eq('item_type', itemType);
    }
    if (searchText != null && searchText.isNotEmpty) {
      q = q.or('part_number.ilike.%$searchText%,location.ilike.%$searchText%');
    }
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
  }

  /// الداشبورد التجميعي (المرحلة 3): تجميع حسب part_number مع العدد.
  /// PostgREST لا يدعم GROUP BY مباشرة عبر select العادي، لذلك الأنسب
  /// إنشاء View جاهزة في Supabase (راجع migrations/002_grouped_view.sql)
  /// واستدعاؤها هنا بدل التجميع يدوياً على الجهاز.
  Future<List<Map<String, dynamic>>> getGroupedByPartNumber() async {
    final rows = await _client
        .from('inventory_items_grouped') // View — راجع ملف الـ migration
        .select()
        .order('qty', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<InventoryItem>> bulkInsert(List<InventoryItem> items) async {
    final rows = await _client
        .from('inventory_items')
        .insert(items.map((e) => e.toInsertMap()).toList())
        .select();
    return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
  }

  Future<void> updateStatus(int itemId, String status) async {
    await _client
        .from('inventory_items')
        .update({'status': status, 'updated_at': DateTime.now().toIso8601String()})
        .eq('item_id', itemId);
  }

  Future<void> updateFields(int itemId, Map<String, dynamic> fields) async {
    fields['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('inventory_items').update(fields).eq('item_id', itemId);
  }

  Future<void> deletePermanently(int itemId) async {
    await _client.from('inventory_items').delete().eq('item_id', itemId);
  }
}
