import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/notification_repository.dart';

/// إعدادات الأدمن: فحص حالة الاتصال بـ Gemini + تشغيل/إيقاف كل نوع
/// إشعار لوحده.
///
/// الجولة الثالثة: نقطة ١٢ — تغيير كلمة المرور الشخصية اتشال من هنا
/// خالص، بقى موجود بس في تبويب "حسابي" الثابت. نقطة ١١ — قايمة
/// الإشعارات اتوسّعت من ٤ لكل الأحداث الحقيقية في النظام، معروضة
/// كمجموعات قابلة للطي (ExpansionTile عادي هنا، مش جوه Dialog، فمفيش
/// تعارض state زي الباج اللي اتصلح في admin_home_screen.dart).
class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  bool? _geminiOk; // null = لسه ماتفحصش
  bool _checkingGemini = false;

  final _notificationRepo = NotificationRepository();
  Map<String, bool> _notifSettings = {};
  bool _loadingNotifSettings = true;

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
          for (final type in NotificationEventType.values)
            type.dbValue: settings[type.dbValue] ?? true,
        };
        _loadingNotifSettings = false;
      });
    }
  }

  Future<void> _toggleNotifType(String type, bool value) async {
    setState(() => _notifSettings[type] = value);
    await _notificationRepo.setTypeEnabled(type, value);
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
                  children: notificationEventGroups.entries.map((group) {
                    return Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(group.key, textAlign: TextAlign.right),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        children: group.value.map((type) {
                          return SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _notifSettings[type.dbValue] ?? true,
                            onChanged: (v) => _toggleNotifType(type.dbValue, v),
                            title: Text(type.arabicLabel, textAlign: TextAlign.right),
                          );
                        }).toList(),
                      ),
                    );
                  }).toList(),
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