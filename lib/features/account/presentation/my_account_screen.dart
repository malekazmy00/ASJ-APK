import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/notification_repository.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/error_messages.dart';
import '../../auth/presentation/auth_providers.dart';

/// "حسابي" — متاحة لأي دور (عكس شاشة إعدادات الأدمن اللي فيها نفس
/// الفكرة بس للأدمن بس). بتوري اسم المستخدم + تغيير كلمة المرور
/// الشخصية، بتستخدم نفس Edge Function change-password.
class MyAccountScreen extends ConsumerStatefulWidget {
  const MyAccountScreen({super.key});

  @override
  ConsumerState<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends ConsumerState<MyAccountScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _changing = false;
  final _notifRepo = NotificationRepository();

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showSnack('كلمة المرور الجديدة وتأكيدها مش متطابقين', isError: true);
      return;
    }
    final username = ref.read(authControllerProvider)?.username;
    final token = ref.read(authControllerProvider.notifier).token;
    if (username == null || token == null) return;

    setState(() => _changing = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'change-password',
        body: {
          'oldPassword': _oldPasswordController.text,
          'newPassword': _newPasswordController.text,
        },
        headers: {'x-app-token': token},
      );
      final data = response.data as Map<String, dynamic>?;
      if (data?['success'] == true) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        await _notifRepo.create(
          notifType: NotificationEventType.selfPasswordChange.dbValue,
          message: '$username غيّر كلمة المرور الشخصية',
        );
        if (!mounted) return;
        // TASK-309: تغيير الباسورد بيلغي صلاحية أي توكن قديم على
        // السيرفر — بما فيه توكن الجهاز الحالي نفسه. لازم تسجيل دخول
        // جديد فعلي بالباسورد الجديدة عشان ياخد توكن صالح.
        _showSnack('تم تغيير كلمة المرور — سجّل دخول تاني بالباسورد الجديدة');
        await ref.read(authControllerProvider.notifier).logout();
        return;
      } else {
        _showSnack(data?['error']?.toString() ?? 'فشل التغيير', isError: true);
      }
    } catch (e, st) {
      AppLogger.logError('MyAccountScreen._changePassword', e, st);
      _showSnack(friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.account_circle_outlined, size: 34, color: AppColors.primary),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.username ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(_roleLabel(user?.role.name), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('تغيير كلمة المرور',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppColors.primary)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _oldPasswordController,
                    obscureText: true,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(labelText: 'كلمة المرور الحالية'),
                    validator: (v) => (v == null || v.isEmpty) ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: true,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
                    validator: (v) => (v == null || v.length < 6) ? '٦ أحرف على الأقل' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور الجديدة'),
                    validator: (v) => (v == null || v.isEmpty) ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _changing ? null : _changePassword,
                    child: _changing
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('تغيير كلمة المرور'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'engineer':
        return 'مهندس';
      case 'admin':
        return 'أدمن';
      case 'worker':
      default:
        return 'عامل';
    }
  }
}