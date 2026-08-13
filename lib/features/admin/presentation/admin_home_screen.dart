import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/notification.dart';
import '../../../core/repositories/user_repository.dart';
import '../../../core/repositories/notification_repository.dart';
import '../../../core/repositories/field_permissions_repository.dart';
import '../../../core/constants/nav_tabs.dart';
import '../../auth/presentation/auth_providers.dart';

// ---------------------------------------------------------------------
class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  final _userRepo = UserRepository();
  final _notifRepo = NotificationRepository();
  final _fieldRepo = FieldPermissionsRepository();
  List<AppUser> _users = [];
  bool _loading = true;
  // TASK-324: الحفظ الفعلي (admin-create-user/admin-reset-password)
  // بيحصل بعد ما الـ Dialog نفسه يتقفل، مش جواه — فمينفعش نمنع
  // الـ double-tap بتعطيل زرار جوه Dialog قفل خلاص. الحل هنا: نمنع
  // فتح Dialog تاني (إنشاء أو تعديل) لحد ما الطلب اللي قبله يخلص.
  bool _submitting = false;

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
    final adminUsername = ref.read(authControllerProvider)?.username ?? 'unknown';
    await _notifRepo.create(
      notifType: NotificationEventType.permissionsChanged.dbValue,
      message: '$adminUsername عدّل صلاحية "$permission" لحساب ${user.username}',
    );
    _load();
  }

  Future<void> _showAddUserDialog() async {
    if (_submitting) return;
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
    setState(() => _submitting = true);

    final adminToken = ref.read(authControllerProvider.notifier).token;
    final response = await Supabase.instance.client.functions.invoke(
      'admin-create-user',
      body: {
        'username': usernameCtrl.text.trim(),
        'password': passwordCtrl.text,
        'role': role,
      },
      headers: adminToken != null ? {'x-app-token': adminToken} : null,
    );
    final data = response.data as Map<String, dynamic>?;
    if (data?['success'] == true) {
      await _notifRepo.create(
        notifType: NotificationEventType.userCreated.dbValue,
        message: '${ref.read(authControllerProvider)?.username ?? 'أدمن'} '
            'أنشأ حساب جديد: ${usernameCtrl.text.trim()} ($role)',
      );
      _load();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الإنشاء: ${data?['error'] ?? ''}')),
      );
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _showEditUserDialog(AppUser user) async {
    if (_submitting) return;
    String role = user.role.name;
    String status = user.status;
    final newPasswordCtrl = TextEditingController();
    final overrides = Map<String, bool>.from(await _userRepo.getTabOverrides(user.username));
    // null = افتراضي حسب الدور، true = إظهار دائماً، false = إخفاء دائماً
    final Map<String, bool?> tabChoices = {
      for (final tab in allNavTabs) tab.$1: overrides[tab.$1],
    };
    // ملحوظة (الجولة الثالثة، نقطة ٧ — إصلاح باج): ExpansionTile كان
    // بيحرّك السهم بس القايمة مابتظهرش، لأن الأنيميشن بتاعه مستقل عن
    // setDialogState بتاعة الـ Dialog. استبدلناه بـ bool بسيط متحكم
    // فيه من نفس setDialogState، فمفيش تعارض في دورة الـ rebuild.
    bool tabsExpanded = false;

    // الجولة الثالثة (نقطة ٢٧) — التحكم في العناصر الداخلية جوه ٥
    // تبويبات بس. بنحمّل كل التخصيصات المحفوظة لكل التبويبات الخمسة
    // مرة واحدة، ونعمل نسخة منفصلة (originalFieldOverrides) نقارن
    // بيها وقت الحفظ عشان نكتب بس اللي اتغيّر فعلاً.
    final loadedFieldOverrides = await _fieldRepo.getAllOverridesForUser(user.username);
    final originalFieldOverrides = <String, Map<String, bool>>{
      for (final entry in loadedFieldOverrides.entries) entry.key: Map.of(entry.value),
    };
    final fieldChoices = <String, Map<String, bool>>{
      for (final entry in loadedFieldOverrides.entries) entry.key: Map.of(entry.value),
    };
    bool fieldsExpanded = false;
    String selectedFieldTab = FieldPermissionsRepository.controllableTabLabels.keys.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(user.username),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'الحالة'),
                    items: const [
                      DropdownMenuItem(value: 'Active', child: Text('مفعّل')),
                      DropdownMenuItem(value: 'Inactive', child: Text('موقوف')),
                    ],
                    onChanged: (v) => setDialogState(() => status = v ?? status),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newPasswordCtrl,
                    obscureText: true,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'كلمة مرور جديدة (سيبها فاضية لو مش هتغيّرها)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => setDialogState(() => tabsExpanded = !tabsExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Icon(tabsExpanded ? Icons.expand_less : Icons.expand_more),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('صلاحيات التبويبات (تخصيص فردي)',
                                textAlign: TextAlign.right),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (tabsExpanded)
                    ...allNavTabs.map((tab) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButton<bool?>(
                                isExpanded: true,
                                value: tabChoices[tab.$1],
                                items: const [
                                  DropdownMenuItem(value: null, child: Text('افتراضي حسب الدور')),
                                  DropdownMenuItem(value: true, child: Text('إظهار دائماً')),
                                  DropdownMenuItem(value: false, child: Text('إخفاء دائماً')),
                                ],
                                onChanged: (v) => setDialogState(() => tabChoices[tab.$1] = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(tab.$2, textAlign: TextAlign.right),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => setDialogState(() => fieldsExpanded = !fieldsExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Icon(fieldsExpanded ? Icons.expand_less : Icons.expand_more),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('التحكم في العناصر الداخلية (تخصيص فردي)',
                                textAlign: TextAlign.right),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // الجولة الثالثة (نقطة ٢٧): تختار تبويب من الخمسة
                  // القابلة للتحكم، وتظهرلك قايمة عناصره — كل عنصر
                  // Checkbox مستقل (ظاهر/مخفي) لنفس الحساب ده بس.
                  if (fieldsExpanded) ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedFieldTab,
                      decoration: const InputDecoration(labelText: 'التبويب'),
                      items: FieldPermissionsRepository.controllableTabLabels.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedFieldTab = v ?? selectedFieldTab),
                    ),
                    const SizedBox(height: 4),
                    ...FieldPermissionsRepository.tabFields[selectedFieldTab]!
                        .entries
                        .map((fieldEntry) {
                      final tabMap = fieldChoices.putIfAbsent(selectedFieldTab, () => {});
                      final visible = tabMap[fieldEntry.key] ?? true;
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: visible,
                        title: Text(fieldEntry.value, textAlign: TextAlign.right),
                        onChanged: (v) =>
                            setDialogState(() => tabMap[fieldEntry.key] = v ?? true),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    setState(() => _submitting = true);

    if (role != user.role.name) {
      await _userRepo.updateRole(user.username, role);
    }
    if (status != user.status) {
      await _userRepo.updateStatus(user.username, status);
    }
    if (newPasswordCtrl.text.trim().isNotEmpty) {
      final adminToken = ref.read(authControllerProvider.notifier).token;
      final response = await Supabase.instance.client.functions.invoke(
        'admin-reset-password',
        body: {'username': user.username, 'newPassword': newPasswordCtrl.text.trim()},
        headers: adminToken != null ? {'x-app-token': adminToken} : null,
      );
      final data = response.data as Map<String, dynamic>?;
      if (data?['success'] == true) {
        await _notifRepo.create(
          notifType: NotificationEventType.adminPasswordReset.dbValue,
          message: '${ref.read(authControllerProvider)?.username ?? 'أدمن'} '
              'أعاد تعيين كلمة مرور ${user.username}',
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تغيير كلمة المرور: ${data?['error'] ?? ''}')),
        );
      }
    }

    final adminUsername = ref.read(authControllerProvider)?.username ?? 'unknown';
    bool tabOverridesChanged = false;
    for (final tab in allNavTabs) {
      final newChoice = tabChoices[tab.$1];
      final oldChoice = overrides[tab.$1];
      if (newChoice == oldChoice) continue;
      tabOverridesChanged = true;
      if (newChoice == null) {
        await _userRepo.clearTabOverride(user.username, tab.$1);
      } else {
        await _userRepo.setTabOverride(user.username, tab.$1, newChoice, updatedBy: adminUsername);
      }
    }
    if (tabOverridesChanged) {
      await _notifRepo.create(
        notifType: NotificationEventType.permissionsChanged.dbValue,
        message: '$adminUsername عدّل صلاحيات التبويبات لحساب ${user.username}',
      );
    }

    // الجولة الثالثة (نقطة ٢٧): نكتب بس العناصر اللي اتغيّرت فعلاً عن
    // القيمة الأصلية اللي اتحمّلت وقت فتح الـ Dialog.
    bool fieldOverridesChanged = false;
    for (final tabId in FieldPermissionsRepository.tabFields.keys) {
      final original = originalFieldOverrides[tabId] ?? {};
      final current = fieldChoices[tabId] ?? {};
      for (final fieldKey in FieldPermissionsRepository.tabFields[tabId]!.keys) {
        final originalVisible = original[fieldKey] ?? true;
        final currentVisible = current[fieldKey] ?? true;
        if (originalVisible != currentVisible) {
          fieldOverridesChanged = true;
          await _fieldRepo.setOverride(
            username: user.username,
            tabId: tabId,
            fieldKey: fieldKey,
            visible: currentVisible,
            updatedBy: adminUsername,
          );
        }
      }
    }
    if (fieldOverridesChanged) {
      await _notifRepo.create(
        notifType: NotificationEventType.permissionsChanged.dbValue,
        message: '$adminUsername عدّل العناصر الداخلية الظاهرة لحساب ${user.username}',
      );
    }

    _load();
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _submitting ? null : _showAddUserDialog,
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
                  child: InkWell(
                    onTap: _submitting ? null : () => _showEditUserDialog(user),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Chip(label: Text(user.role.name)),
                              if (user.status != 'Active') ...[
                                const SizedBox(width: 6),
                                const Chip(
                                  label: Text('موقوف', style: TextStyle(fontSize: 10.5)),
                                  backgroundColor: Color(0xFFFDECEC),
                                ),
                              ],
                              const Spacer(),
                              Text(user.username,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              const Icon(Icons.edit_outlined, size: 16, color: AppColors.textMuted),
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
class NotificationsTab extends StatefulWidget {
  const NotificationsTab({super.key});

  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
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