import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/inventory_group.dart';
import '../../../core/models/inventory_item.dart';
import '../../../core/repositories/inventory_repository.dart';
import '../../../core/repositories/field_permissions_repository.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/error_messages.dart';
import '../../../core/widgets/autocomplete_search_field.dart';
import '../../auth/presentation/auth_providers.dart';
import 'inventory_group_items_screen.dart';
import 'inventory_item_detail_screen.dart';

/// تبويب المخزون — الجولة الثالثة:
/// نقطة ٢: بطاقات مجمّعة حسب رقم القطعة/الموديل، أو حسب الوصف لو مفيش
/// رقم قطعة (زي "مفتاح"، "أفوميتر")، مع عدد المتاح والإجمالي.
/// نقطة ١٥+١٦+١٧+١٨: بحث Autocomplete (اقتراحات بس، البحث الفعلي بعد
/// الاختيار) + زرار مسح باركود + إصلاح باج البحث بالـ ID.
/// نقطة ١٩: زرار "⚙️ عرض" بيفتح نافذة صغيرة فيها شجرة الفلاتر +
/// الترتيب (بما فيه الترتيب بالتاريخ) + خيار "مجمّعة/فردية" لطريقة العرض.
/// نقطة ٢٧: بعض العناصر (البحث بالباركود، زرار الفلاتر، خيار "فردية"،
/// حقل الموقع في العرض الفردي) قابلة للإخفاء لحساب معين من الأدمن.
class InventorySummaryScreen extends ConsumerStatefulWidget {
  const InventorySummaryScreen({super.key});

  @override
  ConsumerState<InventorySummaryScreen> createState() => _InventorySummaryScreenState();
}

class _InventorySummaryScreenState extends ConsumerState<InventorySummaryScreen> {
  final _repo = InventoryRepository();
  final _fieldRepo = FieldPermissionsRepository();
  Map<String, bool> _fieldOverrides = {};

  // بيانات المخزون بشكلَيها (مجمّعة/فردية) — واحد بس بيتحمّل حسب _viewMode
  List<InventoryGroup> _groups = [];
  List<InventoryGroup> _filteredGroups = [];
  List<InventoryItem> _individualItems = [];
  List<InventoryItem> _filteredIndividualItems = [];

  bool _loading = true;
  String? _error;

  /// 'grouped' (افتراضي) أو 'individual'
  String _viewMode = 'grouped';

  // حالة الفلاتر/الترتيب الحالية (نقطة ١٩)
  String? _presence; // null = الكل | 'available' | 'dispatched'
  String? _ownershipStatus;
  String? _entryType;
  String? _exitType;
  String _sortField = 'total_count';
  bool _ascending = false;

  String? _searchText;

  static const Map<String, String> _sortLabelsGrouped = {
    'total_count': 'الكمية',
    'part_number': 'رقم القطعة',
    'item_id': 'الـ ID الداخلي',
    'item_type': 'النوع',
    'created_at': 'تاريخ الإضافة',
    'updated_at': 'تاريخ آخر حركة',
  };
  static const Map<String, String> _sortLabelsIndividual = {
    'item_id': 'الـ ID الداخلي',
    'part_number': 'رقم القطعة',
    'item_type': 'النوع',
    'created_at': 'تاريخ الإضافة',
    'updated_at': 'تاريخ آخر حركة',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _loadFieldOverrides();
  }

  /// الجولة الثالثة (نقطة ٢٧): إيه عناصر تبويب المخزون اللي الأدمن
  /// سمح بظهورها لهذا الحساب.
  Future<void> _loadFieldOverrides() async {
    final username = ref.read(authControllerProvider)?.username;
    if (username == null) return;
    final overrides = await _fieldRepo.getOverrides(username, 'inventory_summary');
    if (mounted) setState(() => _fieldOverrides = overrides);
  }

