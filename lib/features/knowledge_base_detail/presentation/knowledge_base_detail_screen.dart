import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/knowledge_base_entry.dart';
import '../../../core/repositories/knowledge_base_repository.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/error_messages.dart';

/// صفحة تفاصيل مستقلة لقطعة من قاعدة المعرفة (الجولة الثالثة، نقطة
/// ٢٦) — بتفتح من قسم "قاعدة المعرفة" في تبويب "بحث" بس، بتعرض كل
/// الحقول المحفوظة كاملة (مش السطرين المختصرين اللي في نتيجة البحث)،
/// مع إمكانية تعديل فوري — نفس منطق حقول قاعدة المعرفة في "لوحة
/// التعديل" بالضبط (بيتحفظوا على طول من غير موافقة أدمن).
class KnowledgeBaseDetailScreen extends StatefulWidget {
  const KnowledgeBaseDetailScreen({super.key, required this.partNumber});
  final String partNumber;

  @override
  State<KnowledgeBaseDetailScreen> createState() => _KnowledgeBaseDetailScreenState();
}

class _KnowledgeBaseDetailScreenState extends State<KnowledgeBaseDetailScreen> {
  final _repo = KnowledgeBaseRepository();
  KnowledgeBaseEntry? _entry;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  late final TextEditingController _partModelField;
  late final TextEditingController _brandField;
  late final TextEditingController _categoryField;
  late final TextEditingController _compatibleModelField;
  late final TextEditingController _additionalCompatField;
  late final TextEditingController _marketValueField;
  late final TextEditingController _insightsField;

  @override
  void initState() {
    super.initState();
    _partModelField = TextEditingController();
    _brandField = TextEditingController();
    _categoryField = TextEditingController();
    _compatibleModelField = TextEditingController();
    _additionalCompatField = TextEditingController();
    _marketValueField = TextEditingController();
    _insightsField = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entry = await _repo.getByPartNumber(widget.partNumber);
    if (mounted) {
      setState(() {
        _entry = entry;
        _partModelField.text = entry?.partModel ?? '';
        _brandField.text = entry?.brand ?? '';
        _categoryField.text = entry?.category ?? '';
        _compatibleModelField.text = entry?.compatibleModel ?? '';
        _additionalCompatField.text = entry?.additionalCompatibility ?? '';
        _marketValueField.text = entry?.marketValue ?? '';
        _insightsField.text = entry?.geminiInsights ?? '';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _partModelField.dispose();
    _brandField.dispose();
    _categoryField.dispose();
    _compatibleModelField.dispose();
    _additionalCompatField.dispose();
    _marketValueField.dispose();
    _insightsField.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final fields = <String, dynamic>{
        'Part_Model': _partModelField.text.trim(),
        'Brand': _brandField.text.trim(),
        'Category': _categoryField.text.trim(),
        'Compatible_Model': _compatibleModelField.text.trim(),
        'Additional_Compatibility': _additionalCompatField.text.trim(),
        'Market_Value': _marketValueField.text.trim(),
        'Gemini_Insights': _insightsField.text.trim(),
      };
      await _repo.upsertFields(widget.partNumber, fields);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم الحفظ')));
        setState(() => _editing = false);
      }
      await _load();
    } catch (e, st) {
      AppLogger.logError('KnowledgeBaseDetailScreen._save', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.partNumber),
        actions: [
          if (!_loading && !_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _editing = true),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: _editing
                    ? [
                        _EditField(label: 'الموديل (الاسم الكودي)', controller: _partModelField),
                        _EditField(label: 'البراند', controller: _brandField),
                        _EditField(label: 'الفئة/الوصف', controller: _categoryField),
                        _EditField(label: 'الجهاز المتوافق', controller: _compatibleModelField),
                        _EditField(label: 'أجهزة متوافقة إضافية', controller: _additionalCompatField),
                        _EditField(label: 'السعر التقريبي', controller: _marketValueField),
                        _EditField(label: 'ملاحظات فنية', controller: _insightsField, maxLines: 4),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () {
                                        setState(() => _editing = false);
                                        _load();
                                      },
                                child: const Text('إلغاء'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _saving ? null : _save,
                                child: _saving
                                    ? const SizedBox(
                                        width: 18, height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('حفظ'),
                              ),
                            ),
                          ],
                        ),
                      ]
                    : [
                        if (_entry == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: Center(
                              child: Text('لا توجد بيانات محفوظة عن هذه القطعة بعد',
                                  style: TextStyle(color: AppColors.textMuted)),
                            ),
                          )
                        else
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _row('رقم القطعة', _entry!.partNumber),
                                  if (_entry!.partModel != null && _entry!.partModel!.isNotEmpty)
                                    _row('الموديل (الاسم الكودي)', _entry!.partModel!),
                                  if (_entry!.brand != null && _entry!.brand!.isNotEmpty)
                                    _row('البراند', _entry!.brand!),
                                  if (_entry!.category != null && _entry!.category!.isNotEmpty)
                                    _row('الفئة/الوصف', _entry!.category!),
                                  if (_entry!.compatibleModel != null && _entry!.compatibleModel!.isNotEmpty)
                                    _row('الجهاز المتوافق', _entry!.compatibleModel!),
                                  if (_entry!.additionalCompatibility != null &&
                                      _entry!.additionalCompatibility!.isNotEmpty)
                                    _row('أجهزة متوافقة إضافية', _entry!.additionalCompatibility!),
                                  if (_entry!.marketValue != null && _entry!.marketValue!.isNotEmpty)
                                    _row('السعر التقريبي', _entry!.marketValue!),
                                  if (_entry!.geminiInsights != null && _entry!.geminiInsights!.isNotEmpty)
                                    _row('ملاحظات فنية', _entry!.geminiInsights!),
                                  if (_entry!.lastUpdated != null)
                                    _row('آخر تحديث', _entry!.lastUpdated.toString()),
                                ],
                              ),
                            ),
                          ),
                      ],
              ),
            ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(value, textAlign: TextAlign.right)),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({required this.label, required this.controller, this.maxLines = 1});
  final String label;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        textAlign: TextAlign.right,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}