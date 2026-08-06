import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/transaction_log.dart';
import '../../../core/repositories/log_repository.dart';

enum _Period { today, week, month, all }

/// سجل نشاط عام زمني — كل الحركات مرتبة بالوقت، بفلتر فترة، من غير
/// ما تكون مربوطة بقطعة معينة (تتبع قطعة) أو مستخدم معين (تتبع مستخدم).
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _repo = LogRepository();
  _Period _period = _Period.week;
  bool _loading = true;
  List<TransactionLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    DateTime? since;
    final now = DateTime.now();
    switch (_period) {
      case _Period.today:
        since = DateTime(now.year, now.month, now.day);
        break;
      case _Period.week:
        since = now.subtract(const Duration(days: 7));
        break;
      case _Period.month:
        since = now.subtract(const Duration(days: 30));
        break;
      case _Period.all:
        since = null;
        break;
    }
    final logs = await _repo.getRecent(since: since);
    if (mounted) setState(() {
      _logs = logs;
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

  IconData _actionIcon(ActionType t) {
    switch (t) {
      case ActionType.insert:
        return Icons.add_box_outlined;
      case ActionType.update:
        return Icons.edit_note;
      case ActionType.delete:
        return Icons.delete_outline;
      case ActionType.out:
        return Icons.outbox_outlined;
      case ActionType.search:
        return Icons.search;
      case ActionType.login:
        return Icons.login;
      case ActionType.logout:
        return Icons.logout;
      case ActionType.export_:
        return Icons.ios_share;
      case ActionType.import_:
        return Icons.upload_file_outlined;
      case ActionType.userMgmt:
        return Icons.admin_panel_settings_outlined;
      case ActionType.dbRestore:
        return Icons.restore;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
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
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && _logs.isEmpty)
          const Expanded(
            child: Center(
              child: Text('لا توجد حركات في هذه الفترة', style: TextStyle(color: AppColors.textMuted)),
            ),
          ),
        if (!_loading && _logs.isNotEmpty)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                return Card(
                  child: ListTile(
                    leading: Icon(_actionIcon(log.actionType), color: AppColors.primary),
                    title: Text(
                      '${log.actionType.arabicLabel}${log.username != null ? ' — ${log.username}' : ''}',
                      textAlign: TextAlign.right,
                    ),
                    subtitle: Text(
                      [
                        if (log.details != null && log.details!.isNotEmpty) log.details!,
                        if (log.itemId != null) 'قطعة #${log.itemId}',
                        if (log.timestamp != null) log.timestamp.toString(),
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