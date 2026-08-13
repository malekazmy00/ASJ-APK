import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/knowledge_base_repository.dart';
import '../../../core/repositories/approval_repository.dart';
import '../../../core/repositories/notification_repository.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/error_messages.dart';
import '../../auth/presentation/auth_providers.dart';

/// استيراد قاعدة المعرفة الفنية (specs_knowledge_base) من ملف CSV —
/// نفس القطع اللي بتتفتش فعلياً في البحث قبل/جنب Gemini. الأعمدة
/// المتوقعة في أول صف بالملف بالظبط (بحروف كبيرة/صغيرة زي القاعدة):
/// Part_Number, Part_Model, Brand, Category, Compatible_Model,
/// Additional_Compatibility, Market_Value, Gemini_Insights.
/// Part_Number وحده إلزامي، الباقي اختياري.
///
/// الاستيراد مش بيتطبّق فوراً — بياخد نسخة احتياطية كاملة من القاعدة
/// الأول، وبعدين بيتبعت كطلب موافقة للأدمن (زي تعديل رقم القطعة/السريال
/// بالظبط)، ومايتطبقش فعلياً إلا بعد الموافقة من تبويب "الموافقات".
class KnowledgeImportScreen extends ConsumerStatefulWidget {
  const KnowledgeImportScreen({super.key});

  @override
  ConsumerState<KnowledgeImportScreen> createState() => _KnowledgeImportScreenState();
}

class _KnowledgeImportScreenState extends ConsumerState<KnowledgeImportScreen> {
  final _repo = KnowledgeBaseRepository();
  final _approvalRepo = ApprovalRepository();
  final _notificationRepo = NotificationRepository();

  static const _allowedColumns = [
    'Part_Number',
    'Part_Model',
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
  bool _submitted = false;
  String? _error;

  Future<void> _pickAndSubmit() async {
    final username = ref.read(authControllerProvider)?.username;
    if (username == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _submitted = false;
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

      // نسخة احتياطية كاملة من القاعدة قبل ما الطلب يتبعت، بغض النظر
      // هل هيتوافق عليه ولا لأ — الاحتياط جاهز من هنا.
      await _repo.backupSnapshot(username);

      await _approvalRepo.create(
        type: ApprovalType.kbImport,
        payload: {'rows': merged.values.toList(), 'fileName': picked.name},
        requestedBy: username,
      );
      await _notificationRepo.create(
        notifType: 'kb_import',
        message: '$username طلب استيراد ${merged.length} رقم قطعة لقاعدة المعرفة من ملف "${picked.name}"',
      );

      setState(() {
        _submitted = true;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.logError('KnowledgeImportScreen._prepareRequest', e, st);
      setState(() {
        _error = friendlyErrorMessage(e);
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
                  'Part_Number إلزامي، الباقي اختياري. الرقم اللي يتكرر جوه الملف نفسه بيتدمج تلقائياً. الاستيراد بياخد نسخة احتياطية من القاعدة أولاً، وبعدين بيتبعت لموافقة الأدمن — مش هيتطبق إلا بعد الموافقة من تبويب "الموافقات".',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.6),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _pickAndSubmit,
                  icon: _loading
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(_loading ? 'جارٍ التجهيز...' : 'اختيار ملف CSV وإرساله للموافقة'),
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
                  if (_submitted) ...[
                    const SizedBox(height: 8),
                    Text('صفوف اتقرأت: $_parsedRows', textAlign: TextAlign.right),
                    if (_mergedDuplicates > 0)
                      Text('صفوف اتدمجت (تكرار رقم قطعة): $_mergedDuplicates',
                          textAlign: TextAlign.right),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.warning),
                      ),
                      child: const Text(
                        'اتبعت نسخة احتياطية وطلب موافقة — راجع تبويب "الموافقات" لتفعيل الاستيراد فعلياً.',
                        style: TextStyle(
                            color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: 12.5),
                        textAlign: TextAlign.right,
                      ),
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