import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_item.dart';

/// يطابق repositories/item_repo.py من النظام الأصلي.
class InventoryRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<InventoryItem?> getById(int itemId) async {
    final rows = await _client
        .from('inventory_items')
        .select()
        .eq('item_id', itemId)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return InventoryItem.fromMap(list.first);
  }

  /// كل القطع بترتيب زمني - تُستخدم في شاشة الاستيكرات (تصفح مباشر
  /// من غير بحث إجباري) وأي شاشة تانية محتاجة قائمة كاملة.
  Future<List<InventoryItem>> getAll({int limit = 300}) async {
    final rows = await _client
        .from('inventory_items')
        .select()
        .order('item_id', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
  }

  Future<List<InventoryItem>> getByPartNumber(String partNumber) async {
    final rows = await _client
        .from('inventory_items')
        .select()
        .eq('part_number', partNumber)
        .order('created_at');
    return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
  }

  /// بحث موحّد بالـ ID أو رقم القطعة أو السريال أو الموديل (الاسم
  /// الكودي في قاعدة المعرفة) أو الوصف — نفس البحث المستخدم في كل
  /// شاشات المهندس/العامل.
  Future<List<InventoryItem>> smartSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final asInt = int.tryParse(trimmed);

    // لو النص اتطابق مع موديل (اسم كودي) في قاعدة المعرفة، هات كل
    // أرقام القطع المرتبطة بيه كمان
    final kbRows = await _client
        .from('specs_knowledge_base')
        .select('Part_Number')
        .ilike('Part_Model', '%$trimmed%')
        .limit(50);
    final modelPartNumbers =
        (kbRows as List).map((r) => r['Part_Number'] as String).toSet();

    final orParts = <String>[
      'part_number.ilike.%$trimmed%',
      'serial_number.ilike.%$trimmed%',
      'description.ilike.%$trimmed%',
    ];
    if (asInt != null) orParts.add('item_id.eq.$asInt');
    for (final pn in modelPartNumbers) {
      orParts.add('part_number.eq.${pn.replaceAll(',', '')}');
    }

    final rows = await _client
        .from('inventory_items')
        .select()
        .or(orParts.join(','))
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