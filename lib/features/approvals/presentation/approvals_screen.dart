import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/pending_approval.dart';
import '../../../core/repositories/approval_repository.dart';
import '../../auth/presentation/auth_providers.dart';

/// طلبات محتاجة موافقة الأدمن (تعديل رقم قطعة/سريال، استيراد قاعدة
/// معرفة) — الإشعار بيوصل، لكن التنفيذ الفعلي (موافقة/رفض) من هنا بس.
class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  final _repo = ApprovalRepository();
  List<PendingApproval> _pending = [];
  bool _loading = true;
  final Set<int> _resolving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final pending = await _repo.getPending();
    if (mounted) {
      setState(() {
        _pending = pending;
        _loading = false;
      });
    }
  }

  Future<void> _resolve(PendingApproval approval, bool approve) async {
    final token = ref.read(authControllerProvider.notifier).token;
    if (token == null || approval.id == null) return;

    setState(() => _resolving.add(approval.id!));
    final error = await _repo.resolve(
      approvalId: approval.id!,
      approve: approve,
      adminToken: token,
    );
    if (mounted) {
      setState(() => _resolving.remove(approval.id!));
      if (error == null) {
        setState(() => _pending.removeWhere((a) => a.id == approval.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'تمت الموافقة وتطبيق التعديل' : 'تم رفض الطلب'),
            backgroundColor: approve ? AppColors.success : AppColors.textMuted,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  String _summarize(PendingApproval approval) {
    final p = approval.payload;
    switch (approval.approvalType) {
      case ApprovalType.partNumberEdit:
        return 'من "${p['oldPartNumber']}" إلى "${p['newPartNumber']}" — قطعة #${p['itemId']}';
      case ApprovalType.serialEdit:
        return 'من "${p['oldSerial'] ?? '—'}" إلى "${p['newSerial']}" — قطعة #${p['itemId']}';
      case ApprovalType.kbImport:
        final rows = p['rows'];
        final count = rows is List ? rows.length : 0;
        return 'استيراد $count رقم قطعة لقاعدة المعرفة';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_pending.isEmpty) {
      return const Center(
        child: Text('لا توجد طلبات معلّقة حالياً.', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pending.length,
        itemBuilder: (context, index) {
          final approval = _pending[index];
          final isResolving = _resolving.contains(approval.id);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        approval.approvalType.arabicLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.pending_actions, size: 18, color: AppColors.warning),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_summarize(approval), textAlign: TextAlign.right),
                  const SizedBox(height: 4),
                  Text(
                    'طلبه: ${approval.requestedBy ?? '—'}${approval.createdAt != null ? ' — ${approval.createdAt}' : ''}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isResolving ? null : () => _resolve(approval, false),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                          child: const Text('رفض'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isResolving ? null : () => _resolve(approval, true),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                          child: isResolving
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('موافقة'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}