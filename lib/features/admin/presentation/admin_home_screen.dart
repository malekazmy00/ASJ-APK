
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/notification.dart';
import '../../../core/repositories/user_repository.dart';
import '../../../core/repositories/notification_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../inventory_summary/presentation/inventory_summary_screen.dart';
import '../../item_timeline/presentation/item_timeline_screen.dart';
import '../../user_activity/presentation/user_activity_screen.dart';

/// لوحة الأدمن: 5 تبويبات — المستخدمون (صلاحيات + إضافة)، الإشعارات،
/// الداشبورد التجميعي (المرحلة 3)، تتبع قطعة عبر الزمن (المرحلة 3)،
/// تتبع جلسات/أعمال مستخدم (المرحلة 3). ناقص لسه: استيراد قاعدة
/// المعرفة CSV والإحصائيات (راجع PROJECT_PLAN.md §7.1).
class AdminHomeScreen extends ConsumerStatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  ConsumerState<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends ConsumerState<AdminHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الأدمن'),
        backgroundColor: AppColors.roleAdmin,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'المستخدمون', icon: Icon(Icons.people_outline)),
            Tab(text: 'الإشعارات', icon: Icon(Icons.notifications_outlined)),
            Tab(text: 'المخزون', icon: Icon(Icons.inventory_2_outlined)),
            Tab(text: 'تتبع قطعة', icon: Icon(Icons.timeline_outlined)),
            Tab(text: 'تتبع مستخدم', icon: Icon(Icons.person_search_outlined)),
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
          _UsersTab(),
          _NotificationsTab(),
          InventorySummaryScreen(),
          ItemTimelineScreen(),
          UserActivityScreen(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _userRepo = UserRepository();
  List<AppUser> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await _userRepo.getAll();
    if (mounted) setState(() {
      _users = users;
      _loading = false;
    });
  }

  Future<void> _togglePermission(AppUser user, String permission, bool value) async {
    await _userRepo.updatePermissions(
      user.username,
      canExport: permission == 'export' ? value : null,
      canTrack: permission == 'track' ? value : null,
      canEdit: permission == 'edit' ? value : null,
    );
    _load();
  }

  Future<void> _showAddUserDialog() async {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String role = 'worker';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('مستخدم جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameCtrl,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'اسم المستخدم'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'كلمة المرور'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: const [
                  DropdownMenuItem(value: 'worker', child: Text('عامل')),
                  DropdownMenuItem(value: 'engineer', child: Text('مهندس')),
                  DropdownMenuItem(value: 'admin', child: Text('أدمن')),
                ],
                onChanged: (v) => setDialogState(() => role = v ?? role),
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
              child: const Text('إنشاء'),
            ),
          ],
        ),
      ),
    );

    if (created != true) return;

    final response = await Supabase.instance.client.functions.invoke(
      'admin-create-user',
      body: {
        'username': usernameCtrl.text.trim(),
        'password': passwordCtrl.text,
        'role': role,
      },
    );
    final data = response.data as Map<String, dynamic>?;
    if (data?['success'] == true) {
      _load();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الإنشاء: ${data?['error'] ?? ''}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddUserDialog,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('مستخدم جديد'),
        backgroundColor: AppColors.roleAdmin,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Chip(label: Text(user.role.name)),
                            const Spacer(),
                            Text(user.username,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (user.role != UserRole.admin) ...[
                          const Divider(),
                          _PermissionSwitch(
                            label: 'تصدير',
                            value: user.canExport,
                            onChanged: (v) => _togglePermission(user, 'export', v),
                          ),
                          _PermissionSwitch(
                            label: 'تتبع',
                            value: user.canTrack,
                            onChanged: (v) => _togglePermission(user, 'track', v),
                          ),
                          _PermissionSwitch(
                            label: 'تعديل',
                            value: user.canEdit,
                            onChanged: (v) => _togglePermission(user, 'edit', v),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _PermissionSwitch extends StatelessWidget {
  const _PermissionSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label),
        const Spacer(),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

// ---------------------------------------------------------------------
class _NotificationsTab extends StatefulWidget {
  const _NotificationsTab();

  @override
  State<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<_NotificationsTab> {
  final _repo = NotificationRepository();
  List<AppNotification> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _repo.getRecent();
    if (mounted) setState(() {
      _notifications = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  await _repo.markAllRead();
                  _load();
                },
                icon: const Icon(Icons.done_all),
                label: const Text('تعليم الكل كمقروء'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await _repo.clearAll();
                  _load();
                },
                icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.danger),
                label: const Text('مسح الكل', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: _notifications.length,
            itemBuilder: (context, index) {
              final n = _notifications[index];
              return ListTile(
                leading: Icon(
                  n.isRead ? Icons.notifications_none : Icons.notifications_active,
                  color: n.isRead ? Colors.grey : AppColors.roleAdmin,
                ),
                title: Text(n.message, textAlign: TextAlign.right),
                subtitle: n.timestamp != null
                    ? Text(n.timestamp.toString(), textAlign: TextAlign.right)
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
