import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/inventory_item.dart';
import '../../../core/repositories/inventory_repository.dart';
import '../../../core/repositories/knowledge_base_repository.dart';
import '../../../core/repositories/log_repository.dart';
import '../../auth/presentation/auth_providers.dart';

/// واجهة العامل: إدخال/وصف القطعة (نص و/أو صورة) -> تحليل بالذكاء
/// الاصطناعي (Edge Function: analyze-part، بيستقبل الصورة كمان لو
/// موجودة) -> مراجعة وتعديل يدوي -> حفظ جماعي (Bulk Save) بعدد قطع.
/// ملاحظة مهمة: الصورة تُستخدم فقط للتحليل اللحظي، ولا تُرفع/تُحفظ بشكل
/// دائم على Supabase Storage بعد — ده قرار مؤجل منفصل تماماً (راجع
/// PROJECT_PLAN.md)، مش تأجيل لاستخدام الصورة في التحليل نفسه.
class WorkerHomeScreen extends ConsumerStatefulWidget {
  const WorkerHomeScreen({super.key});

  @override
  ConsumerState<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends ConsumerState<WorkerHomeScreen> {
  final _inputController = TextEditingController();
  final _locationController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  String _itemType = defaultItemTypes.first;
  ItemCondition _condition = ItemCondition.used;

  bool _isAnalyzing = false;
  bool _isSaving = false;
  Map<String, dynamic>? _aiResult;
  List<int> _lastSavedIds = [];
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;

  final _inventoryRepo = InventoryRepository();
  final _knowledgeRepo = KnowledgeBaseRepository();
  final _logRepo = LogRepository();

  // حقول قابلة للتعديل بعد التحليل
  late final TextEditingController _partNumberField = TextEditingController();
  late final TextEditingController _brandField = TextEditingController();
  late final TextEditingController _categoryField = TextEditingController();
  late final TextEditingController _compatibleModelField = TextEditingController();
  late final TextEditingController _notesField = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    _locationController.dispose();
    _quantityController.dispose();
    _partNumberField.dispose();
    _brandField.dispose();
    _categoryField.dispose();
    _compatibleModelField.dispose();
    _notesField.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 70, // تصغير الحجم قبل الإرسال لـ Gemini، مش تخزين دائم
      maxWidth: 1280,
    );
    if (file != null) setState(() => _pickedImage = file);
  }

  Future<void> _analyze() async {
    if (_inputController.text.trim().isEmpty && _pickedImage == null) {
      _showSnack('اكتب رقم القطعة/وصفها أو التقط صورة الأول', isError: true);
      return;
    }
    setState(() {
      _isAnalyzing = true;
      _aiResult = null;
      _lastSavedIds = [];
    });

    try {
      String? imageBase64;
      if (_pickedImage != null) {
        final bytes = await File(_pickedImage!.path).readAsBytes();
        imageBase64 = base64Encode(bytes);
      }

      final response = await Supabase.instance.client.functions.invoke(
        'analyze-part',
        body: {
          'partNumberOrText': _inputController.text.trim(),
          if (imageBase64 != null) 'imageBase64': imageBase64,
        },
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null || data['success'] != true) {
        _showSnack(
          'تعذر التحليل: ${data?['error'] ?? 'خطأ غير معروف'}',
          isError: true,
        );
        return;
      }

      final result = data['result'] as Map<String, dynamic>;
      setState(() {
        _aiResult = result;
        _partNumberField.text = result['Part_Number'] ?? '';
        _brandField.text = result['Brand'] ?? '';
        _categoryField.text = result['Category'] ?? '';
        _compatibleModelField.text = result['Compatible_Model'] ?? '';
        _notesField.text = result['Gemini_Insights'] ?? '';
      });
    } catch (e) {
      _showSnack('خطأ في الاتصال بخدمة التحليل', isError: true);
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _save() async {
    final partNumber = _partNumberField.text.trim();
    if (partNumber.isEmpty) {
      _showSnack('رقم القطعة مطلوب قبل الحفظ', isError: true);
      return;
    }
    final quantity = int.tryParse(_quantityController.text) ?? 1;
    final username = ref.read(authControllerProvider)?.username ?? 'unknown';

    setState(() => _isSaving = true);
    try {
      final items = List.generate(
        quantity,
        (_) => InventoryItem(
          itemType: _itemType,
          partNumber: partNumber,
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          condition: _condition.dbValue,
          status: 'Available',
        ),
      );

      final saved = await _inventoryRepo.bulkInsert(items);

      // نفس منطق create_or_update الأصلي: لا نكتب فوق قاعدة معرفة موجودة
      await _knowledgeRepo.createOrAppendInsight(
        partNumber: partNumber,
        geminiInsights: _notesField.text.trim(),
      );

      for (final item in saved) {
        if (item.itemId != null) {
          await _logRepo.logAction(
            itemId: item.itemId,
            actionType: ActionType.insert,
            username: username,
            details: 'إضافة قطعة عبر واجهة العامل',
          );
        }
      }

      setState(() {
        _lastSavedIds = saved.map((e) => e.itemId!).toList();
        _aiResult = null;
        _inputController.clear();
        _quantityController.text = '1';
        _pickedImage = null;
      });
      _showSnack('تم الحفظ بنجاح (${saved.length} قطعة)');
    } catch (e) {
      _showSnack('فشل الحفظ، حاول مرة أخرى', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('واجهة العامل'),
        backgroundColor: AppColors.roleWorker,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_lastSavedIds.isNotEmpty) _SavedIdsBanner(ids: _lastSavedIds),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('إدخال القطعة', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _itemType,
                    decoration: const InputDecoration(labelText: 'نوع القطعة'),
                    items: defaultItemTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _itemType = v ?? _itemType),
                  ),
                  const SizedBox(height: 12),
                  _ImagePickerRow(
                    pickedImage: _pickedImage,
                    onCamera: () => _pickImage(ImageSource.camera),
                    onGallery: () => _pickImage(ImageSource.gallery),
                    onRemove: () => setState(() => _pickedImage = null),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inputController,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'رقم القطعة أو وصفها (اختياري لو مرفقة صورة)',
                      hintText: 'مثال: 5199650 أو "بوردة تغذية سيمنس"',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<ItemCondition>(
                          initialValue: _condition,
                          decoration: const InputDecoration(labelText: 'الحالة'),
                          items: ItemCondition.values
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c.dbValue),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _condition = v ?? _condition),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _locationController,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(labelText: 'الموقع'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isAnalyzing ? null : _analyze,
                    icon: _isAnalyzing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(_isAnalyzing ? 'جارٍ التحليل...' : 'تحليل بالذكاء الاصطناعي'),
                  ),
                ],
              ),
            ),
          ),
          if (_aiResult != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('نتيجة التحليل (قابلة للتعديل)',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _EditableRow(label: 'رقم القطعة', controller: _partNumberField),
                    _EditableRow(label: 'الماركة', controller: _brandField),
                    _EditableRow(label: 'الوصف/الفئة', controller: _categoryField),
                    _EditableRow(
                        label: 'الجهاز المتوافق', controller: _compatibleModelField),
                    _EditableRow(
                      label: 'ملاحظات فنية',
                      controller: _notesField,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('عدد القطع: '),
                        SizedBox(
                          width: 70,
                          child: TextField(
                            controller: _quantityController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_isSaving ? 'جارٍ الحفظ...' : 'حفظ'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditableRow extends StatelessWidget {
  const _EditableRow({
    required this.label,
    required this.controller,
    this.maxLines = 1,
  });

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

class _ImagePickerRow extends StatelessWidget {
  const _ImagePickerRow({
    required this.pickedImage,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  final XFile? pickedImage;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pickedImage != null)
          Stack(
            alignment: Alignment.topLeft,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(pickedImage!.path),
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              IconButton.filled(
                onPressed: onRemove,
                style: IconButton.styleFrom(backgroundColor: AppColors.danger),
                icon: const Icon(Icons.close, size: 18, color: Colors.white),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('التقاط صورة'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('من المعرض'),
                ),
              ),
            ],
          ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'الصورة تُستخدم فقط لتحليل الذكاء الاصطناعي حالياً ولا تُحفظ بشكل دائم بعد (مرحلة رفع الصور لسه مؤجلة).',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _SavedIdsBanner extends StatelessWidget {
  const _SavedIdsBanner({required this.ids});
  final List<int> ids;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success),
      ),
      child: Text(
        'تم إنشاء أرقام القطع: ${ids.join('، ')}',
        style: const TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.right,
      ),
    );
  }
}
