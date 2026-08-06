import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/repositories/knowledge_base_repository.dart';

/// استيراد قاعدة المعرفة الفنية (specs_knowledge_base) من ملف CSV —
/// نفس القطع اللي بتتفتش فعلياً في البحث قبل/جنب Gemini. الأعمدة
/// المتوقعة في أول صف بالملف بالظبط (بحروف كبيرة/صغيرة زي القاعدة):
/// Part_Number, Brand, Category, Compatible_Model,
/// Additional_Compatibility, Market_Value, Gemini_Insights.
/// Part_Number وحده إلزامي، الباقي اختياري.
class KnowledgeImportScreen extends StatefulWidget {
  const KnowledgeImportScreen({super.key});

  @override
  State<KnowledgeImportScreen> createState() => _KnowledgeImportScreenState();
}

class _KnowledgeImportScreenState extends State<KnowledgeImportScreen> {
  final _repo = KnowledgeBaseRepository();

  static const _allowedColumns = [
    'Part_Number',
    'Brand',
    'Category',
    'Compatible_Model',
    'Additional_Compatibility',
    'Market_Value',
    'Gemini_Insights',
  ];

  bool _loading = false;
  String? _fileName;
  int _parsedRows = 0;
  int _mergedDuplicates = 0;
  int? _importedCount;
  String? _error;

  Future<void> _pickAndImport() async {
    setState(() {
      _loading = true;
      _error = null;
      _importedCount = null;
      _fileName = null;
      _parsedRows = 0;
      _mergedDuplicates = 0;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final picked = result.files.first;
      setState(() => _fileName = picked.name);

      final bytes = picked.bytes;
      if (bytes == null) {
        setState(() {
          _error = 'تعذر قراءة الملف';
          _loading = false;
        });
        return;
      }

      // شيل BOM لو موجود قبل الترميز
      var content = utf8.decode(bytes, allowMalformed: true);
      if (content.startsWith('\uFEFF')) content = content.substring(1);

      final table = const CsvToListConverter(eol: '\n').convert(content, shouldParseNumbers: false);
      if (table.isEmpty) {
        setState(() {
          _error = 'الملف فارغ';
          _loading = false;
        });
        return;
      }

      final headers = table.first.map((h) => h.toString().trim()).toList();
      final partIndex = headers.indexOf('Part_Number');
      if (partIndex == -1) {
        setState(() {
          _error = 'الملف لازم يحتوي عمود Part_Number في الصف الأول';
          _loading = false;
        });
        return;
      }

      // دمج الصفوف المكررة بنفس رقم القطعة داخل الملف نفسه: أول قيمة
      // غير فاضية لكل عمود بتفضل، بدل ما يتبعت صفوف مكررة للقاعدة.
      final Map<String, Map<String, dynamic>> merged = {};
      var totalRows = 0;
      for (final row in table.skip(1)) {
        if (row.every((c) => c.toString().trim().isEmpty)) continue;
        totalRows++;
        final partNumber = row[partIndex].toString().trim();
        if (partNumber.isEmpty) continue;

        final rowMap = <String, dynamic>{};
        for (var i = 0; i < headers.length && i < row.length; i++) {
          if (!_allowedColumns.contains(headers[i])) continue;
          final value = row[i].toString().trim();
          if (value.isNotEmpty) rowMap[headers[i]] = value;
        }
        rowMap['Part_Number'] = partNumber;

        if (merged.containsKey(partNumber)) {
          final existing = merged[partNumber]!;
          for (final entry in rowMap.entries) {
            existing.putIfAbsent(entry.key, () => entry.value);
          }
        } else {
          merged[partNumber] = rowMap;
        }
      }

      setState(() {
        _parsedRows = totalRows;
        _mergedDuplicates = totalRows - merged.length;
      });

      final imported = await _repo.bulkUpsert(merged.values.toList());
      setState(() {
        _importedCount = imported;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'فشل الاستيراد: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'الأعمدة المتوقعة في أول صف بالملف:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 6),
                Text(
                  _allowedColumns.join('، '),
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Part_Number إلزامي، الباقي اختياري. الرقم اللي يتكرر جوه الملف نفسه بيتدمج تلقائياً، ولو رقم القطعة موجود أصلاً في القاعدة هيتحدّث ببيانات الملف.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.6),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _pickAndImport,
                  icon: _loading
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(_loading ? 'جارٍ الاستيراد...' : 'اختيار ملف CSV واستيراده'),
                ),
              ],
            ),
          ),
        ),
        if (_fileName != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('الملف: $_fileName', textAlign: TextAlign.right),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.danger),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
                          textAlign: TextAlign.right),
                    ),
                  ],
                  if (_importedCount != null) ...[
                    const SizedBox(height: 8),
                    Text('صفوف اتقرأت: $_parsedRows', textAlign: TextAlign.right),
                    if (_mergedDuplicates > 0)
                      Text('صفوف اتدمجت (تكرار رقم قطعة): $_mergedDuplicates',
                          textAlign: TextAlign.right),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.success),
                      ),
                      child: Text('تم استيراد $_importedCount رقم قطعة بنجاح',
                          style: const TextStyle(
                              color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12.5),
                          textAlign: TextAlign.right),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}