  bool _fieldVisible(String key) => FieldPermissionsRepository.isVisible(_fieldOverrides, key);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_viewMode == 'grouped') {
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
      } else {
        final items = await _repo.getFilteredIndividual(
          presence: _presence,
          ownershipStatus: _presence == 'available' ? _ownershipStatus : null,
          entryType: _entryType,
          exitType: _presence == 'dispatched' ? _exitType : null,
          sortField: _sortField == 'total_count' ? 'item_id' : _sortField,
          ascending: _ascending,
        );
        if (mounted) {
          setState(() {
            _individualItems = items;
            _applySearchText();
          });
        }
      }
    } catch (e, st) {
      AppLogger.logError('InventorySummaryScreen._load', e, st);
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySearchText() {
    final q = _searchText?.trim();
    if (_viewMode == 'grouped') {
      if (q == null || q.isEmpty) {
        _filteredGroups = _groups;
      } else {
        _filteredGroups = _groups.where((g) {
          final name = g.displayName;
          return name == q || name.contains(q);
        }).toList();
      }
    } else {
      if (q == null || q.isEmpty) {
        _filteredIndividualItems = _individualItems;
      } else {
        _filteredIndividualItems = _individualItems.where((item) {
          return item.partNumber.contains(q) ||
              (item.description?.contains(q) ?? false) ||
              item.itemId.toString() == q;
        }).toList();
      }
    }
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
    String viewMode = _viewMode;
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

                if (_fieldVisible('individual_view')) ...[
                  Text('طريقة العرض', textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      ChoiceChip(
                        label: const Text('مجمّعة'),
                        selected: viewMode == 'grouped',
                        onSelected: (_) => setSheetState(() {
                          viewMode = 'grouped';
                          if (sortField != 'total_count' &&
                              !_sortLabelsGrouped.containsKey(sortField)) {
                            sortField = 'total_count';
                          }
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('فردية'),
                        selected: viewMode == 'individual',
                        onSelected: (_) => setSheetState(() {
                          viewMode = 'individual';
                          if (sortField == 'total_count') sortField = 'item_id';
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
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
                        items: (viewMode == 'grouped'
                                ? _sortLabelsGrouped
                                : _sortLabelsIndividual)
                            .entries
                            .map((e) =>
                                DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
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
        _viewMode = viewMode;
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
                    showBarcodeButton: _fieldVisible('barcode_search'),
                    onBarcodeScanned: _handleSelection,
                  ),
                ),
                if (_fieldVisible('filter_sort_button')) ...[
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
          Expanded(
            child: _viewMode == 'grouped' ? _buildGroupedList() : _buildIndividualList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList() {
    if (_filteredGroups.isEmpty) {
      return const Center(child: Text('لا يوجد مخزون مطابق'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _filteredGroups.length,
      itemBuilder: (context, index) {
        final g = _filteredGroups[index];
        final total = g.totalCount;
        final available = g.availableCount;
        final brand = g.brand;
        return Card(
          child: ListTile(
            title: Text(
              g.displayName,
              textAlign: TextAlign.right,
            ),
            subtitle: Text(
              [
                if (brand != null && brand.isNotEmpty) brand,
                g.itemType ?? '',
                'متاح: $available من إجمالي $total',
              ].where((s) => s.isNotEmpty).join(' • '),
              textAlign: TextAlign.right,
            ),
            trailing: CircleAvatar(
              backgroundColor: available > 0 ? AppColors.success : AppColors.textMuted,
              child: Text(
                '$total',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => InventoryGroupItemsScreen(
                    groupKey: g.groupKey,
                    displayName: g.displayName,
                  ),
                ),
              );
              _load();
            },
          ),
        );
      },
    );
  }

  Widget _buildIndividualList() {
    if (_filteredIndividualItems.isEmpty) {
      return const Center(child: Text('لا يوجد مخزون مطابق'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _filteredIndividualItems.length,
      itemBuilder: (context, index) {
        final item = _filteredIndividualItems[index];
        final available = item.status == 'Available';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: available ? AppColors.success : AppColors.textMuted,
              child: Text('#${item.itemId}',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
            title: Text(
              item.partNumber == 'PENDING'
                  ? (item.description ?? 'بدون رقم قطعة')
                  : item.partNumber,
              textAlign: TextAlign.right,
            ),
            subtitle: Text(
              [
                item.itemType,
                if (_fieldVisible('location_field')) item.location ?? 'بدون مكان',
                item.status,
              ].where((s) => s.isNotEmpty).join(' • '),
              textAlign: TextAlign.right,
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => InventoryItemDetailScreen(item: item)),
              );
              _load();
            },
          ),
        );
      },
    );
  }
}