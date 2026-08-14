import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/inventory_item.dart';
import '../../../core/models/knowledge_base_entry.dart';
import '../../../core/repositories/inventory_repository.dart';
import '../../../core/repositories/knowledge_base_repository.dart';
import '../../../core/repositories/approval_repository.dart';
import '../../../core/repositories/notification_repository.dart';
import '../../../core/repositories/field_permissions_repository.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/error_messages.dart';
import '../../../core/models/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../item_timeline/presentation/item_timeline_screen.dart';

/// صفحة تفاصيل قطعة واحدة كاملة (الجولة الثالثة، نقطة ٢) — بتفتح من
/// بطاقة القطعة في InventoryGroupItemsScreen، وفيها بيانات القطعة
/// المحفوظة + خيارات الصرف/الاسترجاع/التتبع/التعديل الأساسي كلها مع
/// بعض في نفس الصفحة.
///
/// تعديل رقم القطعة/السريال بيعدي على نظام الموافقة الموجود زي أي
/// تعديل تاني في التطبيق. إعادة تحليل الصورة بالذكاء الاصطناعي لسه
/// موجودة بس في شاشة التعديل الكاملة (لوحة التعديل) لحد ما نوحّدهم في
/// دفعة لاحقة.
class InventoryItemDetailScreen extends ConsumerStatefulWidget {
  const InventoryItemDetailScreen({super.key, required this.item});
  final InventoryItem item;

  @override
  ConsumerState<InventoryItemDetailScreen> createState() =>
      _InventoryItemDetailScreenState();
}

