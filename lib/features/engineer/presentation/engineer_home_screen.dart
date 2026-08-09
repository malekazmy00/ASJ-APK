import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/inventory_item.dart';
import '../../../core/models/knowledge_base_entry.dart';
import '../../../core/repositories/inventory_repository.dart';
import '../../../core/repositories/knowledge_base_repository.dart';
import '../../../core/repositories/log_repository.dart';
import '../../../core/repositories/approval_repository.dart';
import '../../../core/repositories/notification_repository.dart';
import '../../../core/models/engineer_query.dart';
import '../../../core/repositories/engineer_query_repository.dart';
import '../../../core/widgets/barcode_scanner_page.dart';
import '../../auth/presentation/auth_providers.dart';

// ---------------------------------------------------------------------
// تبويب البحث الذكي والصرف (ودفتر الاستعلامات المدمج)
// يُستخدم الآن كمحتوى تبويب داخل الشاشة الموحّدة (role_home_screen.dart)
// بدل شاشة منفصلة بـ Scaffold خاص بيه.
// ---------------------------------------------------------------------

class SmartSearchTab extends ConsumerStatefulWidget {
  const SmartSearchTab({super.key});

  @override
  ConsumerState<SmartSearchTab> createState() => _SmartSearchTabState();
}

class _SmartSearchTabState extends ConsumerState<SmartSearchTab> {
  final _searchController = TextEditingController();
  final _targetDeviceController = TextEditingController();
  final _merchantNameController = TextEditingController();
  final _merchantPhoneController = TextEditingController();
  final _commentsController = TextEditingController();
  QueryReason _reason = QueryReason.inspection;
  bool _showDetails = false;

  final _inventoryRepo = InventoryRepository();
  final _knowledgeRepo = KnowledgeBaseRepository();
  final _logRepo = LogRepository();
  final _queryRepo = EngineerQueryRepository();
  final _notificationRepo = NotificationRepository();

  bool _isSearching = false;
  bool _hasSearched = false;
  List<InventoryItem> _inventoryResults = [];
  List<KnowledgeBaseEntry> _knowledgeResults = [];
  List<EngineerQuery> _previousQueries = [];
  final Set<int> _dispatchingIds = {}; // منع الضغط المتكرر أثناء تنفيذ الصرف

  bool _geminiLoading = false;
  Map<String, dynamic>? _geminiResult;
  String? _geminiError;

