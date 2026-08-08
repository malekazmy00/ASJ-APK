import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/transaction_log.dart';
import '../../../core/models/user_session.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/log_repository.dart';
import '../../../core/repositories/user_session_repository.dart';
import '../../../core/theme/app_theme.dart';

/// تتبع المستخدم: تكتب اسم المستخدم، تجيب كل جلسات دخوله (وقت الدخول،
/// المدة) وكل أعماله (transactions_log) مجمّعة يومياً، بالإضافة لملخص
/// سريع (النهاردة/الأسبوع ده).
class UserActivityScreen extends StatefulWidget {
  const UserActivityScreen({super.key});

  @override
  State<UserActivityScreen> createState() => _UserActivityScreenState();
}

class _UserActivityScreenState extends State<UserActivityScreen> {
  final _sessionRepo = UserSessionRepository();
  final _logRepo = LogRepository();
  final _controller = TextEditingController();

  List<UserSession> _sessions = [];
  List<TransactionLog> _logs = [];
  bool _loading = false;
  bool _searched = false;

  Future<void> _search() async {
    final username = _controller.text.trim();
    if (username.isEmpty) return;
    setState(() {
      _loading = true;
      _searched = true;
    });
    final results = await Future.wait([
      _sessionRepo.getByUsername(username),
      _logRepo.getByUser(username),
    ]);
    if (mounted) {
      setState(() {
        _sessions = results[0] as List<UserSession>;
        _logs = results[1] as List<TransactionLog>;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ({int count, Duration total}) _summarize(DateTime since) {
    final relevant = _sessions.where((s) => s.loginAt != null && s.loginAt!.isAfter(since));
    var total = Duration.zero;
    for (final s in relevant) {
      total += s.duration ?? Duration.zero;
    }
    return (count: relevant.length, total: total);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h س $m د';
    return '$m د';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = now.subtract(const Duration(days: 7));
    final todaySummary = _searched ? _summarize(todayStart) : null;
    final weekSummary = _searched ? _summarize(weekStart) : null;

    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      hintText: 'اسم المستخدم',
                      prefixIcon: Icon(Icons.person_search_outlined),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _search,
                  child: const Text('بحث'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_searched && !_loading) ...[
              if (todaySummary != null && weekSummary != null)
                Row(
                  children: [
                    Expanded(
                      child: _SummaryChip(
                        label: 'النهاردة',
                        value: '${todaySummary.count} جلسة — ${_formatDuration(todaySummary.total)}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryChip(
                        label: 'آخر ٧ أيام',
                        value: _formatDuration(weekSummary.total),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              const TabBar(
                labelColor: AppColors.primary,
                tabs: [
                  Tab(text: 'الجلسات'),
                  Tab(text: 'الأعمال'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _SessionsList(sessions: _sessions),
                    _DayGroupedLogs(logs: _logs),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.primary)),
        ],
      ),
    );
  }
}

class _SessionsList extends StatelessWidget {
  const _SessionsList({required this.sessions});
  final List<UserSession> sessions;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const Center(child: Text('لا توجد جلسات مسجّلة'));
    }
    final formatter = DateFormat('yyyy-MM-dd  HH:mm');
    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final s = sessions[index];
        final isOpen = s.logoutAt == null;
        return Card(
          child: ListTile(
            leading: Icon(
              isOpen ? Icons.circle : Icons.check_circle_outline,
              color: isOpen ? AppColors.success : Colors.grey,
              size: 16,
            ),
            title: Text(
              s.loginAt != null ? formatter.format(s.loginAt!) : '—',
              textAlign: TextAlign.right,
            ),
            subtitle: Text(
              [
                isOpen ? 'مفتوحة حالياً' : 'مقفولة',
                if (s.duration != null) 'المدة: ${_formatDuration(s.duration!)}',
                if (s.deviceInfo != null && s.deviceInfo!.isNotEmpty) s.deviceInfo!,
              ].join('  •  '),
              textAlign: TextAlign.right,
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h س $m د';
    return '$m د';
  }
}

/// سجل الأعمال مقسّم بعناوين يومية (النهاردة/أمس/تاريخ)، بدل قائمة
/// واحدة مسطّحة — يسهّل معرفة "الشخص ده عمل إيه النهاردة/إمبارح".
class _DayGroupedLogs extends StatelessWidget {
  const _DayGroupedLogs({required this.logs});
  final List<TransactionLog> logs;

  String _dayLabel(DateTime date, DateTime today) {
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'النهاردة';
    if (diff == 1) return 'إمبارح';
    return DateFormat('yyyy-MM-dd').format(d);
  }

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(child: Text('لا توجد أعمال مسجّلة لهذا المستخدم'));
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final Map<String, List<TransactionLog>> grouped = {};
    for (final log in logs) {
      if (log.timestamp == null) continue;
      final label = _dayLabel(log.timestamp!, today);
      grouped.putIfAbsent(label, () => []).add(log);
    }

    return ListView(
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                entry.key,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 13),
              ),
            ),
            ...entry.value.map((log) => Card(
                  child: ListTile(
                    title: Text(log.actionType.arabicLabel, textAlign: TextAlign.right),
                    subtitle: Text(
                      [
                        if (log.details != null && log.details!.isNotEmpty) log.details!,
                        if (log.itemId != null) 'قطعة #${log.itemId}',
                        if (log.timestamp != null) DateFormat('HH:mm').format(log.timestamp!),
                      ].join('  •  '),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                )),
          ],
        );
      }).toList(),
    );
  }
}