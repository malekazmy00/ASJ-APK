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
import '../../../core/widgets/barcode_scanner_page.dart';
import '../../auth/presentation/auth_providers.dart';

/// محتوى شاشة الإدخال - تبويب داخل الشاشة الموحّدة (role_home_screen.dart).
/// ٣ أنواع إدخال: قطعة برقم / قطعة بدون رقم / معدة شغل — كل قطعة
/// بتتسجل لوحدها (اتشالت خانة "عدد القطع")، وبعد الحفظ بيبان رقم الـ
/// ID بشكل واضح عشان يتكتب على القطعة فعلياً.
enum _EntryMode { withPartNumber, withoutPartNumber, equipment }

class WorkerBody extends ConsumerStatefulWidget {
  const WorkerBody({super.key});

  @override
  ConsumerState<WorkerBody> createState() => _WorkerBodyState();
}

class _WorkerBodyState extends ConsumerState<WorkerBody> {
  final _inputController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();

  String _itemType = defaultItemTypes.first;
  ItemCondition _condition = ItemCondition.used;
  OwnershipStatus _ownership = OwnershipStatus.owned;
  _EntryMode _mode = _EntryMode.withPartNumber;

  bool _isAnalyzing = false;
  bool _isSaving = false;
  Map<String, dynamic>? _aiResult;
  List<int> _lastSavedIds = [];
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;

  final _inventoryRepo = InventoryRepository();
  final _knowledgeRepo = KnowledgeBaseRepository();
  final _logRepo = LogRepository();

