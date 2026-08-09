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

  /// ============================================================
  /// الجولة الثالثة (نقطة ٢ و٣): تبويب المخزون + تبويب البحث بالبطاقات
  /// المجمّعة — بدل صف لكل قطعة فعلية، بطاقة واحدة لكل "نوع" (رقم قطعة
  /// أو موديل معروف، أو وصف متطابق للقطع اللي من غير رقم قطعة) مع عدد
  /// المتاح والإجمالي.
  ///
  /// التجميع بيتم في Dart مش SQL View، عشان يغطي الحالتين مع بعض (رقم
  /// قطعة موجود / مش موجود) في استعلام واحد بسيط، ومايتقفلش على شكل
  /// View ممكن يبقى مش متزامن مع القاعدة الحقيقية.
  /// ============================================================

  /// مفتاح تجميع البطاقة: "pn:<رقم القطعة>" لو موجود، وإلا
  /// "desc:<الوصف بعد التريم>" — يُستخدم كـ groupKey في البطاقة وفي
  /// getByGroupKey لجيب القطع الفعلية جواها.
  String _groupKeyFor(Map<String, dynamic> item) {
    final pn = item['part_number'] as String?;
    final hasPartNumber = pn != null && pn.isNotEmpty && pn != 'PENDING';
    if (hasPartNumber) return 'pn:$pn';
    final desc = (item['description'] as String?)?.trim();
    return 'desc:${(desc == null || desc.isEmpty) ? 'غير محدد' : desc}';
  }

  /// كل بطاقات المجموعات (لتبويب المخزون وجزء التوفر في تبويب البحث).
  /// كل عنصر في الرجعة: group_key, display_name, item_type, brand,
  /// has_part_number, total_count, available_count.
  Future<List<Map<String, dynamic>>> getGroupedInventory() async {
    final itemRows = await _client.from('inventory_items').select();
    final items = (itemRows as List).cast<Map<String, dynamic>>();

    final partNumbers = items
        .map((r) => r['part_number'] as String?)
        .where((p) => p != null && p.isNotEmpty && p != 'PENDING')
        .cast<String>()
        .toSet();

    final kbByPartNumber = <String, Map<String, dynamic>>{};
    if (partNumbers.isNotEmpty) {
      final kbRows = await _client
          .from('specs_knowledge_base')
          .select('Part_Number, Part_Model, Brand')
          .inFilter('Part_Number', partNumbers.toList());
      for (final r in kbRows as List) {
        kbByPartNumber[r['Part_Number'] as String] = r as Map<String, dynamic>;
      }
    }

    final groups = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final pn = item['part_number'] as String?;
      final desc = (item['description'] as String?)?.trim();
      final hasPartNumber = pn != null && pn.isNotEmpty && pn != 'PENDING';
      final key = _groupKeyFor(item);

      final kb = hasPartNumber ? kbByPartNumber[pn] : null;
      final displayName = (kb?['Part_Model'] as String?) ??
          (hasPartNumber
              ? pn
              : ((desc == null || desc.isEmpty) ? 'غير محدد' : desc));

      final g = groups.putIfAbsent(
          key,
          () => {
                'group_key': key,
                'display_name': displayName,
                'item_type': item['item_type'],
                'brand': kb?['Brand'],
                'has_part_number': hasPartNumber,
                'total_count': 0,
                'available_count': 0,
              });
      g['total_count'] = (g['total_count'] as int) + 1;
      if (item['status'] == 'Available') {
        g['available_count'] = (g['available_count'] as int) + 1;
      }
    }

    final result = groups.values.toList();
    result.sort(
        (a, b) => (b['total_count'] as int).compareTo(a['total_count'] as int));
    return result;
  }

  /// كل القطع الفعلية جوه مجموعة معينة (نفس groupKey من
  /// getGroupedInventory) — تُستخدم في شاشة "بطاقات القطع الفردية"
  /// بعد ما المستخدم يدوس على بطاقة المجموعة.
  Future<List<InventoryItem>> getByGroupKey(String groupKey) async {
    if (groupKey.startsWith('pn:')) {
      return getByPartNumber(groupKey.substring(3));
    }
    final desc =
        groupKey.startsWith('desc:') ? groupKey.substring(5) : groupKey;
    if (desc == 'غير محدد') {
      final rows = await _client
          .from('inventory_items')
          .select()
          .or('description.is.null,description.eq.')
          .order('created_at', ascending: false);
      return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
    }
    final rows = await _client
        .from('inventory_items')
        .select()
        .eq('description', desc)
        .order('created_at', ascending: false);
    return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
  }

  /// اسم قديم كان بيعتمد على View (`inventory_items_grouped`) مش
  /// مضمون وجودها/تحديثها فعلياً — استُبدل بـ getGroupedInventory
  /// اللي بيحسب التجميع مباشرة من الجدول، وبيغطي حالة القطع من غير
  /// رقم قطعة كمان (كانت الـ View القديمة بتغطي رقم القطعة بس).
  @Deprecated('استخدم getGroupedInventory بدل ده')
  Future<List<Map<String, dynamic>>> getGroupedByPartNumber() =>
      getGroupedInventory();

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