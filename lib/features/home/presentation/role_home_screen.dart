import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/app_user.dart';
import '../../../core/widgets/asj_logo.dart';
import '../../../core/widgets/locked_feature_placeholder.dart';
import '../../../core/repositories/user_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../worker/presentation/worker_home_screen.dart';
import '../../stickers/presentation/stickers_screen.dart';
import '../../engineer/presentation/engineer_home_screen.dart';
import '../../item_timeline/presentation/item_timeline_screen.dart';
import '../../inventory_summary/presentation/inventory_summary_screen.dart';
import '../../analytics/presentation/analytics_screen.dart';
import '../../activity_log/presentation/activity_log_screen.dart';
import '../../export/presentation/export_screen.dart';
import '../../admin/presentation/admin_home_screen.dart';
import '../../knowledge_import/presentation/knowledge_import_screen.dart';
import '../../settings/presentation/admin_settings_screen.dart';
import '../../user_activity/presentation/user_activity_screen.dart';
import '../../account/presentation/my_account_screen.dart';
import '../../advanced_search/presentation/advanced_search_screen.dart';
import '../../approvals/presentation/approvals_screen.dart';

/// وصف تبويب واحد في التنقّل الموحّد. لازم id ثابت مميّز (يُستخدم في
/// user_tab_overrides). إما مربوط بدور أدنى مطلوب (requiredRole) وإما
/// بصلاحية فردية (permission) — وفوق الاتنين، تخصيص فردي لكل حساب
/// (override) بيغلب أي افتراضي.
class _NavTab {
  final String id;
  final String label;
  final IconData icon;
  final Widget Function() builder;
  final UserRole? requiredRole;
  final bool Function(AppUser? user)? permission;

  const _NavTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
    this.requiredRole,
    this.permission,
  });

  bool isUnlocked(AppUser? user, Map<String, bool> overrides) {
    if (user == null) return false;
    if (overrides.containsKey(id)) return overrides[id]!;
    if (user.role == UserRole.admin) return true; // الأدمن مفتوح له كل حاجة دايماً
    if (requiredRole != null) return _roleLevel(user.role) >= _roleLevel(requiredRole!);
    if (permission != null) return permission!(user);
    return true;
  }

  static int _roleLevel(UserRole role) {
    switch (role) {
      case UserRole.worker:
        return 1;
      case UserRole.engineer:
        return 2;
      case UserRole.admin:
        return 3;
    }
  }
}

/// نقطة الدخول الوحيدة بعد تسجيل الدخول. تنقّل موحّد لكل الأدوار: كل
/// التبويبات ظاهرة لأي مستخدم بنفس الشكل بالظبط، والأدمن ممكن يخصّص
/// أي تبويب لأي حساب فوق الافتراضي حسب الدور (راجع UsersTab).
class RoleHomeScreen extends ConsumerStatefulWidget {
  const RoleHomeScreen({super.key});

  @override
  ConsumerState<RoleHomeScreen> createState() => _RoleHomeScreenState();
}

