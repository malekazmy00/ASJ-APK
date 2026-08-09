import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/inventory_item.dart';
import '../../../core/repositories/inventory_repository.dart';
import '../../../core/widgets/barcode_scanner_page.dart';

/// معاينة استيكر القطعة (رقم القطعة + Serial لو موجود + كود QR).
/// القائمة بتظهر مباشرة من غير ما تحتاج تبحث الأول (تصفح حر)، ولو
/// كتبت رقم الـ ID بتاع القطعة بالظبط بتقفز لاستيكرها على طول.
///
/// الجولة الثالثة (نقطة ١٤ — الطباعة): بدل ما نربط بطابعة معينة
/// (محتاج نعرف الموديل بالظبط)، بنستخدم نافذة الطباعة القياسية في
/// أندرويد نفسها (نفس اللي أي تطبيق بيستخدمها) — بتتعرف تلقائياً على
/// أي طابعة متصلة بالموبايل (بلوتوث/شبكة) طالما مثبّت لها تطبيق
/// تعريف (print service)، ومن جواها كمان تقدر "احفظ كـ PDF" لو مفيش
/// طابعة متصلة دلوقتي.
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

class _StickerPreview extends StatefulWidget {
  const _StickerPreview({required this.item});
  final InventoryItem item;

  @override
  State<_StickerPreview> createState() => _StickerPreviewState();
}

class _StickerPreviewState extends State<_StickerPreview> {
  bool _printing = false;

  String get _qrData => 'ASJ|${widget.item.itemId}|${widget.item.partNumber}';

  /// بيبني استيكر بحجم صغير (٦×٤ سم — حجم شائع لاستيكرات القطع)
  /// ويفتح نافذة الطباعة القياسية بتاعة أندرويد. لو الطابعة الفعلية
  /// محتاجة مقاس مختلف، نافذة الطباعة نفسها بتدّي خيار تكبير/تصغير
  /// أو اختيار حجم ورق مختلف حسب الطابعة المتصلة.
  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final item = widget.item;
      final doc = pw.Document();
      final labelFormat = PdfPageFormat(
        6 * PdfPageFormat.cm,
        4 * PdfPageFormat.cm,
        marginAll: 4,
      );

      doc.addPage(
        pw.Page(
          pageFormat: labelFormat,
          build: (context) => pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  item.partNumber == 'PENDING' ? item.itemType : item.partNumber,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 3),
                pw.Text('#${item.itemId}', style: const pw.TextStyle(fontSize: 9)),
                if (item.serialNumber != null && item.serialNumber!.isNotEmpty)
                  pw.Text('S/N: ${item.serialNumber}', style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 4),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: _qrData,
                  width: 90,
                  height: 90,
                ),
              ],
            ),
          ),
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: 'استيكر_${item.itemId}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذرت الطباعة: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
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
          Text(item.partNumber == 'PENDING' ? item.itemType : item.partNumber,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
          const SizedBox(height: 4),
          Text('رقم القطعة الداخلي: #${item.itemId}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          if (item.serialNumber != null && item.serialNumber!.isNotEmpty)
            Text('Serial: ${item.serialNumber}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 14),
          QrImageView(data: _qrData, size: 140, backgroundColor: Colors.white),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _printing ? null : _print,
            icon: _printing
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.print_outlined),
            label: Text(_printing ? 'جارٍ التحضير...' : 'طباعة الاستيكر'),
          ),
          const SizedBox(height: 6),
          const Text(
            'هتفتح نافذة الطباعة القياسية بتاعة الموبايل — اختار الطابعة المتصلة، أو احفظ الاستيكر كـ PDF.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}