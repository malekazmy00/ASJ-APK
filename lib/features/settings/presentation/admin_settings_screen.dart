import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/repositories/notification_repository.dart';
import '../../auth/presentation/auth_providers.dart';

/// إعدادات الأدمن: تغيير كلمة المرور الشخصية + فحص حالة الاتصال بـ
/// Gemini + تشغيل/إيقاف كل نوع إشعار لوحده.
class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _changingPassword = false;

  bool? _geminiOk; // null = لسه ماتفحصش
  bool _checkingGemini = false;

  final _notificationRepo = NotificationRepository();
  Map<String, bool> _notifSettings = {};
  bool _loadingNotifSettings = true;

  static const _notifTypeLabels = {
    'new_query': 'استعلام جديد',
    'part_number_edit': 'تعديل رقم قطعة',
    'serial_edit': 'تعديل رقم تسلسلي',
    'kb_import': 'استيراد قاعدة معرفة',
  };

  @override
  void initState() {
    super.initState();
    _loadNotifSettings();
  }

  Future<void> _loadNotifSettings() async {
    setState(() => _loadingNotifSettings = true);
    final settings = await _notificationRepo.getAllSettings();
    if (mounted) {
      setState(() {
        _notifSettings = {
          for (final type in _notifTypeLabels.keys) type: settings[type] ?? true,
        };
        _loadingNotifSettings = false;
      });
    }
  }

  Future<void> _toggleNotifType(String type, bool value) async {
    setState(() => _notifSettings[type] = value);
    await _notificationRepo.setTypeEnabled(type, value);
  }

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
    if (username == null) return;

    setState(() => _changingPassword = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'change-password',
        body: {
          'username': username,
          'oldPassword': _oldPasswordController.text,
          'newPassword': _newPasswordController.text,
        },
      );
      final data = response.data as Map<String, dynamic>?;
      if (data?['success'] == true) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        _showSnack('تم تغيير كلمة المرور بنجاح');
      } else {
        _showSnack(data?['error']?.toString() ?? 'فشل التغيير', isError: true);
      }
    } catch (e) {
      _showSnack('خطأ في الاتصال بالخادم', isError: true);
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _checkGeminiStatus() async {
    setState(() {
      _checkingGemini = true;
      _geminiOk = null;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke('gemini-status');
      final data = response.data as Map<String, dynamic>?;
      setState(() => _geminiOk = data?['success'] == true);
    } catch (e) {
      setState(() => _geminiOk = false);
    } finally {
      if (mounted) setState(() => _checkingGemini = false);
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'حالة الاتصال بـ Gemini',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_geminiOk != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: (_geminiOk! ? AppColors.success : AppColors.danger).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _geminiOk! ? AppColors.success : AppColors.danger),
                  ),
                  child: Row(
                    children: [
                      Icon(_geminiOk! ? Icons.check_circle_outline : Icons.error_outline,
                          color: _geminiOk! ? AppColors.success : AppColors.danger, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _geminiOk! ? 'متصل ويعمل بشكل طبيعي' : 'تعذر الاتصال بـ Gemini',
                        style: TextStyle(
                          color: _geminiOk! ? AppColors.success : AppColors.danger,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _checkingGemini ? null : _checkGeminiStatus,
                icon: _checkingGemini
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label: Text(_checkingGemini ? 'جارٍ الفحص...' : 'فحص الاتصال الآن'),
              ),
            ],
          ),
        ),
        _SectionCard(
          title: 'الإشعارات',
          child: _loadingNotifSettings
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _notifTypeLabels.entries.map((entry) {
                    return SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _notifSettings[entry.key] ?? true,
                      onChanged: (v) => _toggleNotifType(entry.key, v),
                      title: Text(entry.value, textAlign: TextAlign.right),
                    );
                  }).toList(),
                ),
        ),
        _SectionCard(
          title: 'تغيير كلمة المرور',
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  onPressed: _changingPassword ? null : _changePassword,
                  child: _changingPassword
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('تغيير كلمة المرور'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.primary)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}