class _RoleHomeScreenState extends ConsumerState<RoleHomeScreen>
    with SingleTickerProviderStateMixin {
  late final List<_NavTab> _tabs = [
    // -- تبويبات العامل --
    _NavTab(
      id: 'entry',
      label: 'تسجيل قطعة',
      icon: Icons.add_box_outlined,
      requiredRole: UserRole.worker,
      builder: () => const WorkerBody(),
    ),
    _NavTab(
      id: 'stickers',
      label: 'الاستيكرات',
      icon: Icons.sell_outlined,
      requiredRole: UserRole.worker,
      builder: () => const StickersScreen(),
    ),
    // -- تبويبات المهندس --
    _NavTab(
      id: 'search',
      label: 'بحث وصرف',
      icon: Icons.search,
      requiredRole: UserRole.engineer,
      builder: () => const SmartSearchTab(),
    ),
    _NavTab(
      id: 'edit_dashboard',
      label: 'لوحة التعديل',
      icon: Icons.edit_note,
      permission: (u) => u?.canEdit ?? false,
      builder: () => const EditDashboardTab(),
    ),
    _NavTab(
      id: 'item_timeline',
      label: 'تتبع قطعة',
      icon: Icons.timeline_outlined,
      permission: (u) => u?.canTrack ?? false,
      builder: () => const ItemTimelineScreen(),
    ),
    _NavTab(
      id: 'activity_log',
      label: 'سجل النشاط',
      icon: Icons.receipt_long_outlined,
      permission: (u) => u?.canTrack ?? false,
      builder: () => const ActivityLogScreen(),
    ),
    _NavTab(
      id: 'inventory_summary',
      label: 'المخزون',
      icon: Icons.inventory_2_outlined,
      permission: (u) => u?.canExport ?? false,
      builder: () => const InventorySummaryScreen(),
    ),
    _NavTab(
      id: 'analytics',
      label: 'تحليل البيانات',
      icon: Icons.bar_chart_outlined,
      permission: (u) => u?.canExport ?? false,
      builder: () => const AnalyticsScreen(),
    ),
    _NavTab(
      id: 'export',
      label: 'التصدير',
      icon: Icons.ios_share,
      permission: (u) => u?.canExport ?? false,
      builder: () => const ExportScreen(),
    ),
    // -- تبويبات الأدمن --
    _NavTab(
      id: 'users',
      label: 'المستخدمون',
      icon: Icons.people_outline,
      requiredRole: UserRole.admin,
      builder: () => const UsersTab(),
    ),
    _NavTab(
      id: 'notifications',
      label: 'الإشعارات',
      icon: Icons.notifications_outlined,
      requiredRole: UserRole.admin,
      builder: () => const NotificationsTab(),
    ),
    _NavTab(
      id: 'approvals',
      label: 'الموافقات',
      icon: Icons.pending_actions,
      requiredRole: UserRole.admin,
      builder: () => const ApprovalsScreen(),
    ),
    _NavTab(
      id: 'user_activity',
      label: 'تتبع مستخدم',
      icon: Icons.person_search_outlined,
      requiredRole: UserRole.admin,
      builder: () => const UserActivityScreen(),
    ),
    _NavTab(
      id: 'kb_import',
      label: 'استيراد قاعدة المعرفة',
      icon: Icons.upload_file_outlined,
      requiredRole: UserRole.admin,
      builder: () => const KnowledgeImportScreen(),
    ),
    _NavTab(
      id: 'advanced_search',
      label: 'بحث متقدم',
      icon: Icons.manage_search,
      requiredRole: UserRole.admin,
      builder: () => const AdvancedSearchScreen(),
    ),
    _NavTab(
      id: 'settings',
      label: 'الإعدادات',
      icon: Icons.settings_outlined,
      requiredRole: UserRole.admin,
      builder: () => const AdminSettingsScreen(),
    ),
    // -- تبويب شخصي، متاح لأي حد --
    _NavTab(
      id: 'my_account',
      label: 'حسابي',
      icon: Icons.account_circle_outlined,
      requiredRole: UserRole.worker,
      builder: () => const MyAccountScreen(),
    ),
  ];

  late final TabController _tabController = TabController(length: _tabs.length, vsync: this);
  final _userRepo = UserRepository();
  Map<String, bool> _overrides = {};

  @override
  void initState() {
    super.initState();
    _loadOverrides();
  }

  Future<void> _loadOverrides() async {
    final username = ref.read(authControllerProvider)?.username;
    if (username == null) return;
    final overrides = await _userRepo.getTabOverrides(username);
    if (mounted) setState(() => _overrides = overrides);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AsjLogo(size: 26),
            const SizedBox(width: 8),
            const Text('ASJ Medical Systems',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(2),
          child: Divider(height: 2, thickness: 2, color: AppColors.accent),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs
            .map((t) => t.isUnlocked(user, _overrides)
                ? t.builder()
                : const LockedFeaturePlaceholder())
            .toList(),
      ),
      // شريط تبويبات ثابت تحت، خارج منطقة السكرول تماماً — بيفضل في
      // مكانه مهما اتحرك المحتوى فوقه.
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.accent, width: 1.6)),
          ),
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              return SizedBox(
                height: 58,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _tabs.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final tab = _tabs[index];
                    final unlocked = tab.isUnlocked(user, _overrides);
                    final selected = _tabController.index == index;
                    return _TabPill(
                      label: tab.label,
                      icon: unlocked ? tab.icon : Icons.lock_outline,
                      selected: selected,
                      onTap: () => _tabController.animateTo(index),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// زرار تبويب: أبيض بحدود فيروزي وكتابة كحلي وهو مش محدد، وكحلي ممتلئ
/// بكتابة بيضا وهو محدد — بالظبط زي المتفق عليه في الموك أب.
class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.accent,
            width: 1.4,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: selected ? Colors.white : AppColors.primary),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}