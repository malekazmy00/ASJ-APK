import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/inventory_item.dart';
import '../../../core/repositories/inventory_repository.dart';
import '../../../core/widgets/barcode_scanner_page.dart';

/// معاينة استيكر القطعة (رقم القطعة + Serial لو موجود + كود QR).
/// القائمة بتظهر مباشرة من غير ما تحتاج تبحث الأول (تصفح حر)، ولو
/// كتبت رقم الـ ID بتاع القطعة بالظبط بتقفز لاستيكرها على طول.
/// الطباعة الفعلية عبر طابعة متصلة لسه مؤجلة.
class StickersScreen extends StatefulWidget {
  const StickersScreen({super.key});

  @override
  State<StickersScreen> createState() => _StickersScreenState();
}

class _StickersScreenState extends State<StickersScreen> {
  final _repo = InventoryRepository();
  final _controller = TextEditingController();
  List<InventoryItem> _results = [];
  InventoryItem? _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final items = await _repo.getAll();
    if (mounted) {
      setState(() {
        _results = items;
        _loading = false;
      });
    }
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(() => _selected = null);
      await _loadAll();
      return;
    }

    setState(() {
      _loading = true;
      _selected = null;
    });

    // لو الإدخال رقم صافي، دور بالـ ID مباشرة وقفز لاستيكرها على طول
    final asId = int.tryParse(q);
    if (asId != null) {
      final item = await _repo.getById(asId);
      if (item != null) {
        if (mounted) {
          setState(() {
            _selected = item;
            _loading = false;
          });
        }
        return;
      }
    }

    final items = await _repo.smartSearch(q);
    if (mounted) {
      setState(() {
        _results = items;
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'دوّر برقم القطعة أو الـ ID (اختياري)...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'مسح باركود',
                      onPressed: () async {
                        final code = await scanBarcode(context);
                        if (code != null && code.isNotEmpty) {
                          _controller.text = code;
                          _search();
                        }
                      },
                    ),
                  ),
                  onSubmitted: (_) => _search(),
                  onChanged: (_) => _search(),
                ),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_selected != null)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('رجوع للقائمة'),
                ),
                _StickerPreview(item: _selected!),
              ],
            ),
          )
        else if (!_loading && _results.isEmpty)
          const Expanded(
            child: Center(
              child: Text('لا توجد قطع مسجّلة بعد.', style: TextStyle(color: AppColors.textMuted)),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final item = _results[index];
                return Card(
                  child: ListTile(
                    title: Text('${item.partNumber} — ${item.itemType}', textAlign: TextAlign.right),
                    subtitle: Text('#${item.itemId}', textAlign: TextAlign.right),
                    onTap: () => setState(() => _selected = item),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _StickerPreview extends StatelessWidget {
  const _StickerPreview({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final qrData = 'ASJ|${item.itemId}|${item.partNumber}';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary, width: 1.4),
      ),
      child: Column(
        children: [
          Text(item.partNumber,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
          const SizedBox(height: 4),
          Text('رقم القطعة الداخلي: #${item.itemId}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          if (item.serialNumber != null && item.serialNumber!.isNotEmpty)
            Text('Serial: ${item.serialNumber}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 14),
          QrImageView(data: qrData, size: 140, backgroundColor: Colors.white),
          const SizedBox(height: 14),
          const Text(
            'ميزة الطباعة المباشرة عبر طابعة متصلة قريباً — دلوقتي ممكن تاخد سكرين شوت وتطبعها.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}