  @override
  void dispose() {
    _searchController.dispose();
    _targetDeviceController.dispose();
    _merchantNameController.dispose();
    _merchantPhoneController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _inventoryResults = [];
      _knowledgeResults = [];
      _previousQueries = [];
      _geminiLoading = true;
      _geminiResult = null;
      _geminiError = null;
    });

    // بحث Gemini الحي بيشتغل بالتوازي من غير ما يوقف عرض النتائج الداخلية
    unawaited(_runGeminiSearch(query));

    try {
      final username = ref.read(authControllerProvider)?.username ?? 'unknown';

      // الاتنين مع بعض دايماً: المخزون الفعلي + قاعدة المعرفة الداخلية
      // (بيانات ميدانية موثوقة) — مفيش تسلسل يوقف عند أول نتيجة.
      final items = await _inventoryRepo.smartSearch(query);
      final kbResults = await _knowledgeRepo.searchByCategoryOrPart(query);
      final previousQueries = await _queryRepo.getByPartNumber(query);

      if (mounted) {
        setState(() {
          _inventoryResults = items;
          _knowledgeResults = kbResults;
          _previousQueries = previousQueries;
        });
      }

      // كل بحث هو نفسه استعلام مسجَّل (زي النظام الأصلي بالظبط) — بيتسجل
      // تلقائياً بالتفاصيل الإضافية لو اتملت، أو بس رقم القطعة وسبب افتراضي.
      await _queryRepo.create(EngineerQuery(
        username: username,
        partNumber: query,
        partCategory: kbResults.isNotEmpty ? kbResults.first.category : null,
        queryReason: _reason.dbValue,
        targetDevice: _targetDeviceController.text.trim().isEmpty
            ? null
            : _targetDeviceController.text.trim(),
        merchantName: _merchantNameController.text.trim().isEmpty
            ? null
            : _merchantNameController.text.trim(),
        merchantPhone: _merchantPhoneController.text.trim().isEmpty
            ? null
            : _merchantPhoneController.text.trim(),
        comments: _commentsController.text.trim().isEmpty
            ? null
            : _commentsController.text.trim(),
      ));

      await _logRepo.logAction(
        actionType: ActionType.search,
        username: username,
        details: 'بحث عن: $query',
      );

      // إشعار الأدمن بكل استعلام جديد (بيتجاهل بصمت لو النوع ده موقوف
      // من الإعدادات)
      await _notificationRepo.create(
        notifType: 'new_query',
        message: 'استعلام جديد من $username عن "$query"',
      );

      // تفضيل تصفير الحقول الإضافية بعد كل بحث ناجح عشان البحث الجاي
      // يبدأ نضيف، من غير ما يورّث بيانات تاجر/جهاز بحث سابق بالغلط.
      _targetDeviceController.clear();
      _merchantNameController.clear();
      _merchantPhoneController.clear();
      _commentsController.clear();
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _runGeminiSearch(String query) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'search-part',
        body: {'query': query},
      );
      final data = response.data;
      if (data is! Map || data['success'] != true) {
        final errMsg = (data is Map ? data['error'] : null) ?? 'رد غير متوقع من الخادم';
        if (mounted) setState(() => _geminiError = errMsg.toString());
        return;
      }
      if (mounted) {
        setState(() => _geminiResult = Map<String, dynamic>.from(data['result'] as Map));
      }
    } catch (e) {
      if (mounted) setState(() => _geminiError = 'تعذر الوصول لبحث Gemini الحي');
    } finally {
      if (mounted) setState(() => _geminiLoading = false);
    }
  }

  Future<void> _dispatch(InventoryItem item) async {
    if (_dispatchingIds.contains(item.itemId)) return; // منع تكرار الصرف لنفس القطعة
    final result = await showDialog<_DispatchResult>(
      context: context,
      builder: (context) => _RecipientDialog(),
    );
    if (result == null || result.recipient.trim().isEmpty) return;

    setState(() => _dispatchingIds.add(item.itemId!));
    try {
      final username = ref.read(authControllerProvider)?.username ?? 'unknown';
      await _inventoryRepo.updateStatus(item.itemId!, 'Out');
      await _logRepo.logAction(
        itemId: item.itemId,
        actionType: ActionType.out,
        username: username,
        details: 'تم الصرف إلى: ${result.recipient} (${result.exitType.arabicLabel})'
            '${result.note != null ? ' — ملاحظة: ${result.note}' : ''}',
        exitType: result.exitType.dbValue,
      );

      setState(() {
        _inventoryResults.removeWhere((e) => e.itemId == item.itemId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم صرف القطعة #${item.itemId} إلى ${result.recipient}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('فشل الصرف، حاول مرة أخرى'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _dispatchingIds.remove(item.itemId));
    }
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
                controller: _searchController,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: 'ابحث برقم القطعة أو النوع...',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'مسح باركود',
              onPressed: () async {
                final code = await scanBarcode(context);
                if (code != null && code.isNotEmpty) {
                  _searchController.text = code;
                  _search();
                }
              },
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isSearching ? null : _search,
              child: _isSearching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('بحث'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // تفاصيل الاستعلام (اختيارية) — بتتسجل مع البحث نفسه بدل نموذج منفصل
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: const Text('تفاصيل إضافية عن الاستعلام (اختياري)', textAlign: TextAlign.right),
            initiallyExpanded: _showDetails,
            onExpansionChanged: (v) => setState(() => _showDetails = v),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            children: [
              DropdownButtonFormField<QueryReason>(
                initialValue: _reason,
                decoration: const InputDecoration(labelText: 'سبب الاستعلام'),
                items: QueryReason.values
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.dbValue)))
                    .toList(),
                onChanged: (v) => setState(() => _reason = v ?? _reason),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _targetDeviceController,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'الجهاز المطلوبة له'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _merchantNameController,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(labelText: 'اسم التاجر'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _merchantPhoneController,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(labelText: 'رقم التاجر'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _commentsController,
                textAlign: TextAlign.right,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
              ),
            ],
          ),
        ),
        if (_hasSearched) ...[
          const SizedBox(height: 8),
          _SectionHeader('المتاح في المخزون الآن', Icons.inventory_2_outlined),
          if (_inventoryResults.isEmpty)
            const _EmptyNote('غير متوفرة في المخزون حالياً.')
          else
            ..._inventoryResults.map((item) => Card(
                  child: ListTile(
                    title: Text('${item.partNumber} — ${item.itemType}', textAlign: TextAlign.right),
                    subtitle: Text(
                      'رقم القطعة الداخلي: #${item.itemId}  •  الحالة: ${item.status}'
                      '${item.location != null ? '  •  الموقع: ${item.location}' : ''}',
                      textAlign: TextAlign.right,
                    ),
                    trailing: item.status == 'Available'
                        ? TextButton.icon(
                            onPressed: _dispatchingIds.contains(item.itemId)
                                ? null
                                : () => _dispatch(item),
                            icon: _dispatchingIds.contains(item.itemId)
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.outbox_outlined),
                            label: const Text('صرف'),
                          )
                        : Chip(label: Text(item.status)),
                  ),
                )),
          const SizedBox(height: 16),
          _SectionHeader('من قاعدة المعرفة الداخلية', Icons.storage_outlined),
          if (_knowledgeResults.isEmpty)
            const _EmptyNote('لا توجد بيانات محفوظة عن هذه القطعة في قاعدة المعرفة.')
          else
            ..._knowledgeResults.map((e) => Card(
                  child: ListTile(
                    title: Text(e.partNumber, textAlign: TextAlign.right),
                    subtitle: Text(
                      [
                        if (e.brand != null && e.brand!.isNotEmpty) 'البراند: ${e.brand}',
                        if (e.category != null && e.category!.isNotEmpty) 'النوع: ${e.category}',
                        if (e.compatibleModel != null && e.compatibleModel!.isNotEmpty)
                          'يناسب: ${e.compatibleModel}',
                        if (e.marketValue != null && e.marketValue!.isNotEmpty)
                          'السعر التقريبي: ${e.marketValue}',
                      ].join('  •  '),
                      textAlign: TextAlign.right,
                    ),
                  ),
                )),
          const SizedBox(height: 16),
          _SectionHeader('بحث Gemini المباشر', Icons.auto_awesome_outlined),
          if (_geminiLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_geminiError != null)
            _EmptyNote(_geminiError!)
          else if (_geminiResult != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if ((_geminiResult!['Summary'] as String? ?? '').isNotEmpty)
                      Text(_geminiResult!['Summary'], textAlign: TextAlign.right),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if ((_geminiResult!['Brand'] as String? ?? '').isNotEmpty)
                          'البراند: ${_geminiResult!['Brand']}',
                        if ((_geminiResult!['Category'] as String? ?? '').isNotEmpty)
                          'النوع: ${_geminiResult!['Category']}',
                        if ((_geminiResult!['Compatible_Model'] as String? ?? '').isNotEmpty)
                          'يناسب: ${_geminiResult!['Compatible_Model']}',
                        if ((_geminiResult!['Market_Value'] as String? ?? '').isNotEmpty)
                          'السعر التقريبي: ${_geminiResult!['Market_Value']}',
                      ].join('  •  '),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          _SectionHeader('استعلامات سابقة على نفس القطعة', Icons.history),
          if (_previousQueries.isEmpty)
            const _EmptyNote('لا توجد استعلامات سابقة مسجلة على هذه القطعة.')
          else
            ..._previousQueries.map((q) => Card(
                  child: ListTile(
                    title: Text('${q.username} — ${q.queryReason}', textAlign: TextAlign.right),
                    subtitle: Text(
                      q.targetDevice != null ? 'للجهاز: ${q.targetDevice}' : '',
                      textAlign: TextAlign.right,
                    ),
                    trailing: Chip(label: Text(QueryStatus.fromDb(q.status).arabicLabel)),
                  ),
                )),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Icon(icon, size: 20),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning),
      ),
      child: Text(text, textAlign: TextAlign.right),
    );
  }
}

