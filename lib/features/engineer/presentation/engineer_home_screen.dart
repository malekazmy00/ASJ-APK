import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/inventory_item.dart';
import '../../../core/repositories/inventory_repository.dart';
import '../../../core/repositories/knowledge_base_repository.dart';
import '../../../core/repositories/log_repository.dart';
import '../../../core/models/engineer_query.dart';
import '../../../core/repositories/engineer_query_repository.dart';
import '../../auth/presentation/auth_providers.dart';

/// واجهة المهندس: تبويبان — (1) بحث ذكي + صرف/بيع، (2) لوحة تعديل
/// ديناميكية بفلاتر وحذف نهائي. مطابقة لتدفق views/engineer.py الأصلي.
class EngineerHomeScreen extends ConsumerStatefulWidget {
  const EngineerHomeScreen({super.key});

  @override
  ConsumerState<EngineerHomeScreen> createState() => _EngineerHomeScreenState();
}

class _EngineerHomeScreenState extends ConsumerState<EngineerHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('واجهة المهندس'),
        backgroundColor: AppColors.roleEngineer,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'بحث وصرف', icon: Icon(Icons.search)),
            Tab(text: 'لوحة التعديل', icon: Icon(Icons.edit_note)),
            Tab(text: 'دفتر الاستعلامات', icon: Icon(Icons.assignment_outlined)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _SmartSearchTab(),
          _EditDashboardTab(),
          _QueriesTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// تبويب البحث الذكي والصرف
// ---------------------------------------------------------------------

class _SmartSearchTab extends ConsumerStatefulWidget {
  const _SmartSearchTab();

  @override
  ConsumerState<_SmartSearchTab> createState() => _SmartSearchTabState();
}

class _SmartSearchTabState extends ConsumerState<_SmartSearchTab> {
  final _searchController = TextEditingController();
  final _inventoryRepo = InventoryRepository();
  final _knowledgeRepo = KnowledgeBaseRepository();
  final _logRepo = LogRepository();

  bool _isSearching = false;
  List<InventoryItem> _inventoryResults = [];
  bool _searchedKnowledgeBase = false;
  String? _knowledgeBaseNote;
  final Set<int> _dispatchingIds = {}; // منع الضغط المتكرر أثناء تنفيذ الصرف

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _inventoryResults = [];
      _searchedKnowledgeBase = false;
      _knowledgeBaseNote = null;
    });

    try {
      // 1) المخزون أولاً (زي النظام الأصلي بالظبط)
      final items = await _inventoryRepo.smartSearch(query);

      if (items.isNotEmpty) {
        setState(() => _inventoryResults = items);
      } else {
        // 2) لو مفيش نتيجة، نجرب قاعدة المعرفة (قبل اللجوء لـ Gemini)
        final kbResults = await _knowledgeRepo.searchByCategoryOrPart(query);
        setState(() {
          _searchedKnowledgeBase = true;
          _knowledgeBaseNote = kbResults.isEmpty
              ? 'القطعة غير موجودة في المخزون ولا في قاعدة المعرفة.'
              : 'غير متوفرة في المخزون حالياً، لكن معروفة في قاعدة المعرفة:\n'
                  '${kbResults.map((e) => '${e.partNumber} — ${e.category ?? ''}').join('\n')}';
        });
      }

      final username = ref.read(authControllerProvider)?.username ?? 'unknown';
      await _logRepo.logAction(
        actionType: ActionType.search,
        username: username,
        details: 'بحث عن: $query',
      );
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _dispatch(InventoryItem item) async {
    if (_dispatchingIds.contains(item.itemId)) return; // منع تكرار الصرف لنفس القطعة
    final recipient = await showDialog<String>(
      context: context,
      builder: (context) => _RecipientDialog(),
    );
    if (recipient == null || recipient.trim().isEmpty) return;

    setState(() => _dispatchingIds.add(item.itemId!));
    try {
      final username = ref.read(authControllerProvider)?.username ?? 'unknown';
      await _inventoryRepo.updateStatus(item.itemId!, 'Out');
      await _logRepo.logAction(
        itemId: item.itemId,
        actionType: ActionType.out,
        username: username,
        details: 'تم الصرف إلى: $recipient',
      );

      setState(() {
        _inventoryResults.removeWhere((e) => e.itemId == item.itemId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم صرف القطعة #${item.itemId} إلى $recipient'),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
              ElevatedButton(
                onPressed: _isSearching ? null : _search,
                child: _isSearching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('بحث'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_searchedKnowledgeBase && _knowledgeBaseNote != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning),
              ),
              child: Text(_knowledgeBaseNote!, textAlign: TextAlign.right),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _inventoryResults.length,
              itemBuilder: (context, index) {
                final item = _inventoryResults[index];
                return Card(
                  child: ListTile(
                    title: Text('${item.partNumber} — ${item.itemType}',
                        textAlign: TextAlign.right),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientDialog extends StatefulWidget {
  @override
  State<_RecipientDialog> createState() => _RecipientDialogState();
}

class _RecipientDialogState extends State<_RecipientDialog> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('صرف القطعة'),
      content: TextField(
        controller: _controller,
        textAlign: TextAlign.right,
        decoration: const InputDecoration(labelText: 'اسم المستلم/الجهة'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('تأكيد الصرف'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// تبويب لوحة التعديل الديناميكية
// ---------------------------------------------------------------------

class _EditDashboardTab extends ConsumerStatefulWidget {
  const _EditDashboardTab();

  @override
  ConsumerState<_EditDashboardTab> createState() => _EditDashboardTabState();
}

class _EditDashboardTabState extends ConsumerState<_EditDashboardTab> {
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
// تبويب دفتر الاستعلامات (طلب قطعة غير متوفرة)
// ---------------------------------------------------------------------

class _QueriesTab extends ConsumerStatefulWidget {
  const _QueriesTab();

  @override
  ConsumerState<_QueriesTab> createState() => _QueriesTabState();
}

class _QueriesTabState extends ConsumerState<_QueriesTab> {
  final _repo = EngineerQueryRepository();
  final _partNumberController = TextEditingController();
  final _targetDeviceController = TextEditingController();
  final _merchantNameController = TextEditingController();
  final _merchantPhoneController = TextEditingController();
  final _commentsController = TextEditingController();
  QueryReason _reason = QueryReason.inspection;

  List<EngineerQuery> _queries = [];
  bool _loading = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _repo.getRecent();
    if (mounted) {
      setState(() {
        _queries = list;
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final partNumber = _partNumberController.text.trim();
    if (partNumber.isEmpty) return;
    final username = ref.read(authControllerProvider)?.username ?? 'unknown';

    setState(() => _submitting = true);
    try {
      await _repo.create(EngineerQuery(
        username: username,
        partNumber: partNumber,
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
      _partNumberController.clear();
      _targetDeviceController.clear();
      _merchantNameController.clear();
      _merchantPhoneController.clear();
      _commentsController.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _partNumberController.dispose();
    _targetDeviceController.dispose();
    _merchantNameController.dispose();
    _merchantPhoneController.dispose();
    _commentsController.dispose();
    super.dispose();
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
                Text('طلب استعلام جديد',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _partNumberController,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(labelText: 'رقم القطعة المطلوبة'),
                ),
                const SizedBox(height: 10),
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
                  decoration: const InputDecoration(labelText: 'الجهاز المطلوبة له (اختياري)'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _merchantNameController,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(labelText: 'اسم التاجر (اختياري)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _merchantPhoneController,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(labelText: 'رقم التاجر (اختياري)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _commentsController,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(_submitting ? 'جارٍ الإرسال...' : 'تسجيل الاستعلام'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('آخر الاستعلامات', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(),
        ..._queries.map((q) => Card(
              child: ListTile(
                title: Text('${q.partNumber} — ${q.queryReason}',
                    textAlign: TextAlign.right),
                subtitle: Text(
                  '${q.username}${q.targetDevice != null ? ' • ${q.targetDevice}' : ''}',
                  textAlign: TextAlign.right,
                ),
                trailing: Chip(label: Text(q.status)),
              ),
            )),
      ],
    );
  }
}
