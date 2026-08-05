import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/transaction_log.dart';
import '../../../core/models/user_session.dart';
import '../../../core/repositories/log_repository.dart';
import '../../../core/repositories/user_session_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/timeline_widget.dart';

/// تتبع المستخدم: تكتب اسم المستخدم، تجيب كل جلسات دخوله (وقت الدخول،
/// المدة) وكل أعماله (transactions_log) — مش بس آخر دخول زي الوضع
/// الحالي.
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

  @override
  Widget build(BuildContext context) {
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
                    SingleChildScrollView(
                      child: TimelineWidget(
                        logs: _logs,
                        showUsername: false,
                        emptyMessage: 'لا توجد أعمال مسجّلة لهذا المستخدم',
                      ),
                    ),
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
              isOpen
                  ? 'جلسة مفتوحة حالياً'
                  : 'المدة: ${_formatDuration(s.duration)}',
              textAlign: TextAlign.right,
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '—';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h س $m د';
    return '$m د';
  }
}
