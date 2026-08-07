import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/app_user.dart';
import '../../../core/widgets/asj_logo.dart';
import '../../../core/widgets/locked_feature_placeholder.dart';
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

/// وصف تبويب واحد في التنقّل الموحّد. إما مربوط بدور أدنى مطلوب
/// (requiredRole) وإما بصلاحية فردية يمنحها الأدمن (permission).
class _NavTab {
  final String label;
  final IconData icon;
  final Widget Function() builder;
  final UserRole? requiredRole;
  final bool Function(AppUser? user)? permission;

  const _NavTab({
    required this.label,
    required this.icon,
    required this.builder,
    this.requiredRole,
    this.permission,
  });

  bool isUnlocked(AppUser? user) {
    if (user == null) return false;
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
/// التبويبات ظاهرة لأي مستخدم بنفس الشكل بالظبط — دور المهندس بيشوف
/// تبويبات الأدمن (مقفولة)، والعامل بيشوف تبويبات المهندس والأدمن
/// (مقفولة)، وهكذا. الترتيب طبيعي: تبويبات العامل، بعدين المهندس،
/// بعدين الأدمن.
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
      label: 'تسجيل قطعة',
      icon: Icons.add_box_outlined,
      requiredRole: UserRole.worker,
      builder: () => const WorkerBody(),
    ),
    _NavTab(
      label: 'الاستيكرات',
      icon: Icons.sell_outlined,
      requiredRole: UserRole.worker,
      builder: () => const StickersScreen(),
    ),
    // -- تبويبات المهندس --
    _NavTab(
      label: 'بحث وصرف',
      icon: Icons.search,
      requiredRole: UserRole.engineer,
      builder: () => const SmartSearchTab(),
    ),
    _NavTab(
      label: 'لوحة التعديل',
      icon: Icons.edit_note,
      permission: (u) => u?.canEdit ?? false,
      builder: () => const EditDashboardTab(),
    ),
    _NavTab(
      label: 'تتبع قطعة',
      icon: Icons.timeline_outlined,
      permission: (u) => u?.canTrack ?? false,
      builder: () => const ItemTimelineScreen(),
    ),
    _NavTab(
      label: 'سجل النشاط',
      icon: Icons.receipt_long_outlined,
      permission: (u) => u?.canTrack ?? false,
      builder: () => const ActivityLogScreen(),
    ),
    _NavTab(
      label: 'المخزون',
      icon: Icons.inventory_2_outlined,
      permission: (u) => u?.canExport ?? false,
      builder: () => const InventorySummaryScreen(),
    ),
    _NavTab(
      label: 'تحليل البيانات',
      icon: Icons.bar_chart_outlined,
      permission: (u) => u?.canExport ?? false,
      builder: () => const AnalyticsScreen(),
    ),
    _NavTab(
      label: 'التصدير',
      icon: Icons.ios_share,
      permission: (u) => u?.canExport ?? false,
      builder: () => const ExportScreen(),
    ),
    // -- تبويبات الأدمن --
    _NavTab(
      label: 'المستخدمون',
      icon: Icons.people_outline,
      requiredRole: UserRole.admin,
      builder: () => const UsersTab(),
    ),
    _NavTab(
      label: 'الإشعارات',
      icon: Icons.notifications_outlined,
      requiredRole: UserRole.admin,
      builder: () => const NotificationsTab(),
    ),
    _NavTab(
      label: 'تتبع مستخدم',
      icon: Icons.person_search_outlined,
      requiredRole: UserRole.admin,
      builder: () => const UserActivityScreen(),
    ),
    _NavTab(
      label: 'استيراد قاعدة المعرفة',
      icon: Icons.upload_file_outlined,
      requiredRole: UserRole.admin,
      builder: () => const KnowledgeImportScreen(),
    ),
    _NavTab(
      label: 'الإعدادات',
      icon: Icons.settings_outlined,
      requiredRole: UserRole.admin,
      builder: () => const AdminSettingsScreen(),
    ),
  ];

  late final TabController _tabController = TabController(length: _tabs.length, vsync: this);

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
      appBar: AppBar(
        title: const Text('ASJ Medical Systems'),
        backgroundColor: AppColors.primary,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11.5),
          isScrollable: true,
          tabs: _tabs
              .map((t) => Tab(
                    icon: Icon(t.isUnlocked(user) ? t.icon : Icons.lock_outline),
                    text: t.label,
                  ))
              .toList(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabs
                  .map((t) => t.isUnlocked(user) ? t.builder() : const LockedFeaturePlaceholder())
                  .toList(),
            ),
          ),
          // علامة اللوجو المائية الثابتة أسفل كل شاشة، على الخلفية الفاتحة
          Container(
            width: double.infinity,
            color: AppColors.background,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Opacity(opacity: 0.14, child: AsjLogo(size: 30)),
            ),
          ),
        ],
      ),
    );
  }
}