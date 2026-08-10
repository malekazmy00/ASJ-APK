import 'package:flutter/material.dart';
import '../../../core/models/transaction_log.dart';
import '../../../core/repositories/inventory_repository.dart';
import '../../../core/repositories/log_repository.dart';
import '../../../core/widgets/autocomplete_search_field.dart';
import '../../../core/widgets/timeline_widget.dart';

/// تتبع القطعة: تبحث برقم القطعة (بحث Autocomplete — نقطة ١٥+١٨)،
/// تجيب كل حركاتها من entry لحد الآن — كتبويب عادي.
///
/// الجولة الثالثة (نقطة ٢): تدعم كمان فتح مباشر على قطعة بعينها من
/// صفحة تفاصيل القطعة (زرار "تتبع") — [initialPartNumber] بيعبّي
/// خانة البحث ويبحث تلقائي، و[initialItemId] بيستخدم لو رقم القطعة
/// "PENDING" (قطعة من غير رقم) عشان التتبع يبقى بالـ ID الداخلي
/// بدل البحث برقم قطعة غير موجود أصلاً.
class ItemTimelineScreen extends StatefulWidget {
  const ItemTimelineScreen({super.key, this.initialPartNumber, this.initialItemId});

  final String? initialPartNumber;
  final int? initialItemId;

  @override
  State<ItemTimelineScreen> createState() => _ItemTimelineScreenState();
}

class _ItemTimelineScreenState extends State<ItemTimelineScreen> {
  final _logRepo = LogRepository();
  final _inventoryRepo = InventoryRepository();
  final _controller = TextEditingController();
  List<TransactionLog> _logs = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    final hasPartNumber = widget.initialPartNumber != null &&
        widget.initialPartNumber!.isNotEmpty &&
        widget.initialPartNumber != 'PENDING';
    if (hasPartNumber) {
      _controller.text = widget.initialPartNumber!;
      _searchWithText(widget.initialPartNumber!);
    } else if (widget.initialItemId != null) {
      _searchByItemId(widget.initialItemId!);
    }
  }

  /// البحث الفعلي بيحصل بس لما يتم اختيار رقم من قايمة الاقتراحات (أو
  /// مسح باركود) — مش أثناء الكتابة نفسها (راجع AutocompleteSearchField).
  Future<void> _searchWithText(String partNumber) async {
    final trimmed = partNumber.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _loading = true;
      _searched = true;
    });
    final logs = await _logRepo.getByPartNumber(trimmed);
    if (mounted) {
      setState(() {
        _logs = logs;
        _loading = false;
      });
    }
  }

  /// تتبع بالـ ID الداخلي مباشرة — لقطعة من غير رقم قطعة رسمي
  /// (part_number = 'PENDING')، البحث برقم القطعة مش هيلاقي حاجة.
  Future<void> _searchByItemId(int itemId) async {
    setState(() {
      _loading = true;
      _searched = true;
    });
    final logs = await _logRepo.getByItem(itemId);
    if (mounted) {
      setState(() {
        _logs = logs;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AutocompleteSearchField(
            controller: _controller,
            hintText: 'رقم القطعة أو الاسم الكودي',
            fetchSuggestions: (q) => _inventoryRepo.getSuggestions(q),
            onSelected: _searchWithText,
            onBarcodeScanned: _searchWithText,
          ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          if (_searched && !_loading)
            Expanded(
              child: SingleChildScrollView(
                child: TimelineWidget(
                  logs: _logs,
                  emptyMessage: 'لا توجد حركات مسجّلة لهذا الرقم',
                ),
              ),
            ),
        ],
      ),
    );
  }
}