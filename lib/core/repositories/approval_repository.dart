import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/enums.dart';
import '../models/pending_approval.dart';

/// إدارة طلبات الموافقة المعلّقة (تعديل رقم قطعة/سريال، استيراد قاعدة
/// معرفة). الإنشاء عادي من العميل، لكن التطبيق الفعلي (الموافقة/الرفض)
/// بيعدي على Edge Function `resolve-approval` عشان يطبّق التغيير بثقة
/// أعلى ويسجّله بشكل موحّد.
class ApprovalRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> create({
    required ApprovalType type,
    required Map<String, dynamic> payload,
    required String requestedBy,
  }) async {
    await _client.from('pending_approvals').insert({
      'approval_type': type.dbValue,
      'payload': payload,
      'requested_by': requestedBy,
      'status': 'Pending',
    });
  }

  Future<List<PendingApproval>> getPending({int limit = 100}) async {
    final rows = await _client
        .from('pending_approvals')
        .select()
        .eq('status', 'Pending')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => PendingApproval.fromMap(r)).toList();
  }

  /// TASK-301: الدالة على السيرفر بقت بتتحقق إن المستدعي admin فعلاً
  /// (requireRole)، وresolvedBy بقى بيتحدد من التوكن نفسه — مش من قيمة
  /// بنبعتها من هنا، فمحتاجين نبعت التوكن في الهيدر بدل resolvedBy.
  ///
  /// بيرجع null لو نجحت، أو رسالة الخطأ (عربية وجاهزة، بما فيها حالة
  /// "الطلب ده اتحسم قبل كده" لو حد تاني كسب سباق الحسم — راجع
  /// claim_pending_approval_tx في migrations/016_state_transition_guards.sql)
  /// لو فشلت.
  Future<String?> resolve({
    required int approvalId,
    required bool approve,
    required String adminToken,
  }) async {
    final response = await _client.functions.invoke(
      'resolve-approval',
      body: {
        'approvalId': approvalId,
        'action': approve ? 'approve' : 'reject',
      },
      headers: {'x-app-token': adminToken},
    );
    final data = response.data as Map<String, dynamic>?;
    if (data?['success'] == true) return null;
    return data?['error']?.toString() ?? 'فشل تنفيذ الطلب';
  }
}