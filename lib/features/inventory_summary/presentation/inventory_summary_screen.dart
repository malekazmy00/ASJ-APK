import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/inventory_repository.dart';
import '../../../core/widgets/autocomplete_search_field.dart';
import 'inventory_group_items_screen.dart';
import 'inventory_item_detail_screen.dart';

/// تبويب المخزون — الجولة الثالثة:
/// نقطة ٢: بطاقات مجمّعة حسب رقم القطعة/الموديل، أو حسب الوصف لو مفيش
/// رقم قطعة (زي "مفتاح"، "أفوميتر")، مع عدد المتاح والإجمالي.
/// نقطة ١٥+١٦+١٧+١٨: بحث Autocomplete (اقتراحات بس، البحث الفعلي بعد
/// الاختيار) + زرار مسح باركود + إصلاح باج البحث بالـ ID (كان بيدوّر
/// في display_name بس، دلوقتي بيدوّر بالـ ID مباشرة لو النص رقم صافي).
/// نقطة ١٩: زرار "⚙️ عرض" بيفتح نافذة صغيرة فيها شجرة الفلاتر + الترتيب.
class InventorySummaryScreen extends StatefulWidget {
  const InventorySummaryScreen({super.key});

  @override
  State<InventorySummaryScreen> createState() => _InventorySummaryScreenState();
}

class _InventorySummaryScreenState extends State<InventorySummaryScreen> {
  final _repo = InventoryRepository();
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;

  // حالة الفلاتر/الترتيب الحالية (نقطة ١٩)
  String? _presence; // null = الكل | 'available' | 'dispatched'
  String? _ownershipStatus;
  String? _entryType;
  String? _exitType;
  String _sortField = 'total_count';
  bool _ascending = false;

