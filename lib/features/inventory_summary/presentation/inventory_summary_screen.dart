import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/repositories/inventory_repository.dart';

/// الداشبورد التجميعي المطلوب: تجميع حسب part_number/item_type مع العدد،
/// بدل صف منفصل لكل قطعة فردية. مصدر البيانات: View `inventory_items_grouped`
/// (راجع migrations/001).
class InventorySummaryScreen extends StatefulWidget {
  const InventorySummaryScreen({super.key});

  @override
  State<InventorySummaryScreen> createState() => _InventorySummaryScreenState();
}

class _InventorySummaryScreenState extends State<InventorySummaryScreen> {
  final _repo = InventoryRepository();
  List<Map<String, dynamic>> _rows = [];
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
      final rows = await _repo.getGroupedByPartNumber();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'تعذر تحميل الداشبورد التجميعي — تأكد إن الـ View `inventory_items_grouped` اتعملت في Supabase (راجع migrations/001).');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    if (_rows.isEmpty) {
      return const Center(child: Text('لا يوجد مخزون مسجّل حالياً'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _rows.length,
        itemBuilder: (context, index) {
          final row = _rows[index];
          final qty = row['qty'] ?? 0;
          final qtyAvailable = row['qty_available'] ?? 0;
          return Card(
            child: ListTile(
              title: Text(
                '${row['part_number']} — ${row['item_type']}',
                textAlign: TextAlign.right,
              ),
              subtitle: Text(
                'متاح: $qtyAvailable من إجمالي $qty قطعة',
                textAlign: TextAlign.right,
              ),
              trailing: CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Text(
                  '$qty',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