  late final TextEditingController _partNumberField = TextEditingController();
  late final TextEditingController _partModelField = TextEditingController();
  late final TextEditingController _serialField = TextEditingController();
  late final TextEditingController _brandField = TextEditingController();
  late final TextEditingController _categoryField = TextEditingController();
  late final TextEditingController _compatibleModelField = TextEditingController();
  late final TextEditingController _additionalCompatField = TextEditingController();
  late final TextEditingController _marketValueField = TextEditingController();
  late final TextEditingController _notesField = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _partNumberField.dispose();
    _partModelField.dispose();
    _serialField.dispose();
    _brandField.dispose();
    _categoryField.dispose();
    _compatibleModelField.dispose();
    _additionalCompatField.dispose();
    _marketValueField.dispose();
    _notesField.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1280,
    );
    if (file != null) setState(() => _pickedImage = file);
  }

  Future<void> _analyze() async {
    final text = _inputController.text.trim();
    if (text.isEmpty && _pickedImage == null) {
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

      final Map<String, dynamic> requestBody = {
        'partNumberOrText': text.isNotEmpty ? text : 'غير معروف - حلل من الصورة',
      };
      if (imageBase64 != null) {
        requestBody['imageBase64'] = imageBase64;
      }

      final response = await Supabase.instance.client.functions.invoke(
        'analyze-part',
        body: requestBody,
      );

      final data = response.data;
      if (data is! Map || data['success'] != true) {
        final errMsg = (data is Map ? data['error'] : null) ?? 'رد غير متوقع من الخادم';
        _showSnack('تعذر التحليل: $errMsg', isError: true);
        return;
      }

      final result = Map<String, dynamic>.from(data['result'] as Map);
      setState(() {
        _aiResult = result;
        _partNumberField.text = result['Part_Number'] ?? '';
        _partModelField.text = result['Part_Model'] ?? '';
        _serialField.text = result['Serial_Number'] ?? '';
        _brandField.text = result['Brand'] ?? '';
        _categoryField.text = result['Category'] ?? '';
        _compatibleModelField.text = result['Compatible_Model'] ?? '';
        _additionalCompatField.text = result['Additional_Compatibility'] ?? '';
        _marketValueField.text = result['Market_Value'] ?? '';
        _notesField.text = result['Gemini_Insights'] ?? '';
      });
    } catch (e) {
      _showSnack('خطأ في الاتصال بخدمة التحليل: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _onSavePressed() async {
    // تأكيد بس في مسار "برقم قطعة" لو التحليل معرفش يحدد رقم واضح.
    // مش مطلوب في مسار "بدون رقم" ولا "معدة شغل" لأنهم أصلاً من غير رقم.
    if (_mode == _EntryMode.withPartNumber && _partNumberField.text.trim().isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('رقم القطعة غير واضح'),
          content: const Text(
            'التحليل ما قدرش يحدد رقم القطعة. متأكد إنك عاوز تحفظ القطعة من غير رقم؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('احفظ من غير رقم'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _save();
  }

  Future<void> _save() async {
    final username = ref.read(authControllerProvider)?.username ?? 'unknown';
    final isEquipment = _mode == _EntryMode.equipment;
    final hasPartNumber = _mode == _EntryMode.withPartNumber;
    final partNumber = hasPartNumber && _partNumberField.text.trim().isNotEmpty
        ? _partNumberField.text.trim()
        : 'PENDING';

    setState(() => _isSaving = true);
    try {
      final item = InventoryItem(
        itemType: _itemType,
        partNumber: partNumber,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        entryType: isEquipment ? EntryType.equipment.dbValue : EntryType.part.dbValue,
        location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
        condition: _condition.dbValue,
        status: 'Available',
        serialNumber: _serialField.text.trim().isEmpty ? null : _serialField.text.trim(),
        ownershipStatus: _ownership.dbValue,
      );

      final saved = await _inventoryRepo.bulkInsert([item]);

      if (hasPartNumber && partNumber != 'PENDING') {
        await _knowledgeRepo.createOrAppendInsight(
          partNumber: partNumber,
          geminiInsights: _notesField.text.trim(),
        );
        await _knowledgeRepo.setPartModelIfEmpty(partNumber, _partModelField.text.trim());
      }

      for (final saved1 in saved) {
        if (saved1.itemId != null) {
          await _logRepo.logAction(
            itemId: saved1.itemId,
            actionType: ActionType.insert,
            username: username,
            details: '${isEquipment ? 'إضافة معدة' : 'إضافة قطعة'} ${saved1.itemType} - '
                '$partNumber (${_ownership.arabicLabel})',
          );
        }
      }

      setState(() {
        _lastSavedIds = saved.map((e) => e.itemId!).toList();
        _aiResult = null;
        _inputController.clear();
        _descriptionController.clear();
        _notesController.clear();
        _pickedImage = null;
        _partNumberField.clear();
        _partModelField.clear();
        _serialField.clear();
      });
      _showSnack('تم الحفظ بنجاح');
    } catch (e) {
      _showSnack('فشل الحفظ: $e', isError: true);
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
    final isEquipment = _mode == _EntryMode.equipment;
    final hasPartNumber = _mode == _EntryMode.withPartNumber;
    final showAnalysis = !isEquipment; // البحث بالذكاء الاصطناعي متاح لمسارَي القطع بس

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_lastSavedIds.isNotEmpty) _SavedIdsBanner(ids: _lastSavedIds),

        _SectionCard(
          title: 'نوع الإدخال',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ThreeWayToggle(
                mode: _mode,
                onChanged: (m) => setState(() => _mode = m),
              ),
              const SizedBox(height: 6),
              Text(
                isEquipment
                    ? 'معدة شغل (عدة/جهاز مساعد) — بتاخد ID خاص بيها زي أي قطعة.'
                    : hasPartNumber
                        ? 'القطعة معاها رقم رسمي من الشركة المصنعة.'
                        : 'للشاسيهات أو الأطقم اللي مالهاش رقم قطعة رسمي.',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ),

        _SectionCard(
          title: 'حالة الملكية',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: OwnershipStatus.values.map((o) {
              final selected = _ownership == o;
              return ChoiceChip(
                label: Text(o.arabicLabel),
                selected: selected,
                onSelected: (_) => setState(() => _ownership = o),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList(),
          ),
        ),

        _SectionCard(
          title: isEquipment ? 'بيانات المعدة' : 'الصورة والتحليل',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _itemType,
                decoration: InputDecoration(labelText: isEquipment ? 'نوع المعدة' : 'نوع القطعة'),
                items: defaultItemTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _itemType = v ?? _itemType),
              ),
              const SizedBox(height: 12),
              if (showAnalysis) ...[
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
                  decoration: InputDecoration(
                    labelText: 'رقم القطعة أو وصفها (اختياري لو مرفقة صورة)',
                    hintText: 'مثال: 5199650 أو "بوردة تغذية سيمنس"',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'مسح باركود',
                      onPressed: () async {
                        final code = await scanBarcode(context);
                        if (code != null && code.isNotEmpty) {
                          _inputController.text = code;
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (!showAnalysis) ...[
                TextField(
                  controller: _descriptionController,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'وصف المعدة'),
                ),
                const SizedBox(height: 12),
              ],
              if (!hasPartNumber && !isEquipment) ...[
                TextField(
                  controller: _descriptionController,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'الوصف'),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _notesController,
                textAlign: TextAlign.right,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<ItemCondition>(
                      initialValue: _condition,
                      decoration: const InputDecoration(labelText: 'الحالة'),
                      items: ItemCondition.values
                          .map((c) => DropdownMenuItem(value: c, child: Text(c.dbValue)))
                          .toList(),
                      onChanged: (v) => setState(() => _condition = v ?? _condition),
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
              if (showAnalysis) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isAnalyzing ? null : _analyze,
                  icon: _isAnalyzing
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isAnalyzing ? 'جارٍ التحليل...' : 'بحث'),
                ),
              ],
            ],
          ),
        ),

        if (showAnalysis && _aiResult != null)
          _SectionCard(
            title: 'نتيجة التحليل (قابلة للتعديل)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasPartNumber)
                  _EditableRow(label: 'رقم القطعة', controller: _partNumberField),
                _EditableRow(label: 'الموديل (الاسم الكودي)', controller: _partModelField),
                _EditableRow(label: 'الرقم التسلسلي (Serial)', controller: _serialField),
                _EditableRow(label: 'الماركة', controller: _brandField),
                _EditableRow(label: 'الوصف/الفئة', controller: _categoryField),
                _EditableRow(label: 'الجهاز المتوافق', controller: _compatibleModelField),
                _EditableRow(label: 'أجهزة متوافقة إضافية', controller: _additionalCompatField),
                _EditableRow(label: 'تقدير السعر', controller: _marketValueField),
                _EditableRow(label: 'ملاحظات فنية', controller: _notesField, maxLines: 3),
              ],
            ),
          ),

        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _onSavePressed,
          icon: _isSaving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ],
    );
  }
}

