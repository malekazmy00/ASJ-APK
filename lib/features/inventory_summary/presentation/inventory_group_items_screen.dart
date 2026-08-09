import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/inventory_item.dart';
import '../../../core/repositories/inventory_repository.dart';
import 'inventory_item_detail_screen.dart';

/// شاشة القطع الفعلية جوه مجموعة واحدة (الجولة الثالثة، نقطة ٢) —
/// بتفتح بعد الدوس على بطاقة مجموعة في InventorySummaryScreen، وبتعرض
/// كل قطعة فعلية بالـ ID/رقم القطعة/المكان، ودوس عليها يفتح صفحة
/// التفاصيل الكاملة.
class InventoryGroupItemsScreen extends StatefulWidget {
  const InventoryGroupItemsScreen({
    super.key,
    required this.groupKey,
    required this.displayName,
  });

  final String groupKey;
  final String displayName;

  @override
  State<InventoryGroupItemsScreen> createState() =>
      _InventoryGroupItemsScreenState();
}

class _InventoryGroupItemsScreenState extends State<InventoryGroupItemsScreen> {
  final _repo = InventoryRepository();
  List<InventoryItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _repo.getByGroupKey(widget.groupKey);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.displayName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('لا توجد قطع فعلية في هذه المجموعة'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final available = item.status == 'Available';
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                available ? AppColors.success : AppColors.textMuted,
                            child: Text(
                              '#${item.itemId}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                          title: Text(
                            item.partNumber == 'PENDING'
                                ? (item.description ?? 'بدون رقم قطعة')
                                : item.partNumber,
                            textAlign: TextAlign.right,
                          ),
                          subtitle: Text(
                            [
                              item.location ?? 'بدون مكان محدد',
                              item.status,
                            ].join(' • '),
                            textAlign: TextAlign.right,
                          ),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => InventoryItemDetailScreen(item: item),
                              ),
                            );
                            _load();
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}