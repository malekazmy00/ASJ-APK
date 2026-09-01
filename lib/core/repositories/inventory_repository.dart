import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_group.dart';
import '../models/inventory_item.dart';
import '../services/error_messages.dart';

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
        .neq('status', 'Archived')
        .order('item_id', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
  }

  Future<List<InventoryItem>> getByPartNumber(String partNumber) async {
    final rows = await _client
        .from('inventory_items')
        .select()
        .eq('part_number', partNumber)
        .neq('status', 'Archived')
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

    // TASK-019: item_id بدل created_at — راجع migrations/019_inventory_created_at_fix.sql.
    // created_at كان بلا DEFAULT (593 من 865 قطعة كانت created_at
    // بتاعتها NULL)، فأي ترتيب بيه كان بيفقد القطع الأحدث من النتيجة.
    // item_id (PK متسلسل، مستحيل يبقى NULL) هو نفس منطق getAll()
    // (تاب الاستيكرات) المستقر أصلاً — وده بيضمن عدم تكرار نفس المشكلة
    // حتى لو حصل drift تاني في created_at مستقبلاً.
    final rows = await _client
        .from('inventory_items')
        .select()
        .or(orParts.join(','))
        .neq('status', 'Archived')
        .order('item_id', ascending: false)
        .limit(100);
    return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
  }

  Future<List<InventoryItem>> getFiltered({
    String? status,
    String? itemType,
    String? searchText,
    int limit = 200,
  }) async {
    var q = _client.from('inventory_items').select().neq('status', 'Archived');
    if (status != null && status.isNotEmpty) {
      q = q.eq('status', status);
    }
    if (itemType != null && itemType.isNotEmpty) {
      q = q.eq('item_type', itemType);
    }
    if (searchText != null && searchText.isNotEmpty) {
      q = q.or('part_number.ilike.%$searchText%,location.ilike.%$searchText%');
    }
    // TASK-019: نفس التعليل بالظبط اللي فوق في smartSearch — item_id
    // بدل created_at (راجع migrations/019_inventory_created_at_fix.sql).
    final rows = await q.order('item_id', ascending: false).limit(limit);
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

  /// اقتراحات نصية خفيفة لخانة البحث بشكل Autocomplete (الجولة الثالثة،
  /// نقطة ١٥+١٨): بترجع نصوص عرض بس (رقم قطعة/موديل/وصف) بتتطابق جزئياً
  /// مع النص، مش القطع نفسها — الشاشة اللي بتستخدمها هي اللي بتقرر
  /// تعمل ايه لما المستخدم يختار من القايمة (البحث الفعلي بيحصل وقتها
  /// بس، مش أثناء الكتابة).
  Future<List<String>> getSuggestions(String query, {int limit = 8}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final results = <String>{};

    final itemRows = await _client
        .from('inventory_items')
        .select('part_number, description')
        .or('part_number.ilike.%$trimmed%,description.ilike.%$trimmed%')
        .neq('status', 'Archived')
        .limit(limit * 3);
    for (final r in itemRows as List) {
      if (results.length >= limit) break;
      final pn = r['part_number'] as String?;
      final desc = r['description'] as String?;
      if (pn != null &&
          pn.isNotEmpty &&
          pn != 'PENDING' &&
          pn.toLowerCase().contains(trimmed.toLowerCase())) {
        results.add(pn);
      } else if (desc != null &&
          desc.isNotEmpty &&
          desc.toLowerCase().contains(trimmed.toLowerCase())) {
        results.add(desc);
      }
    }

    if (results.length < limit) {
      final kbRows = await _client
          .from('specs_knowledge_base')
          .select('Part_Model')
          .ilike('Part_Model', '%$trimmed%')
          .limit(limit);
      for (final r in kbRows as List) {
        if (results.length >= limit) break;
        final model = r['Part_Model'] as String?;
        if (model != null && model.isNotEmpty) results.add(model);
      }
    }

    return results.take(limit).toList();
  }

  /// كل بطاقات المجموعات (لتبويب المخزون وجزء التوفر في تبويب البحث).
  /// كل عنصر في الرجعة: group_key, display_name, item_type, brand,
  /// has_part_number, total_count, available_count.
  ///
  /// الجولة الثالثة (نقطة ١٩): بارامترات الفلترة/الترتيب الاختيارية —
  /// [presence] ('available' القطع الموجودة في المخزن / 'dispatched'
  /// المنصرفة / null الكل)، [ownershipStatus] (يفعل مع available بس)،
  /// [entryType] (برقم قطعة/معدة شغل/بدون رقم)، [exitType] (سبب
  /// الصرف: بيع/إعارة/تلف — يفعل مع dispatched بس، ومصدره
  /// transactions_log مش inventory_items فمحتاج خطوة جلب إضافية).
  /// [sortField]: 'total_count' (افتراضي) أو 'part_number' أو
  /// 'item_id' أو 'item_type' أو 'created_at' (تاريخ إضافة أقدم قطعة
  /// في المجموعة) أو 'updated_at' (تاريخ آخر حركة لأحدث قطعة في
  /// المجموعة). القيم الافتراضية (من غير أي بارامتر) بترجع نفس
  /// السلوك القديم بالظبط، عشان الشاشات التانية اللي بتنادي
  /// getGroupedInventory() من غير فلاتر (Batch B) تفضل شغالة زي ما هي.
  Future<List<InventoryGroup>> getGroupedInventory({
    String? presence,
    String? ownershipStatus,
    String? entryType,
    String? exitType,
    String sortField = 'total_count',
    bool ascending = false,
  }) async {
    // TASK-315: التجميع بقى بيتحسب في الداتابيز (SQL) في الحالة
    // الأساسية — بيرجع عدد "المجموعات" بس، مش كل القطع الفردية، مهما
    // كان حجم المخزون. فلترة سبب الصرف (exit_type) لسه بمسارها القديم
    // في Dart (محتاجة join مع transactions_log، حالة أضيق استخداماً).
    // شكل النتيجة والترتيب النهائي زي ما هو بالظبط في الحالتين.
    final rawResult = (presence == 'dispatched' && exitType != null)
        ? await _getGroupedInventoryLegacy(
            presence: presence,
            ownershipStatus: ownershipStatus,
            entryType: entryType,
            exitType: exitType,
          )
        : await _getGroupedInventoryViaRpc(
            presence: presence,
            ownershipStatus: ownershipStatus,
            entryType: entryType,
          );

    // TASK-320: تحويل لموديل مكتوب (InventoryGroup) بدل ما نفضل شغالين
    // على Map خام لحد الشاشة — نفس البيانات بالظبط.
    final groups = rawResult.map(InventoryGroup.fromMap).toList();

    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    int cmp(InventoryGroup a, InventoryGroup b) {
      switch (sortField) {
        case 'part_number':
          return a.displayName.compareTo(b.displayName);
        case 'item_id':
          return (a.minItemId ?? 0).compareTo(b.minItemId ?? 0);
        case 'item_type':
          return (a.itemType ?? '').compareTo(b.itemType ?? '');
        case 'created_at':
          return (a.minCreatedAt ?? epoch).compareTo(b.minCreatedAt ?? epoch);
        case 'updated_at':
          return (a.maxUpdatedAt ?? epoch).compareTo(b.maxUpdatedAt ?? epoch);
        default:
          return a.totalCount.compareTo(b.totalCount);
      }
    }

    groups.sort((a, b) => ascending ? cmp(a, b) : cmp(b, a));
    return groups;
  }

  /// TASK-315: نداء RPC واحد بيرجع المجموعات جاهزة (group_key,
  /// display_name, item_type, brand, has_part_number, total_count,
  /// available_count, min_item_id, min_created_at, max_updated_at) —
  /// نفس المفاتيح والأنواع بالظبط اللي كان بيرجّعها المسار القديم في
  /// Dart، عشان الشاشات المستهلكة (تبويب المخزون، تبويب البحث) تفضل
  /// شغالة من غير أي تعديل فيها. راجع migrations/011_grouped_inventory_rpc.sql.
  Future<List<Map<String, dynamic>>> _getGroupedInventoryViaRpc({
    String? presence,
    String? ownershipStatus,
    String? entryType,
  }) async {
    final rows = await _client.rpc('get_grouped_inventory', params: {
      'p_presence': presence,
      'p_ownership_status': ownershipStatus,
      'p_entry_type': entryType,
    });
    return (rows as List).map<Map<String, dynamic>>((r) {
      final map = r as Map<String, dynamic>;
      return {
        'group_key': map['group_key'],
        'display_name': map['display_name'],
        'item_type': map['item_type'],
        'brand': map['brand'],
        'has_part_number': map['has_part_number'] as bool? ?? false,
        'total_count': (map['total_count'] as num).toInt(),
        'available_count': (map['available_count'] as num).toInt(),
        'min_item_id': map['min_item_id'] as int?,
        'min_created_at': map['min_created_at'] != null
            ? DateTime.tryParse(map['min_created_at'].toString())
            : null,
        'max_updated_at': map['max_updated_at'] != null
            ? DateTime.tryParse(map['max_updated_at'].toString())
            : null,
      };
    }).toList();
  }

  /// المسار القديم (تجميع في Dart) — لسه مستخدم بس لحالة فلترة سبب
  /// الصرف (exit_type)، اللي محتاجة join مع transactions_log. نفس
  /// الكود اللي كان شغال قبل TASK-315 بالظبط، من غير أي تغيير في
  /// المنطق (بس من غير الـ sort الأخير، اللي بقى مركزي في الدالة الأم).
  Future<List<Map<String, dynamic>>> _getGroupedInventoryLegacy({
    String? presence,
    String? ownershipStatus,
    String? entryType,
    String? exitType,
  }) async {
    var q = _client.from('inventory_items').select().neq('status', 'Archived');
    if (presence == 'available') {
      q = q.neq('status', 'Out');
      if (ownershipStatus != null) q = q.eq('ownership_status', ownershipStatus);
    } else if (presence == 'dispatched') {
      q = q.eq('status', 'Out');
    }
    if (entryType != null) q = q.eq('entry_type', entryType);

    final itemRows = await q;
    var items = (itemRows as List).cast<Map<String, dynamic>>();

    // سبب الصرف مخزّن في transactions_log مش في inventory_items، فلو
    // مطلوب فلترة بيه لازم نجيب آخر حركة "صرف" لكل قطعة صادرة الأول.
    if (presence == 'dispatched' && exitType != null && items.isNotEmpty) {
      final itemIds = items.map((r) => r['item_id'] as int).toList();
      final logRows = await _client
          .from('transactions_log')
          .select('item_id, exit_type')
          .eq('action_type', 'OUT')
          .inFilter('item_id', itemIds)
          .order('timestamp', ascending: false);
      final exitTypeByItem = <int, String?>{};
      for (final r in logRows as List) {
        final id = r['item_id'] as int;
        // مرتبين تنازلي بالوقت، فأول ظهور لكل item_id هو آخر حركة صرف ليها
        exitTypeByItem.putIfAbsent(id, () => r['exit_type'] as String?);
      }
      items = items
          .where((item) => exitTypeByItem[item['item_id'] as int] == exitType)
          .toList();
    }

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
      final itemId = item['item_id'] as int?;
      final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '');
      final updatedAt = DateTime.tryParse(item['updated_at']?.toString() ?? '');

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
                'min_item_id': itemId,
                'min_created_at': createdAt,
                'max_updated_at': updatedAt,
              });
      g['total_count'] = (g['total_count'] as int) + 1;
      if (item['status'] == 'Available') {
        g['available_count'] = (g['available_count'] as int) + 1;
      }
      if (itemId != null &&
          (g['min_item_id'] == null || itemId < (g['min_item_id'] as int))) {
        g['min_item_id'] = itemId;
      }
      if (createdAt != null) {
        final current = g['min_created_at'] as DateTime?;
        if (current == null || createdAt.isBefore(current)) {
          g['min_created_at'] = createdAt;
        }
      }
      if (updatedAt != null) {
        final current = g['max_updated_at'] as DateTime?;
        if (current == null || updatedAt.isAfter(current)) {
          g['max_updated_at'] = updatedAt;
        }
      }
    }

    return groups.values.toList();
  }

  /// نفس فلاتر getGroupedInventory بالظبط، لكن من غير تجميع — كل قطعة
  /// فعلية بصف/بطاقة مستقلة ليها (الجولة الثالثة، إضافة على نقطة ١٩:
  /// خيار عرض "فردية" بدل "مجمّعة"). نفس أسماء sortField المدعومة في
  /// getGroupedInventory بالظبط (ماعدا 'total_count' اللي معناهاش حاجة
  /// هنا، بيتعامل زي 'item_id').
  Future<List<InventoryItem>> getFilteredIndividual({
    String? presence,
    String? ownershipStatus,
    String? entryType,
    String? exitType,
    String sortField = 'item_id',
    bool ascending = false,
  }) async {
    var q = _client.from('inventory_items').select().neq('status', 'Archived');
    if (presence == 'available') {
      q = q.neq('status', 'Out');
      if (ownershipStatus != null) q = q.eq('ownership_status', ownershipStatus);
    } else if (presence == 'dispatched') {
      q = q.eq('status', 'Out');
    }
    if (entryType != null) q = q.eq('entry_type', entryType);

    final itemRows = await q;
    var items = (itemRows as List).cast<Map<String, dynamic>>();

    if (presence == 'dispatched' && exitType != null && items.isNotEmpty) {
      final itemIds = items.map((r) => r['item_id'] as int).toList();
      final logRows = await _client
          .from('transactions_log')
          .select('item_id, exit_type')
          .eq('action_type', 'OUT')
          .inFilter('item_id', itemIds)
          .order('timestamp', ascending: false);
      final exitTypeByItem = <int, String?>{};
      for (final r in logRows as List) {
        final id = r['item_id'] as int;
        exitTypeByItem.putIfAbsent(id, () => r['exit_type'] as String?);
      }
      items = items
          .where((item) => exitTypeByItem[item['item_id'] as int] == exitType)
          .toList();
    }

    final result = items.map((r) => InventoryItem.fromMap(r)).toList();
    result.sort((a, b) {
      int c;
      switch (sortField) {
        case 'part_number':
          c = a.partNumber.compareTo(b.partNumber);
          break;
        case 'item_type':
          c = a.itemType.compareTo(b.itemType);
          break;
        case 'created_at':
          c = (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
          break;
        case 'updated_at':
          c = (a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
          break;
        default: // item_id
          c = (a.itemId ?? 0).compareTo(b.itemId ?? 0);
      }
      return ascending ? c : -c;
    });
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
          .neq('status', 'Archived')
          .order('created_at', ascending: false);
      return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
    }
    final rows = await _client
        .from('inventory_items')
        .select()
        .eq('description', desc)
        .neq('status', 'Archived')
        .order('created_at', ascending: false);
    return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
  }

  /// اسم قديم كان بيعتمد على View (`inventory_items_grouped`) مش
  /// مضمون وجودها/تحديثها فعلياً — استُبدل بـ getGroupedInventory
  /// اللي بيحسب التجميع مباشرة من الجدول، وبيغطي حالة القطع من غير
  /// رقم قطعة كمان (كانت الـ View القديمة بتغطي رقم القطعة بس).
  @Deprecated('استخدم getGroupedInventory بدل ده')
  Future<List<InventoryGroup>> getGroupedByPartNumber() =>
      getGroupedInventory();

  Future<List<InventoryItem>> bulkInsert(List<InventoryItem> items) async {
    final rows = await _client
        .from('inventory_items')
        .insert(items.map((e) => e.toInsertMap()).toList())
        .select();
    return (rows as List).map((r) => InventoryItem.fromMap(r)).toList();
  }

  /// TASK-304 + TASK-305: تسجيل قطعة جديدة كوحدة واحدة ذرية (إدراج
  /// القطعة + تحديث قاعدة المعرفة + الـ audit log + الإشعار) عبر RPC
  /// واحدة في Postgres (راجع migrations/008_atomic_inventory_insert.sql)
  /// بدل 4-5 نداءات منفصلة من هنا — لو أي جزء فشل، كل حاجة بترجع
  /// (rollback) تلقائياً، فمفيش احتمال قطعة تتسجل من غير سجل حركة أو
  /// إشعار ناقص. استُخدمت بدل bulkInsert في شاشة تسجيل قطعة (العامل).
  ///
  /// TASK-401: الـ RPC نفسها بقت ممنوعة تتنادى مباشرة من anon (راجع
  /// 012_secure_atomic_insert_rpc.sql) — النداء بقى عبر Edge Function
  /// `create-inventory-item` اللي بتتحقق من التوكن الأول، عشان
  /// طبقة الـ Authorization اللي بنيناها للعمليات الحساسة تتطبق هنا
  /// كمان، مش بس على admin functions.
  Future<InventoryItem> createItemAtomic({
    required InventoryItem item,
    required String username,
    required String? token,
    String? geminiInsights,
    String? partModel,
    required String logDetails,
    String? notifMessage,
  }) async {
    final response = await _client.functions.invoke('create-inventory-item',
        body: {
          'itemType': item.itemType,
          'partNumber': item.partNumber,
          'description': item.description,
          'notes': item.notes,
          'entryType': item.entryType,
          'location': item.location,
          'condition': item.condition,
          'serialNumber': item.serialNumber,
          'ownershipStatus': item.ownershipStatus,
          'geminiInsights': geminiInsights,
          'partModel': partModel,
          'logDetails': logDetails,
          'notifMessage': notifMessage,
        },
        headers: token != null ? {'x-app-token': token} : null);

    final data = response.data as Map<String, dynamic>?;
    if (data?['success'] != true) {
      final msg = data?['error']?.toString() ?? 'فشل حفظ القطعة';
      if (data?['businessError'] == true) throw BusinessException(msg);
      throw Exception(msg);
    }
    return InventoryItem.fromMap(data!['item'] as Map<String, dynamic>);
  }

  Future<void> updateStatus(int itemId, String status) async {
    await _client
        .from('inventory_items')
        .update({'status': status, 'updated_at': DateTime.now().toIso8601String()})
        .eq('item_id', itemId);
  }

  /// راجع migrations/013_dispatch_return_atomic.sql — نفس فلسفة
  /// createItemAtomic: صرف القطعة (سجل الحركة + تغيير الحالة + الإشعار)
  /// بقى transaction ذرية واحدة، عبر Edge Function `dispatch-item` اللي
  /// بتتحقق من التوكن الأول (نفس نمط TASK-401). details/exitType
  /// بتتبني في الشاشة المستدعية زي ما كانت بالظبط — مفيش تغيير في شكل
  /// الرسالة المسجّلة.
  Future<InventoryItem> dispatchItem({
    required int itemId,
    required String? token,
    required String details,
    required String exitType,
    String? notifMessage,
  }) async {
    final response = await _client.functions.invoke('dispatch-item',
        body: {
          'itemId': itemId,
          'details': details,
          'exitType': exitType,
          'notifMessage': notifMessage,
        },
        headers: token != null ? {'x-app-token': token} : null);
    final data = response.data as Map<String, dynamic>?;
    if (data?['success'] != true) {
      final msg = data?['error']?.toString() ?? 'فشل تسجيل الصرف';
      if (data?['businessError'] == true) throw BusinessException(msg);
      throw Exception(msg);
    }
    return InventoryItem.fromMap(data!['item'] as Map<String, dynamic>);
  }

  /// نفس فلسفة dispatchItem بالظبط، لعملية الاسترجاع.
  Future<InventoryItem> returnItem({
    required int itemId,
    required String? token,
    required String details,
    String? notifMessage,
  }) async {
    final response = await _client.functions.invoke('return-item',
        body: {
          'itemId': itemId,
          'details': details,
          'notifMessage': notifMessage,
        },
        headers: token != null ? {'x-app-token': token} : null);
    final data = response.data as Map<String, dynamic>?;
    if (data?['success'] != true) {
      final msg = data?['error']?.toString() ?? 'فشل تسجيل الاسترجاع';
      if (data?['businessError'] == true) throw BusinessException(msg);
      throw Exception(msg);
    }
    return InventoryItem.fromMap(data!['item'] as Map<String, dynamic>);
  }

  Future<void> updateFields(int itemId, Map<String, dynamic> fields) async {
    fields['updated_at'] = DateTime.now().toIso8601String();
    await _client.from('inventory_items').update(fields).eq('item_id', itemId);
  }

  /// راجع migrations/014_update_fields_atomic.sql. بديل آمن ومُدقّق
  /// لـ updateFields للحقول الأساسية (موقع/حالة فنية/حالة ملكية،
  /// واختيارياً حالة القطعة/ملاحظات/سريال) — بيعدي على Edge Function
  /// `update-item-fields` اللي بتتحقق من التوكن **وكمان** من صلاحية
  /// can_edit فعلياً على السيرفر (مش بس شرط إظهار الزرار في الواجهة).
  /// كل شاشة بتبعت بس الحقول اللي بتديرها فعلاً (نفس الفروق الموجودة
  /// بالفعل بين الشاشتين، محفوظة زي ما هي).
  Future<InventoryItem> updateItemFieldsAtomic({
    required int itemId,
    required String? token,
    required String? location,
    required String condition,
    required String ownershipStatus,
    String? status,
    String? notes,
    String? serialNumber,
    required String logDetails,
  }) async {
    final response = await _client.functions.invoke('update-item-fields',
        body: {
          'itemId': itemId,
          'location': location,
          'condition': condition,
          'ownershipStatus': ownershipStatus,
          if (status != null) 'status': status,
          'updateStatus': status != null,
          if (notes != null) 'notes': notes,
          'updateNotes': notes != null,
          if (serialNumber != null) 'serialNumber': serialNumber,
          'updateSerial': serialNumber != null,
          'logDetails': logDetails,
        },
        headers: token != null ? {'x-app-token': token} : null);
    final data = response.data as Map<String, dynamic>?;
    if (data?['success'] != true) {
      final msg = data?['error']?.toString() ?? 'فشل حفظ التعديل';
      if (data?['businessError'] == true) throw BusinessException(msg);
      throw Exception(msg);
    }
    return InventoryItem.fromMap(data!['item'] as Map<String, dynamic>);
  }

  /// TASK-306: اتشال الـ hard delete من التطبيق نهائياً. بدل ما نمسح
  /// الصف فعلياً (وبالتالي نفقد التاريخ/الـ audit/traceability بتاعته
  /// للأبد)، بنعمل أرشفة قابلة للتراجع: status يبقى 'Archived' +
  /// deleted_at/deleted_by/delete_reason. القطعة تختفي من كل شاشات
  /// التصفح العادية (getAll/smartSearch/getFiltered/...، كلها بقت
  /// بتستبعد Archived) لكن بيانتها وتاريخها لسه موجودين في الداتابيز
  /// لو احتجنا نرجع لها أو نحقق في حاجة لاحقاً.
  ///
  /// الحذف النهائي الحقيقي (DELETE FROM) بقى عملية صيانة قاعدة بيانات
  /// بحتة تتم يدوياً على Supabase SQL Editor لو ولما احتجناها فعلاً —
  /// مش حاجة متاحة من التطبيق.
  ///
  /// آخر نقطة من مصفوفة SECURITY.md: بقت atomic (تحديث + سجل حركة مع
  /// بعض) ومتحقق منها فعلياً على السيرفر (can_edit/admin) عبر Edge
  /// Function `archive-item` — مش نداء مباشر على الجدول بمفتاح anon.
  Future<InventoryItem> archiveItem(
    int itemId, {
    required String? token,
    required String reason,
  }) async {
    final response = await _client.functions.invoke('archive-item',
        body: {'itemId': itemId, 'reason': reason},
        headers: token != null ? {'x-app-token': token} : null);
    final data = response.data as Map<String, dynamic>?;
    if (data?['success'] != true) {
      final msg = data?['error']?.toString() ?? 'فشلت الأرشفة';
      if (data?['businessError'] == true) throw BusinessException(msg);
      throw Exception(msg);
    }
    return InventoryItem.fromMap(data!['item'] as Map<String, dynamic>);
  }
}