/// مفتاح ثلاثي: قطعة برقم / قطعة بدون رقم / معدة شغل.
class _ThreeWayToggle extends StatelessWidget {
  const _ThreeWayToggle({required this.mode, required this.onChanged});
  final _EntryMode mode;
  final ValueChanged<_EntryMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFEEF2F5), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: _seg('برقم قطعة', _EntryMode.withPartNumber)),
          Expanded(child: _seg('بدون رقم', _EntryMode.withoutPartNumber)),
          Expanded(child: _seg('معدة شغل', _EntryMode.equipment)),
        ],
      ),
    );
  }

  Widget _seg(String label, _EntryMode value) {
    final active = mode == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: active ? [const BoxShadow(color: Color(0x1A0A2540), blurRadius: 6)] : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.bold,
            color: active ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _EditableRow extends StatelessWidget {
  const _EditableRow({required this.label, required this.controller, this.maxLines = 1});
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
                child: Image.file(File(pickedImage!.path), height: 150, width: double.infinity, fit: BoxFit.cover),
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
            'الصورة تُستخدم فقط لتحليل الذكاء الاصطناعي حالياً ولا تُحفظ بشكل دائم بعد.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// بانر بعد الحفظ — بارز وواضح إن الرقم ده لازم يتكتب على القطعة نفسها.
class _SavedIdsBanner extends StatelessWidget {
  const _SavedIdsBanner({required this.ids});
  final List<int> ids;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                ids.length == 1 ? 'رقم القطعة الداخلي: #${ids.first}' : 'أرقام القطع: ${ids.join('، ')}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.success),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit_note, color: AppColors.success),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'اكتب الرقم ده على القطعة نفسها — بيفضل ثابت للقطعة دي طول الوقت حتى لو خرجت ورجعت.',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}