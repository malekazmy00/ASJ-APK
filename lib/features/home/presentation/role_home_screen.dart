import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../worker/presentation/worker_home_screen.dart';
import '../../engineer/presentation/engineer_home_screen.dart';
import '../../admin/presentation/admin_home_screen.dart';

/// نقطة دخول واحدة بعد تسجيل الدخول، توجّه المستخدم لواجهة دوره مباشرة.
class RoleHomeScreen extends ConsumerWidget {
  const RoleHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    if (user == null) return const SizedBox.shrink();

    switch (user.role) {
      case UserRole.worker:
        return const WorkerHomeScreen();
      case UserRole.engineer:
        return const EngineerHomeScreen();
      case UserRole.admin:
        return const AdminHomeScreen();
    }
  }
}
