import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/app_user.dart';
import '../../../core/repositories/log_repository.dart';
import '../../../core/repositories/user_repository.dart';

enum _Period { today, week, month, all }

/// سجل نشاط عام موحّد — الجولة الثالثة (نقطة ١٠): بدل سجل بس عن
/// transactions_log، دلوقتي بيجمع من كل مصادر السجل المتفرقة
/// (transactions_log، engineer_queries، user_sessions،
/// pending_approvals) في مكان واحد، مع فلتر نوع الحدث + الفترة +
/// المستخدم، الثلاثة قابلين للدمج مع بعض.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _repo = LogRepository();
  final _userRepo = UserRepository();

  _Period _period = _Period.week;
  String _eventType = 'ALL';
  String? _username; // null = كل المستخدمين
  List<AppUser> _users = [];

  bool _loading = true;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _userRepo.getAll().then((u) {
      if (mounted) setState(() => _users = u);
    });
    _load();
  }

  DateTime? get _sinceForPeriod {
    final now = DateTime.now();
    switch (_period) {
      case _Period.today:
        return DateTime(now.year, now.month, now.day);
      case _Period.week:
        return now.subtract(const Duration(days: 7));
      case _Period.month:
        return now.subtract(const Duration(days: 30));
      case _Period.all:
        return null;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await _repo.getUnified(
      eventType: _eventType,
      since: _sinceForPeriod,
      username: _username,
    );
    if (mounted) setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  String _periodLabel(_Period p) {
    switch (p) {
      case _Period.today:
        return 'اليوم';
      case _Period.week:
        return '٧ أيام';
      case _Period.month:
        return '٣٠ يوم';
      case _Period.all:
        return 'الكل';
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'INSERT':
        return Icons.add_box_outlined;
      case 'UPDATE':
        return Icons.edit_note;
      case 'DELETE':
        return Icons.delete_outline;
      case 'OUT':
        return Icons.outbox_outlined;
      case 'RETURN':
        return Icons.assignment_return_outlined;
      case 'SEARCH':
        return Icons.search;
      case 'LOGIN':
        return Icons.login;
      case 'LOGOUT':
        return Icons.logout;
      case 'EXPORT':
        return Icons.ios_share;
      case 'IMPORT':
        return Icons.upload_file_outlined;
      case 'USER_MGMT':
        return Icons.admin_panel_settings_outlined;
      case 'DB_RESTORE':
        return Icons.restore;
      case 'QUERY':
        return Icons.manage_search;
      case 'SESSION':
        return Icons.phonelink_outlined;
      case 'APPROVAL':
        return Icons.pending_actions;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(
            spacing: 8,
            alignment: WrapAlignment.end,
            children: _Period.values.map((p) {
              final selected = _period == p;
              return ChoiceChip(
                label: Text(_periodLabel(p)),
                selected: selected,
                onSelected: (_) {
                  setState(() => _period = p);
                  _load();
                },
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _eventType,
                  decoration: const InputDecoration(labelText: 'نوع الحدث', isDense: true),
                  items: LogRepository.unifiedEventTypeLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _eventType = v ?? 'ALL');
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _username,
                  decoration: const InputDecoration(labelText: 'المستخدم', isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('الكل')),
                    ..._users.map((u) => DropdownMenuItem(value: u.username, child: Text(u.username))),
                  ],
                  onChanged: (v) {
                    setState(() => _username = v);
                    _load();
                  },
                ),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && _entries.isEmpty)
          const Expanded(
            child: Center(
              child: Text('لا توجد أحداث مطابقة', style: TextStyle(color: AppColors.textMuted)),
            ),
          ),
        if (!_loading && _entries.isNotEmpty)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final type = entry['type'] as String? ?? '';
                final label = LogRepository.unifiedEventTypeLabels[type] ?? type;
                return Card(
                  child: ListTile(
                    leading: Icon(_typeIcon(type), color: AppColors.primary),
                    title: Text(
                      '$label${entry['username'] != null ? ' — ${entry['username']}' : ''}',
                      textAlign: TextAlign.right,
                    ),
                    subtitle: Text(
                      [
                        if (entry['details'] != null && entry['details'].toString().isNotEmpty)
                          entry['details'].toString(),
                        if (entry['item_id'] != null) 'قطعة #${entry['item_id']}',
                        if (entry['timestamp'] != null) entry['timestamp'].toString(),
                      ].join('  •  '),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11),
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