  // آخر نص بحث مختار (من الاقتراحات أو الباركود) — بيتفلتر بيه فوق
  // نتيجة الفلاتر، مش بديل عنها.
  String? _searchText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await _repo.getGroupedInventory(
        presence: _presence,
        ownershipStatus: _presence == 'available' ? _ownershipStatus : null,
        entryType: _entryType,
        exitType: _presence == 'dispatched' ? _exitType : null,
        sortField: _sortField,
        ascending: _ascending,
      );
      if (mounted) {
        setState(() {
          _groups = groups;
          _applySearchText();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر تحميل المخزون: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySearchText() {
    final q = _searchText?.trim();
    if (q == null || q.isEmpty) {
      _filtered = _groups;
      return;
    }
    _filtered = _groups.where((g) {
      final name = (g['display_name'] as String?) ?? '';
      return name == q || name.contains(q);
    }).toList();
  }

  /// الجولة الثالثة (نقطة ١٧ — إصلاح الباج): لو النص المُختار رقم
  /// صافي، ندوّر بالـ ID مباشرة (getById) ونفتح تفاصيل القطعة على
  /// طول، بدل ما نفلتر بطاقات المجموعات (اللي أصلاً معروضة برقم
  /// القطعة/الوصف مش بالـ ID الفردي).
  Future<void> _handleSelection(String text) async {
    final asId = int.tryParse(text.trim());
    if (asId != null) {
      final item = await _repo.getById(asId);
      if (item != null) {
        if (mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => InventoryItemDetailScreen(item: item)),
          );
          _load();
        }
        return;
      }
    }
    setState(() {
      _searchText = text;
      _applySearchText();
    });
  }

  Future<void> _openFilterSheet() async {
    String? presence = _presence;
    String? ownership = _ownershipStatus;
    String? entryType = _entryType;
    String? exitType = _exitType;
    String sortField = _sortField;
    bool ascending = _ascending;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('اختار طريقة العرض',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),

                Text('حالة القطعة', textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    ChoiceChip(
                      label: const Text('الكل'),
                      selected: presence == null,
                      onSelected: (_) => setSheetState(() {
                        presence = null;
                        ownership = null;
                        exitType = null;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('موجودة'),
                      selected: presence == 'available',
                      onSelected: (_) => setSheetState(() {
                        presence = 'available';
                        exitType = null;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('منصرفة'),
                      selected: presence == 'dispatched',
                      onSelected: (_) => setSheetState(() {
                        presence = 'dispatched';
                        ownership = null;
                      }),
                    ),
                  ],
                ),

                if (presence == 'available') ...[
                  const SizedBox(height: 14),
                  Text('حالة الملكية', textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      ChoiceChip(
                        label: const Text('الكل'),
                        selected: ownership == null,
                        onSelected: (_) => setSheetState(() => ownership = null),
                      ),
                      ...OwnershipStatus.values.map((o) => ChoiceChip(
                            label: Text(o.arabicLabel),
                            selected: ownership == o.dbValue,
                            onSelected: (_) => setSheetState(() => ownership = o.dbValue),
                          )),
                    ],
                  ),
                ],

                if (presence == 'dispatched') ...[
                  const SizedBox(height: 14),
                  Text('سبب الصرف', textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      ChoiceChip(
                        label: const Text('الكل'),
                        selected: exitType == null,
                        onSelected: (_) => setSheetState(() => exitType = null),
                      ),
                      ...ExitType.values.map((e) => ChoiceChip(
                            label: Text(e.arabicLabel),
                            selected: exitType == e.dbValue,
                            onSelected: (_) => setSheetState(() => exitType = e.dbValue),
                          )),
                    ],
                  ),
                ],

                const SizedBox(height: 14),
                Text('نوع الإدخال', textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    ChoiceChip(
                      label: const Text('الكل'),
                      selected: entryType == null,
                      onSelected: (_) => setSheetState(() => entryType = null),
                    ),
                    ...EntryType.values.map((e) => ChoiceChip(
                          label: Text(e.arabicLabel),
                          selected: entryType == e.dbValue,
                          onSelected: (_) => setSheetState(() => entryType = e.dbValue),
                        )),
                  ],
                ),

                const Divider(height: 28),
                Text('الترتيب', textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: sortField,
                        decoration: const InputDecoration(labelText: 'حسب'),
                        items: const [
                          DropdownMenuItem(value: 'total_count', child: Text('الكمية')),
                          DropdownMenuItem(value: 'part_number', child: Text('رقم القطعة')),
                          DropdownMenuItem(value: 'item_id', child: Text('الـ ID الداخلي')),
                          DropdownMenuItem(value: 'item_type', child: Text('النوع')),
                        ],
                        onChanged: (v) => setSheetState(() => sortField = v ?? sortField),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<bool>(
                        initialValue: ascending,
                        decoration: const InputDecoration(labelText: 'الاتجاه'),
                        items: const [
                          DropdownMenuItem(value: false, child: Text('تنازلي')),
                          DropdownMenuItem(value: true, child: Text('تصاعدي')),
                        ],
                        onChanged: (v) => setSheetState(() => ascending = v ?? ascending),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('تطبيق'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (applied == true) {
      setState(() {
        _presence = presence;
        _ownershipStatus = ownership;
        _entryType = entryType;
        _exitType = exitType;
        _sortField = sortField;
        _ascending = ascending;
      });
      _load();
    }
  }

  bool get _hasActiveFilters =>
      _presence != null || _ownershipStatus != null || _entryType != null || _exitType != null;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AutocompleteSearchField(
                    hintText: 'بحث برقم القطعة، الاسم، أو الـ ID',
                    fetchSuggestions: (q) => _repo.getSuggestions(q),
                    onSelected: _handleSelection,
                    onBarcodeScanned: _handleSelection,
                  ),
                ),
                const SizedBox(width: 8),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton.outlined(
                      onPressed: _openFilterSheet,
                      icon: const Icon(Icons.tune),
                      tooltip: 'اختار طريقة العرض',
                    ),
                    if (_hasActiveFilters)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (_searchText != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ActionChip(
                    label: const Text('مسح البحث'),
                    avatar: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() {
                      _searchText = null;
                      _applySearchText();
                    }),
                  ),
                ],
              ),
            ),
          if (_filtered.isEmpty)
            const Expanded(
              child: Center(child: Text('لا يوجد مخزون مطابق')),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final g = _filtered[index];
                  final total = g['total_count'] as int? ?? 0;
                  final available = g['available_count'] as int? ?? 0;
                  final brand = g['brand'] as String?;
                  return Card(
                    child: ListTile(
                      title: Text(
                        g['display_name'] as String? ?? 'غير محدد',
                        textAlign: TextAlign.right,
                      ),
                      subtitle: Text(
                        [
                          if (brand != null && brand.isNotEmpty) brand,
                          g['item_type'] as String? ?? '',
                          'متاح: $available من إجمالي $total',
                        ].where((s) => s.isNotEmpty).join(' • '),
                        textAlign: TextAlign.right,
                      ),
                      trailing: CircleAvatar(
                        backgroundColor: available > 0
                            ? AppColors.success
                            : AppColors.textMuted,
                        child: Text(
                          '$total',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => InventoryGroupItemsScreen(
                              groupKey: g['group_key'] as String,
                              displayName: g['display_name'] as String? ?? '',
                            ),
                          ),
                        );
                        _load();
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}