class _DispatchResult {
  final String recipient;
  final ExitType exitType;
  final String? note;
  const _DispatchResult(this.recipient, this.exitType, this.note);
}

class _RecipientDialog extends StatefulWidget {
  @override
  State<_RecipientDialog> createState() => _RecipientDialogState();
}

class _RecipientDialogState extends State<_RecipientDialog> {
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

// ---------------------------------------------------------------------
// تبويب لوحة التعديل الديناميكية
// ---------------------------------------------------------------------

class EditDashboardTab extends ConsumerStatefulWidget {
  const EditDashboardTab({super.key});

  @override
  ConsumerState<EditDashboardTab> createState() => _EditDashboardTabState();
}

class _EditDashboardTabState extends ConsumerState<EditDashboardTab> {
  final _inventoryRepo = InventoryRepository();
  final _logRepo = LogRepository();
  final _filterController = TextEditingController();
  String? _statusFilter;
  List<InventoryItem> _items = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _inventoryRepo.getFiltered(
      status: _statusFilter,
      searchText: _filterController.text.trim(),
    );
    if (mounted) setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _confirmDelete(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('حذف القطعة #${item.itemId} نهائياً؟ لا يمكن التراجع.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final username = ref.read(authControllerProvider)?.username ?? 'unknown';
    await _logRepo.logAction(
      itemId: item.itemId,
      actionType: ActionType.delete,
      username: username,
      details: 'حذف نهائي من لوحة التعديل',
    );
    await _inventoryRepo.deletePermanently(item.itemId!);
    _load();
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
                  controller: _filterController,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'فلترة برقم القطعة/الموقع'),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String?>(
                value: _statusFilter,
                hint: const Text('الحالة'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('الكل')),
                  DropdownMenuItem(value: 'Available', child: Text('متاح')),
                  DropdownMenuItem(value: 'Out', child: Text('صادر')),
                  DropdownMenuItem(value: 'Reserved', child: Text('محجوز')),
                  DropdownMenuItem(value: 'Damaged', child: Text('تالف')),
                ],
                onChanged: (v) {
                  setState(() => _statusFilter = v);
                  _load();
                },
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              return Card(
                child: ListTile(
                  title: Text('${item.partNumber} — ${item.itemType}',
                      textAlign: TextAlign.right),
                  subtitle: Text(
                    '#${item.itemId} • ${item.status} • ${item.condition ?? ''}',
                    textAlign: TextAlign.right,
                  ),
                  onTap: () async {
                    final username = ref.read(authControllerProvider)?.username ?? 'unknown';
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => _ItemEditSheet(item: item, username: username),
                    );
                    _load();
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    onPressed: () => _confirmDelete(item),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// شاشة تعديل قطعة كاملة: حقول المخزون + حقول قاعدة المعرفة المرتبطة
// برقم القطعة مع بعض، بدل شاشتين منفصلتين.
// ---------------------------------------------------------------------

class _ItemEditSheet extends StatefulWidget {
  const _ItemEditSheet({required this.item, required this.username});
  final InventoryItem item;
  final String username;

  @override
  State<_ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<_ItemEditSheet> {
  final _inventoryRepo = InventoryRepository();
  final _knowledgeRepo = KnowledgeBaseRepository();
  final _logRepo = LogRepository();
  final _approvalRepo = ApprovalRepository();
  final _notificationRepo = NotificationRepository();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  bool _reanalyzing = false;
  XFile? _pickedImage;

  late final TextEditingController _partNumberField;
  late final TextEditingController _partModelField;
  late final TextEditingController _locationField;
  late final TextEditingController _serialField;
  ItemCondition _condition = ItemCondition.used;
  ItemStatus _status = ItemStatus.available;
  OwnershipStatus _ownership = OwnershipStatus.owned;

  late final TextEditingController _brandField;
  late final TextEditingController _categoryField;
  late final TextEditingController _compatibleModelField;
  late final TextEditingController _additionalCompatField;
  late final TextEditingController _marketValueField;
  late final TextEditingController _insightsField;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _partNumberField = TextEditingController(text: item.partNumber == 'PENDING' ? '' : item.partNumber);
    _locationField = TextEditingController(text: item.location ?? '');
    _serialField = TextEditingController(text: item.serialNumber ?? '');
    _condition = ItemCondition.fromDb(item.condition);
    _status = ItemStatus.fromDb(item.status);
    _ownership = OwnershipStatus.fromDb(item.ownershipStatus);

    _partModelField = TextEditingController();
    _brandField = TextEditingController();
    _categoryField = TextEditingController();
    _compatibleModelField = TextEditingController();
    _additionalCompatField = TextEditingController();
    _marketValueField = TextEditingController();
    _insightsField = TextEditingController();
    _loadKnowledge();
  }

  Future<void> _loadKnowledge() async {
    final kb = await _knowledgeRepo.getByPartNumber(widget.item.partNumber);
    if (kb != null && mounted) {
      setState(() {
        _partModelField.text = kb.partModel ?? '';
        _brandField.text = kb.brand ?? '';
        _categoryField.text = kb.category ?? '';
        _compatibleModelField.text = kb.compatibleModel ?? '';
        _additionalCompatField.text = kb.additionalCompatibility ?? '';
        _marketValueField.text = kb.marketValue ?? '';
        _insightsField.text = kb.geminiInsights ?? '';
      });
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _partNumberField.dispose();
    _partModelField.dispose();
    _locationField.dispose();
    _serialField.dispose();
    _brandField.dispose();
    _categoryField.dispose();
    _compatibleModelField.dispose();
    _additionalCompatField.dispose();
    _marketValueField.dispose();
    _insightsField.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1280);
    if (file != null) setState(() => _pickedImage = file);
  }

  /// إعادة تحليل بصورة جديدة — بيملى الحقول للمراجعة، ومش بيحفظ لوحده،
  /// المهندس لازم يدوس "حفظ" بعدها زي أي تعديل تاني.
  Future<void> _reanalyze() async {
    if (_pickedImage == null && _partNumberField.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('التقط صورة أو اكتب رقم القطعة الأول')),
      );
      return;
    }
    setState(() => _reanalyzing = true);
    try {
      String? imageBase64;
      if (_pickedImage != null) {
        final bytes = await File(_pickedImage!.path).readAsBytes();
        imageBase64 = base64Encode(bytes);
      }
      final response = await Supabase.instance.client.functions.invoke(
        'analyze-part',
        body: {
          'partNumberOrText': _partNumberField.text.trim().isNotEmpty
              ? _partNumberField.text.trim()
              : 'غير معروف - حلل من الصورة',
          if (imageBase64 != null) 'imageBase64': imageBase64,
        },
      );
      final data = response.data;
      if (data is! Map || data['success'] != true) {
        final errMsg = (data is Map ? data['error'] : null) ?? 'رد غير متوقع من الخادم';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر التحليل: $errMsg'), backgroundColor: AppColors.danger),
          );
        }
        return;
      }
      final result = Map<String, dynamic>.from(data['result'] as Map);
      setState(() {
        if ((result['Part_Number'] as String? ?? '').isNotEmpty) {
          _partNumberField.text = result['Part_Number'];
        }
        if ((result['Part_Model'] as String? ?? '').isNotEmpty) {
          _partModelField.text = result['Part_Model'];
        }
        if ((result['Serial_Number'] as String? ?? '').isNotEmpty) {
          _serialField.text = result['Serial_Number'];
        }
        _brandField.text = result['Brand'] ?? _brandField.text;
        _categoryField.text = result['Category'] ?? _categoryField.text;
        _compatibleModelField.text = result['Compatible_Model'] ?? _compatibleModelField.text;
        _additionalCompatField.text = result['Additional_Compatibility'] ?? _additionalCompatField.text;
        _marketValueField.text = result['Market_Value'] ?? _marketValueField.text;
        _insightsField.text = result['Gemini_Insights'] ?? _insightsField.text;
        _pickedImage = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التحليل: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _reanalyzing = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final originalPartNumber = widget.item.partNumber;
      final originalSerial = widget.item.serialNumber ?? '';
      final newPartNumber = _partNumberField.text.trim().isEmpty
          ? originalPartNumber
          : _partNumberField.text.trim();
      final newSerial = _serialField.text.trim();
      final partNumberChanged = newPartNumber != originalPartNumber;
      final serialChanged = newSerial != originalSerial;

      // الحقول العادية بتتحدث فوراً. رقم القطعة والسريال بس، لو
      // اتغيروا، بيروحوا لطلب موافقة الأدمن بدل ما يتحفظوا على طول.
      await _inventoryRepo.updateFields(widget.item.itemId!, {
        'location': _locationField.text.trim().isEmpty ? null : _locationField.text.trim(),
        'condition': _condition.dbValue,
        'status': _status.dbValue,
        'ownership_status': _ownership.dbValue,
        if (!serialChanged) 'serial_number': newSerial.isEmpty ? null : newSerial,
      });

      await _logRepo.logAction(
        itemId: widget.item.itemId,
        actionType: ActionType.update,
        username: widget.username,
        details: 'تعديل بيانات القطعة (الموقع/الحالة الفنية/حالة الملكية)',
      );

      final pendingLabels = <String>[];
      if (partNumberChanged) {
        await _approvalRepo.create(
          type: ApprovalType.partNumberEdit,
          payload: {
            'itemId': widget.item.itemId,
            'oldPartNumber': originalPartNumber,
            'newPartNumber': newPartNumber,
          },
          requestedBy: widget.username,
        );
        await _notificationRepo.create(
          notifType: 'part_number_edit',
          message: '${widget.username} طلب تعديل رقم القطعة #${widget.item.itemId} '
              'من "$originalPartNumber" إلى "$newPartNumber"',
        );
        pendingLabels.add('رقم القطعة');
      }
      if (serialChanged) {
        await _approvalRepo.create(
          type: ApprovalType.serialEdit,
          payload: {
            'itemId': widget.item.itemId,
            'oldSerial': originalSerial,
            'newSerial': newSerial,
          },
          requestedBy: widget.username,
        );
        await _notificationRepo.create(
          notifType: 'serial_edit',
          message: '${widget.username} طلب تعديل الرقم التسلسلي للقطعة #${widget.item.itemId} '
              'من "$originalSerial" إلى "$newSerial"',
        );
        pendingLabels.add('الرقم التسلسلي');
      }

      // قاعدة المعرفة (البراند/الموديل/الفئة...) بتتحدث فوراً من غير
      // موافقة — دي مرتبطة برقم القطعة الحالي (القديم) لحد ما طلب
      // التعديل لو موجود يتوافق عليه.
      final kbFields = <String, dynamic>{};
      void addIfNotEmpty(String key, String value) {
        if (value.trim().isNotEmpty) kbFields[key] = value.trim();
      }
      addIfNotEmpty('Part_Model', _partModelField.text);
      addIfNotEmpty('Brand', _brandField.text);
      addIfNotEmpty('Category', _categoryField.text);
      addIfNotEmpty('Compatible_Model', _compatibleModelField.text);
      addIfNotEmpty('Additional_Compatibility', _additionalCompatField.text);
      addIfNotEmpty('Market_Value', _marketValueField.text);
      addIfNotEmpty('Gemini_Insights', _insightsField.text);
      if (kbFields.isNotEmpty) {
        await _knowledgeRepo.upsertFields(originalPartNumber, kbFields);
      }

      if (mounted) {
        if (pendingLabels.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('اتبعت طلب تعديل ${pendingLabels.join(' و')} للأدمن للموافقة'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _returnToInventory() async {
    final receivedByController = TextEditingController();
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استرجاع القطعة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: receivedByController,
              textAlign: TextAlign.right,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'استلمها (اسمك أو اسم المستلم)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              textAlign: TextAlign.right,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'سبب الاسترجاع (اختياري)'),
            ),
          ],
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
    final receivedBy = receivedByController.text.trim().isEmpty
        ? widget.username
        : receivedByController.text.trim();
    final note = noteController.text.trim();

    setState(() => _saving = true);
    try {
      await _inventoryRepo.updateStatus(widget.item.itemId!, 'Available');
      await _logRepo.logAction(
        itemId: widget.item.itemId,
        actionType: ActionType.return_,
        username: widget.username,
        details: 'تم استرجاع القطعة إلى المخزون — استلمها: $receivedBy'
            '${note.isNotEmpty ? ' — ملاحظة: $note' : ''}',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الاسترجاع: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${widget.item.partNumber} — #${widget.item.itemId}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
              textAlign: TextAlign.right,
            ),
            if (ItemStatus.fromDb(widget.item.status) == ItemStatus.out) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _returnToInventory,
                icon: const Icon(Icons.assignment_return_outlined),
                label: const Text('استرجاع القطعة للمخزون'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.success),
              ),
            ],
            const SizedBox(height: 16),
            Text('إعادة تحليل بصورة (اختياري)', style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.right),
            const SizedBox(height: 8),
            if (_pickedImage != null)
              Stack(
                alignment: Alignment.topLeft,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(_pickedImage!.path), height: 130, width: double.infinity, fit: BoxFit.cover),
                  ),
                  IconButton.filled(
                    onPressed: () => setState(() => _pickedImage = null),
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
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('كاميرا'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('من المعرض'),
                    ),
                  ),
                ],
              ),
            if (_pickedImage == null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _reanalyzing ? null : _reanalyze,
                icon: _reanalyzing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: const Text('إعادة تحليل (بدون صورة، برقم القطعة المكتوب)'),
              ),
            ],
            if (_pickedImage != null) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _reanalyzing ? null : _reanalyze,
                icon: _reanalyzing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome),
                label: const Text('حلّل الصورة دي'),
              ),
            ],
            const SizedBox(height: 16),
            Text('بيانات المخزون', style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.right),
            const SizedBox(height: 8),
            TextField(
              controller: _partNumberField,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'رقم القطعة',
                helperText: 'أي تغيير هنا محتاج موافقة الأدمن قبل ما يتفعّل',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _locationField,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'الموقع'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _serialField,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'الرقم التسلسلي (Serial)',
                helperText: 'أي تغيير هنا محتاج موافقة الأدمن قبل ما يتفعّل',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<ItemStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'الحالة'),
              items: ItemStatus.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.arabicLabel)))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<ItemCondition>(
              initialValue: _condition,
              decoration: const InputDecoration(labelText: 'الحالة الفنية'),
              items: ItemCondition.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.dbValue)))
                  .toList(),
              onChanged: (v) => setState(() => _condition = v ?? _condition),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<OwnershipStatus>(
              initialValue: _ownership,
              decoration: const InputDecoration(labelText: 'حالة الملكية'),
              items: OwnershipStatus.values
                  .map((o) => DropdownMenuItem(value: o, child: Text(o.arabicLabel)))
                  .toList(),
              onChanged: (v) => setState(() => _ownership = v ?? _ownership),
            ),
            const SizedBox(height: 20),
            Text('قاعدة المعرفة الفنية', style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.right),
            const SizedBox(height: 8),
            TextField(
              controller: _partModelField,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'الموديل (الاسم الكودي)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _brandField,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'البراند'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _categoryField,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'الفئة/الوصف'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _compatibleModelField,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'الجهاز المتوافق'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _additionalCompatField,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'أجهزة متوافقة إضافية'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _marketValueField,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'السعر التقريبي'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _insightsField,
              textAlign: TextAlign.right,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'ملاحظات فنية'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('حفظ كل التعديلات'),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}