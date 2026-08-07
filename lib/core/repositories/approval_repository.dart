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

  Future<bool> resolve({
    required int approvalId,
    required bool approve,
    required String resolvedBy,
  }) async {
    final response = await _client.functions.invoke(
      'resolve-approval',
      body: {
        'approvalId': approvalId,
        'action': approve ? 'approve' : 'reject',
        'resolvedBy': resolvedBy,
      },
    );
    final data = response.data as Map<String, dynamic>?;
    return data?['success'] == true;
  }
}