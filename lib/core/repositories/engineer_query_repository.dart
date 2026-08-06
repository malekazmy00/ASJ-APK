import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/engineer_query.dart';

/// يطابق repositories/query_repo.py — إدارة جدول engineer_queries
/// (طلبات قطع غير متوفرة حالياً في المخزون).
class EngineerQueryRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> create(EngineerQuery query) async {
    await _client.from('engineer_queries').insert(query.toInsertMap());
  }

  Future<List<EngineerQuery>> getRecent({String? status, int limit = 100}) async {
    var q = _client.from('engineer_queries').select();
    if (status != null) q = q.eq('status', status);
    final rows = await q.order('timestamp', ascending: false).limit(limit);
    return (rows as List).map((r) => EngineerQuery.fromMap(r)).toList();
  }

  Future<void> updateStatus(int queryId, String status) async {
    await _client
        .from('engineer_queries')
        .update({'status': status})
        .eq('query_id', queryId);
  }

  /// استعلامات سابقة على نفس رقم القطعة (أو نص قريب منه) — تُستخدم
  /// عشان تظهر جنب نتيجة البحث نفسها بدل تبويب منفصل.
  Future<List<EngineerQuery>> getByPartNumber(String partNumber, {int limit = 10}) async {
    final rows = await _client
        .from('engineer_queries')
        .select()
        .ilike('part_number', '%$partNumber%')
        .order('timestamp', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => EngineerQuery.fromMap(r)).toList();
  }
}