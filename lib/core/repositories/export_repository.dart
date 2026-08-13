import 'package:supabase_flutter/supabase_flutter.dart';

/// بيانات التصدير الخام — بترجع كل صف كـ Map زي ما هو من القاعدة (من
/// غير تحويل لموديل)، عشان التصدير يفضل متزامن تلقائياً مع أي عمود
/// جديد يتضاف للجدول من غير ما نعدّل الكود هنا.
///
/// TASK-322: كل التقارير بقت بتعدّي على Edge Function `export-data`
/// بدل ما تسأل الجداول مباشرة بمفتاح anon — الصلاحية (can_export أو
/// admin) بقت بتتحقق فعلياً على السيرفر، مش بس شرط إظهار الزرار في
/// الواجهة. راجع supabase/functions/export-data/index.ts.
class ExportRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _export(String dataset, {String? token}) async {
    final response = await _client.functions.invoke(
      'export-data',
      body: {'dataset': dataset},
      headers: token != null ? {'x-app-token': token} : null,
    );
    final data = response.data as Map<String, dynamic>?;
    if (data?['success'] != true) {
      throw Exception(data?['error']?.toString() ?? 'فشل التصدير');
    }
    return (data!['rows'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getFullInventory({String? token}) =>
      _export('full', token: token);

  Future<List<Map<String, dynamic>>> getAvailableInventory({String? token}) =>
      _export('available', token: token);

  Future<List<Map<String, dynamic>>> getDispatchedInventory({String? token}) =>
      _export('dispatched', token: token);

  Future<List<Map<String, dynamic>>> getKnowledgeBase({String? token}) =>
      _export('kb', token: token);

  Future<List<Map<String, dynamic>>> getTransactionLog({String? token}) =>
      _export('log', token: token);
}
