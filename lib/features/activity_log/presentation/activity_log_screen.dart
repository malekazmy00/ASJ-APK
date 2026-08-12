import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/app_user.dart';
import '../../../core/repositories/log_repository.dart';
import '../../../core/repositories/user_repository.dart';

enum _Period { today, week, month, all }

/// سجل نشاط عام موحّد (الجولة الثالثة، نقطة ١٠) — كل الحركات من كل
/// المصادر (transactions_log، استعلامات المهندسين، الجلسات، طلبات
/// الموافقة) مع بعض في قايمة واحدة مرتبة زمنياً، بفلتر فترة + نوع
/// الحدث + مستخدم، الثلاثة قابلين للدمج مع بعض.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _logRepo = LogRepository();
  final _userRepo = UserRepository();

  _Period _period = _Period.week;
  String _eventType = 'ALL';
  String? _username;

  bool _loading = true;
  List<Map<String, dynamic>> _entries = [];
  List<AppUser> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _load();
  }

  Future<void> _loadUsers() async {
    final users = await _userRepo.getAll();
    if (mounted) setState(() => _users = users);
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
    final entries = await _logRepo.getUnified(
      eventType: _eventType,
      since: _sinceForPeriod,
      username: _username,
    );
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
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

  /// تجميع الإدخالات حسب اليوم (النهاردة/إمبارح/تاريخ) — أسهل للقراءة
  /// من قايمة مسطحة طويلة.
  Map<String, List<Map<String, dynamic>>> get _groupedByDay {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final e in _entries) {
      final ts = DateTime.tryParse(e['timestamp']?.toString() ?? '');
      String label;
      if (ts == null) {
        label = 'غير معروف';
      } else {
        final day = DateTime(ts.year, ts.month, ts.day);
        if (day == today) {
          label = 'النهاردة';
        } else if (day == yesterday) {
          label = 'إمبارح';
        } else {
          label = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        }
      }
      grouped.putIfAbsent(label, () => []).add(e);
    }
    return grouped;
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
        return Icons.smartphone_outlined;
      case 'APPROVAL':
        return Icons.pending_actions;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedByDay;

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
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _eventType,
                  decoration: const InputDecoration(labelText: 'نوع الحدث'),
                  isExpanded: true,
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
                  decoration: const InputDecoration(labelText: 'المستخدم'),
                  isExpanded: true,
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
              child: Text('لا توجد حركات مطابقة', style: TextStyle(color: AppColors.textMuted)),
            ),
          ),
        if (!_loading && _entries.isNotEmpty)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              children: grouped.entries.expand((group) {
                return [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      group.key,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.primary),
                    ),
                  ),
                  ...group.value.map((log) {
                    final type = log['type'] as String? ?? '';
                    final typeLabel = LogRepository.unifiedEventTypeLabels[type] ?? type;
                    final username = log['username'] as String?;
                    final itemId = log['item_id'];
                    final details = log['details'] as String?;
                    final ts = DateTime.tryParse(log['timestamp']?.toString() ?? '');
                    return Card(
                      child: ListTile(
                        leading: Icon(_typeIcon(type), color: AppColors.primary),
                        title: Text(
                          '$typeLabel${username != null ? ' — $username' : ''}',
                          textAlign: TextAlign.right,
                        ),
                        subtitle: Text(
                          [
                            if (details != null && details.isNotEmpty) details,
                            if (itemId != null) 'قطعة #$itemId',
                            if (ts != null)
                              '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
                          ].join('  •  '),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    );
                  }),
                ];
              }).toList(),
            ),
          ),
      ],
    );
  }
}