class _InventoryItemDetailScreenState
    extends ConsumerState<InventoryItemDetailScreen> {
  final _inventoryRepo = InventoryRepository();
  final _kbRepo = KnowledgeBaseRepository();
  final _approvalRepo = ApprovalRepository();
  final _notifRepo = NotificationRepository();
  final _fieldRepo = FieldPermissionsRepository();
  Map<String, bool> _fieldOverrides = {};

  late InventoryItem _item;
  KnowledgeBaseEntry? _kb;
  bool _loading = true;
  // TASK-324: منع تكرار الصرف/الاسترجاع لو المستخدم دبّس الزرار أكتر
  // من مرة (شبكة بطيئة مثلاً) — قبل كده الزرار فضل شغال طول وقت
  // الطلب، وممكن كان يعمل سجلين/إشعارين لنفس العملية.
  bool _dispatching = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _load();
    _loadFieldOverrides();
  }

  /// الجولة الثالثة (نقطة ٢٧): إيه عناصر صفحة تفاصيل القطعة اللي
  /// الأدمن سمح بظهورها لهذا الحساب (نفس تبويب "المخزون").
  Future<void> _loadFieldOverrides() async {
    final username = ref.read(authControllerProvider)?.username;
    if (username == null) return;
    final overrides = await _fieldRepo.getOverrides(username, 'inventory_summary');
    if (mounted) setState(() => _fieldOverrides = overrides);
  }

  bool _fieldVisible(String key) => FieldPermissionsRepository.isVisible(_fieldOverrides, key);

  Future<void> _load() async {
    setState(() => _loading = true);
    final refreshed = await _inventoryRepo.getById(_item.itemId!);
    KnowledgeBaseEntry? kb;
    if (_item.partNumber != 'PENDING' && _item.partNumber.isNotEmpty) {
      kb = await _kbRepo.getByPartNumber(_item.partNumber);
    }
    if (mounted) {
      setState(() {
        _item = refreshed ?? _item;
        _kb = kb;
        _loading = false;
      });
    }
  }

  String get _username => ref.read(authControllerProvider)?.username ?? 'unknown';

  /// الجولة الثالثة (نقطة ٢٤ — إصلاح ثغرة صلاحيات): الأدمن مفتوح له كل
  /// حاجة دايماً (زي باقي التطبيق)، وأي حد تاني لازم يكون عنده
  /// canEdit/canTrack صراحة — نفس الصلاحية اللي بتتحكم في ظهور تبويبَي
  /// "لوحة التعديل"/"تتبع قطعة" المستقلين، عشان محدش يقدر يعدّل أو
  /// يتتبع من هنا لو الصلاحية دي مقفولة له. الصرف/الاسترجاع مقصود
  /// يفضلوا مرتبطين بالوصول لتبويب المخزون نفسه بس، من غير صلاحية
  /// مستقلة، بقرار من مالك.
  bool get _canEdit {
    final user = ref.read(authControllerProvider);
    return user?.role == UserRole.admin || (user?.canEdit ?? false);
  }

  bool get _canTrack {
    final user = ref.read(authControllerProvider);
    return user?.role == UserRole.admin || (user?.canTrack ?? false);
  }

  Future<void> _dispatch() async {
    final result = await showDialog<_DispatchResult>(
      context: context,
      builder: (_) => const _DispatchDialog(),
    );
    if (result == null) return;
    if (_dispatching) return;
    setState(() => _dispatching = true);

    try {
      final details = [
        'صرف إلى: ${result.recipient}',
        if (result.note != null) 'ملاحظة: ${result.note}',
      ].join(' — ');
      final token = ref.read(authControllerProvider.notifier).token;
      await _inventoryRepo.dispatchItem(
        itemId: _item.itemId!,
        token: token,
        details: details,
        exitType: result.exitType.dbValue,
        notifMessage:
            'صرف القطعة #${_item.itemId} (${_item.partNumber}) إلى ${result.recipient}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم تسجيل الصرف')));
      }
      await _load();
    } catch (e, st) {
      AppLogger.logError('InventoryItemDetailScreen._dispatch', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _dispatching = false);
    }
  }

  Future<void> _returnToStock() async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استرجاع للمخزون'),
        content: TextField(
          controller: noteController,
          textAlign: TextAlign.right,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'سبب الاسترجاع (اختياري)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تأكيد الاسترجاع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_dispatching) return;
    setState(() => _dispatching = true);

    try {
      final note = noteController.text.trim();
      final details = note.isEmpty ? 'استرجاع للمخزون' : 'استرجاع للمخزون — $note';
      final token = ref.read(authControllerProvider.notifier).token;
      await _inventoryRepo.returnItem(
        itemId: _item.itemId!,
        token: token,
        details: details,
        notifMessage: 'استرجاع القطعة #${_item.itemId} (${_item.partNumber}) للمخزون',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم الاسترجاع')));
      }
      await _load();
    } catch (e, st) {
      AppLogger.logError('InventoryItemDetailScreen._returnToStock', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _dispatching = false);
    }
  }

  Future<void> _editBasicFields() async {
    final locationController = TextEditingController(text: _item.location);
    final notesController = TextEditingController(text: _item.notes);
    String condition = _item.condition ?? ItemCondition.used.dbValue;
    String ownership = _item.ownershipStatus;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('تعديل بيانات القطعة #${_item.itemId}',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: locationController,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'المكان'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: condition,
                  decoration: const InputDecoration(labelText: 'الحالة'),
                  items: ItemCondition.values
                      .map((e) =>
                          DropdownMenuItem(value: e.dbValue, child: Text(e.dbValue)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => condition = v ?? condition),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: ownership,
                  decoration: const InputDecoration(labelText: 'حالة الملكية'),
                  items: OwnershipStatus.values
                      .map((e) => DropdownMenuItem(
                          value: e.dbValue, child: Text(e.arabicLabel)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => ownership = v ?? ownership),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  textAlign: TextAlign.right,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'ملاحظات'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('حفظ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true) return;
    try {
      final token = ref.read(authControllerProvider.notifier).token;
      await _inventoryRepo.updateItemFieldsAtomic(
        itemId: _item.itemId!,
        token: token,
        location: locationController.text.trim(),
        condition: condition,
        ownershipStatus: ownership,
        notes: notesController.text.trim(),
        logDetails: 'تعديل بيانات أساسية من صفحة تفاصيل القطعة',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم الحفظ')));
      }
      await _load();
    } catch (e, st) {
      AppLogger.logError('InventoryItemDetailScreen._editBasicFields', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e)), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  /// تعديل رقم القطعة/السريال — بيعدي على نظام الموافقة زي باقي
  /// التطبيق، مش بيتطبق فوراً.
  Future<void> _requestSensitiveEdit({
    required bool isPartNumber,
  }) async {
    final controller = TextEditingController(
      text: isPartNumber ? _item.partNumber : (_item.serialNumber ?? ''),
    );
    final newValue = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isPartNumber ? 'طلب تعديل رقم القطعة' : 'طلب تعديل الرقم التسلسلي'),
        content: TextField(
          controller: controller,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(labelText: 'القيمة الجديدة'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('إرسال للموافقة'),
          ),
        ],
      ),
    );
    if (newValue == null || newValue.isEmpty) return;

    await _approvalRepo.create(
      type: isPartNumber ? ApprovalType.partNumberEdit : ApprovalType.serialEdit,
      payload: {
        'itemId': _item.itemId,
        if (isPartNumber) 'oldPartNumber': _item.partNumber,
        if (isPartNumber) 'newPartNumber': newValue,
        if (!isPartNumber) 'oldSerial': _item.serialNumber,
        if (!isPartNumber) 'newSerial': newValue,
      },
      requestedBy: _username,
    );
    await _notifRepo.create(
      notifType: (isPartNumber
              ? NotificationEventType.partNumberEdit
              : NotificationEventType.serialEdit)
          .dbValue,
      message:
          '${_username} طلب تعديل ${isPartNumber ? 'رقم القطعة' : 'الرقم التسلسلي'} للقطعة #${_item.itemId}',
      relatedId: _item.itemId,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الطلب لموافقة الأدمن')));
    }
  }

  Future<void> _openTimeline() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('تتبع القطعة')),
        body: ItemTimelineScreen(
          initialPartNumber: _item.partNumber,
          initialItemId: _item.itemId,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final available = _item.status == 'Available';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _item.partNumber == 'PENDING' ? 'تفاصيل القطعة' : _item.partNumber,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _row('رقم القطعة الداخلي (اكتبه على القطعة)', '#${_item.itemId}'),
                    _row('النوع', _item.itemType),
                    _row('رقم القطعة',
                        _item.partNumber == 'PENDING' ? 'بدون رقم' : _item.partNumber,
                        onEdit: _canEdit ? () => _requestSensitiveEdit(isPartNumber: true) : null),
                    _row('الرقم التسلسلي', _item.serialNumber ?? '—',
                        onEdit: _canEdit ? () => _requestSensitiveEdit(isPartNumber: false) : null),
                    if (_kb?.partModel != null) _row('الموديل (اسم كودي)', _kb!.partModel!),
                    if (_kb?.brand != null) _row('البراند', _kb!.brand!),
                    if (_kb?.compatibleModel != null)
                      _row('الجهاز المتوافق', _kb!.compatibleModel!),
                    if (_item.description != null && _item.description!.isNotEmpty)
                      _row('الوصف', _item.description!),
                    if (_fieldVisible('location_field'))
                      _row('المكان', _item.location ?? '—'),
                    _row('الحالة (فنية)', _item.condition ?? '—'),
                    _row('حالة المخزون', _item.status),
                    _row('حالة الملكية', _item.ownershipStatus),
                    if (_fieldVisible('market_value') &&
                        _kb?.marketValue != null &&
                        _kb!.marketValue!.isNotEmpty)
                      _row('السعر التقريبي', _kb!.marketValue!),
                    if (_item.notes != null && _item.notes!.isNotEmpty)
                      _row('ملاحظات', _item.notes!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_fieldVisible('dispatch_button'))
                  available
                      ? ElevatedButton.icon(
                          onPressed: _dispatching ? null : _dispatch,
                          icon: const Icon(Icons.outbox),
                          label: const Text('صرف'),
                        )
                      : ElevatedButton.icon(
                          onPressed: _dispatching ? null : _returnToStock,
                          icon: const Icon(Icons.undo),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                          label: const Text('استرجاع للمخزون'),
                        ),
                if (_fieldVisible('track_button'))
                  OutlinedButton.icon(
                    onPressed: _canTrack ? _openTimeline : null,
                    icon: const Icon(Icons.timeline_outlined),
                    label: const Text('تتبع'),
                  ),
                if (_fieldVisible('edit_button'))
                  OutlinedButton.icon(
                    onPressed: _canEdit ? _editBasicFields : null,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل البيانات'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {VoidCallback? onEdit}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit, size: 18, color: AppColors.textMuted),
              onPressed: onEdit,
              visualDensity: VisualDensity.compact,
            ),
          Expanded(
            child: Text(value, textAlign: TextAlign.right),
          ),
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

class _DispatchResult {
  final String recipient;
  final ExitType exitType;
  final String? note;
  const _DispatchResult(this.recipient, this.exitType, this.note);
}

class _DispatchDialog extends StatefulWidget {
  const _DispatchDialog();

  @override
  State<_DispatchDialog> createState() => _DispatchDialogState();
}

class _DispatchDialogState extends State<_DispatchDialog> {
  final _controller = TextEditingController();
  final _noteController = TextEditingController();
  ExitType _exitType = ExitType.sale;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('صرف القطعة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(labelText: 'اسم المستلم/الجهة'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ExitType>(
            initialValue: _exitType,
            decoration: const InputDecoration(labelText: 'سبب الصرف'),
            items: ExitType.values
                .map((e) => DropdownMenuItem(value: e, child: Text(e.arabicLabel)))
                .toList(),
            onChanged: (v) => setState(() => _exitType = v ?? _exitType),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            textAlign: TextAlign.right,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(
            _DispatchResult(
              _controller.text,
              _exitType,
              _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
            ),
          ),
          child: const Text('تأكيد الصرف'),
        ),
      ],
    );
  }
}