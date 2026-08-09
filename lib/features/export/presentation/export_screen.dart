import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/export_repository.dart';
import '../../../core/repositories/log_repository.dart';
import '../../../core/repositories/notification_repository.dart';
import '../../auth/presentation/auth_providers.dart';

/// تصدير بيانات النظام كملفات CSV. متاحة لأي مستخدم عنده صلاحية
/// can_export (زي المخزون/تحليل البيانات بالظبط)، مش حصراً على دور.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  final _repo = ExportRepository();
  final _logRepo = LogRepository();
  final _notifRepo = NotificationRepository();
  String? _generatingKey;

  Future<void> _export({
    required String key,
    required String fileLabel,
    required Future<List<Map<String, dynamic>>> Function() fetch,
  }) async {
    setState(() => _generatingKey = key);
    try {
      final rows = await fetch();
      if (rows.isEmpty) {
        _showSnack('لا توجد بيانات لتصديرها في هذا التقرير حالياً', isError: true);
        return;
      }

      final headers = rows.first.keys.toList();
      final csvRows = <List<dynamic>>[
        headers,
        ...rows.map((r) => headers.map((h) => r[h]?.toString() ?? '').toList()),
      ];
      final csvString = const ListToCsvConverter().convert(csvRows);

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${dir.path}/${fileLabel}_$timestamp.csv');
      await file.writeAsString(csvString, encoding: const _Utf8BomEncoding());

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: fileLabel),
      );

      final username = ref.read(authControllerProvider)?.username ?? 'unknown';
      await _logRepo.logAction(
        actionType: ActionType.export_,
        username: username,
        details: 'تصدير تقرير: $fileLabel (${rows.length} صف)',
      );
      // إشعار مخصص لقاعدة المعرفة بس (نقطة ١١ في قايمة الإشعارات) —
      // باقي التقارير بتتسجل في السجل الموحّد من غير إشعار مستقل ليها.
      if (key == 'kb') {
        await _notifRepo.create(
          notifType: NotificationEventType.kbExport.dbValue,
          message: '$username صدّر قاعدة المعرفة (${rows.length} صف)',
        );
      }
    } catch (e) {
      _showSnack('فشل التصدير: $e', isError: true);
    } finally {
      if (mounted) setState(() => _generatingKey = null);
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
        _ExportTile(
          title: 'المخزون الكامل',
          subtitle: 'كل القطع المسجّلة بكل الحالات',
          icon: Icons.inventory_2_outlined,
          loading: _generatingKey == 'full',
          onTap: () => _export(key: 'full', fileLabel: 'المخزون_الكامل', fetch: _repo.getFullInventory),
        ),
        _ExportTile(
          title: 'المتاح فقط',
          subtitle: 'القطع اللي حالتها "متاح" حالياً',
          icon: Icons.check_circle_outline,
          loading: _generatingKey == 'available',
          onTap: () =>
              _export(key: 'available', fileLabel: 'المتاح', fetch: _repo.getAvailableInventory),
        ),
        _ExportTile(
          title: 'المصروف',
          subtitle: 'القطع اللي حالتها "صادر"',
          icon: Icons.outbox_outlined,
          loading: _generatingKey == 'dispatched',
          onTap: () =>
              _export(key: 'dispatched', fileLabel: 'المصروف', fetch: _repo.getDispatchedInventory),
        ),
        _ExportTile(
          title: 'قاعدة المعرفة',
          subtitle: 'كل بيانات القطع الفنية المحفوظة',
          icon: Icons.storage_outlined,
          loading: _generatingKey == 'kb',
          onTap: () => _export(key: 'kb', fileLabel: 'قاعدة_المعرفة', fetch: _repo.getKnowledgeBase),
        ),
        _ExportTile(
          title: 'سجل الحركات',
          subtitle: 'كل العمليات المسجّلة من أول يوم',
          icon: Icons.history,
          loading: _generatingKey == 'log',
          onTap: () => _export(key: 'log', fileLabel: 'سجل_الحركات', fetch: _repo.getTransactionLog),
        ),
      ],
    );
  }
}

/// UTF-8 مع BOM عشان الحروف العربية تفتح صح في Excel مباشرة.
class _Utf8BomEncoding extends Encoding {
  const _Utf8BomEncoding();
  @override
  String get name => 'utf-8-bom';
  @override
  Converter<String, List<int>> get encoder => const _Utf8BomEncoder();
  @override
  Converter<List<int>, String> get decoder => utf8.decoder;
}

class _Utf8BomEncoder extends Converter<String, List<int>> {
  const _Utf8BomEncoder();
  @override
  List<int> convert(String input) => [0xEF, 0xBB, 0xBF, ...utf8.encode(input)];
}

class _ExportTile extends StatelessWidget {
  const _ExportTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.loading,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, textAlign: TextAlign.right),
        subtitle: Text(subtitle, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5)),
        trailing: loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.ios_share, size: 18, color: AppColors.accent),
        onTap: loading ? null : onTap,
      ),
    );
  }
}