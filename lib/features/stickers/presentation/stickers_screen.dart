import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/inventory_item.dart';
import '../../../core/repositories/inventory_repository.dart';

/// معاينة استيكر القطعة (رقم القطعة + Serial لو موجود + كود QR).
/// الطباعة الفعلية عبر طابعة متصلة، والمسح بالسكانر الفيزيائي، لسه
/// مؤجلين (محتاجين صلاحية نظام Bluetooth/كاميرا تُطلب وقت الاستخدام،
/// مش جزء من هذه الدفعة).
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
  bool _loading = false;

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _selected = null;
    });
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: 'ابحث برقم القطعة...',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _loading ? null : _search,
              child: const Text('بحث'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (!_loading && _results.isNotEmpty && _selected == null)
          ..._results.map((item) => Card(
                child: ListTile(
                  title: Text('${item.partNumber} — ${item.itemType}', textAlign: TextAlign.right),
                  subtitle: Text('#${item.itemId}', textAlign: TextAlign.right),
                  onTap: () => setState(() => _selected = item),
                ),
              )),
        if (_selected != null) _StickerPreview(item: _selected!),
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