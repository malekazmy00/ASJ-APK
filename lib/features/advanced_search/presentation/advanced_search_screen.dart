import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/repositories/advanced_search_repository.dart';

/// بحث متقدم — أدمن فقط. بيدور في أي نص مخزّن في ٤ جداول مع بعض
/// (المخزون، قاعدة المعرفة، الاستعلامات، سجل الحركات)، مفيد لو رقم
/// قطعة اتغيّر أو اختفى وعاوز تلاقي أثره من أي كلمة فاكرها.
class AdvancedSearchScreen extends StatefulWidget {
  const AdvancedSearchScreen({super.key});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  final _repo = AdvancedSearchRepository();
  final _controller = TextEditingController();
  bool _loading = false;
  bool _searched = false;

  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _kb = [];
  List<Map<String, dynamic>> _queries = [];
  List<Map<String, dynamic>> _logs = [];

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _searched = true;
    });
    final results = await Future.wait([
      _repo.searchInventory(q),
      _repo.searchKnowledgeBase(q),
      _repo.searchQueries(q),
      _repo.searchLog(q),
    ]);
    if (mounted) {
      setState(() {
        _inventory = results[0];
        _kb = results[1];
        _queries = results[2];
        _logs = results[3];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalResults = _inventory.length + _kb.length + _queries.length + _logs.length;
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
                  hintText: 'دوّر بأي كلمة... ملاحظة، اسم تاجر، جزء من وصف',
                  prefixIcon: Icon(Icons.manage_search),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _loading ? null : _search,
              child: _loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('بحث'),
            ),
          ],
        ),
        if (_searched && !_loading) ...[
          const SizedBox(height: 16),
          if (totalResults == 0)
            const _EmptyNote('مفيش أي نتيجة في أي مكان.')
          else ...[
            if (_inventory.isNotEmpty)
              _ResultSection(
                title: 'المخزون (${_inventory.length})',
                icon: Icons.inventory_2_outlined,
                items: _inventory.map((r) => _ResultTile(
                      title: '${r['part_number']} — #${r['item_id']}',
                      subtitle: [
                        if ((r['description'] as String?)?.isNotEmpty ?? false) r['description'],
                        if ((r['notes'] as String?)?.isNotEmpty ?? false) 'ملاحظة: ${r['notes']}',
                        if ((r['location'] as String?)?.isNotEmpty ?? false) 'الموقع: ${r['location']}',
                      ].join('  •  '),
                    )).toList(),
              ),
            if (_kb.isNotEmpty)
              _ResultSection(
                title: 'قاعدة المعرفة (${_kb.length})',
                icon: Icons.storage_outlined,
                items: _kb.map((r) => _ResultTile(
                      title: r['Part_Number']?.toString() ?? '',
                      subtitle: [
                        if ((r['Part_Model'] as String?)?.isNotEmpty ?? false) 'موديل: ${r['Part_Model']}',
                        if ((r['Brand'] as String?)?.isNotEmpty ?? false) 'البراند: ${r['Brand']}',
                        if ((r['Gemini_Insights'] as String?)?.isNotEmpty ?? false)
                          'ملاحظات: ${r['Gemini_Insights']}',
                      ].join('  •  '),
                    )).toList(),
              ),
            if (_queries.isNotEmpty)
              _ResultSection(
                title: 'استعلامات سابقة (${_queries.length})',
                icon: Icons.history,
                items: _queries.map((r) => _ResultTile(
                      title: '${r['part_number']} — ${r['username']}',
                      subtitle: r['comments']?.toString() ?? '',
                    )).toList(),
              ),
            if (_logs.isNotEmpty)
              _ResultSection(
                title: 'سجل الحركات (${_logs.length})',
                icon: Icons.receipt_long_outlined,
                items: _logs.map((r) {
                  final itemId = r['item_id'];
                  return _ResultTile(
                    title: '${r['action_type']} — '
                        '${itemId != null ? 'قطعة #$itemId — ' : ''}'
                        '${r['username'] ?? ''}',
                    subtitle: r['details']?.toString() ?? '',
                  );
                }).toList(),
              ),
          ],
        ],
      ],
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.title, required this.icon, required this.items});
  final String title;
  final IconData icon;
  final List<_ResultTile> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
              const SizedBox(width: 6),
              Icon(icon, size: 18, color: AppColors.primary),
            ],
          ),
          const SizedBox(height: 6),
          ...items,
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title, textAlign: TextAlign.right),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5)),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning),
      ),
      child: Text(text, textAlign: TextAlign.center),
    );
  }
}