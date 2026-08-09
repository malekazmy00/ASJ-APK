import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/repositories/inventory_repository.dart';
import 'inventory_group_items_screen.dart';

/// تبويب المخزون — الجولة الثالثة (نقطة ٢): بطاقات مجمّعة حسب رقم
/// القطعة/الموديل، أو حسب الوصف لو مفيش رقم قطعة (زي "مفتاح"،
/// "أفوميتر")، مع عدد المتاح والإجمالي. الدوس على بطاقة يفتح شاشة
/// فيها القطع الفعلية جوه المجموعة دي واحدة واحدة.
class InventorySummaryScreen extends StatefulWidget {
  const InventorySummaryScreen({super.key});

  @override
  State<InventorySummaryScreen> createState() => _InventorySummaryScreenState();
}

class _InventorySummaryScreenState extends State<InventorySummaryScreen> {
  final _repo = InventoryRepository();
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchController = TextEditingController();
  bool _loading = true;
  String? _error;

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
      final groups = await _repo.getGroupedInventory();
      if (mounted) {
        setState(() {
          _groups = groups;
          _applyFilter();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر تحميل المخزون: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      _filtered = _groups;
      return;
    }
    _filtered = _groups.where((g) {
      final name = (g['display_name'] as String?) ?? '';
      final key = (g['group_key'] as String?) ?? '';
      return name.contains(q) || key.contains(q);
    }).toList();
  }

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
            child: TextField(
              controller: _searchController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'بحث برقم القطعة أو الاسم',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(_applyFilter),
            ),
          ),
          if (_filtered.isEmpty)
            const Expanded(
              child: Center(child: Text('لا يوجد مخزون مطابق')),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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