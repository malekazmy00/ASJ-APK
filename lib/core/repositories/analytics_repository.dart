import 'package:supabase_flutter/supabase_flutter.dart';

/// بيانات تحليلية مبنية على الجداول الموجودة فعلاً (inventory_items،
/// transactions_log) — بدون أي عمود لسه مش موجود (زي "سبب الصرف" اللي
/// محتاج dropdown جديد مش متنفذ لسه). التجميع بيتم في Dart لأن REST
/// API بتاع Supabase مباشرة مش بيدعم GROUP BY من غير RPC مخصص.
class AnalyticsRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<int> getTotalItemsCount() async {
    final rows = await _client.from('inventory_items').select('item_id');
    return (rows as List).length;
  }

  /// توزيع القطع حسب الحالة الحالية (Available/Out/Reserved/Damaged).
  Future<Map<String, int>> getStatusBreakdown() async {
    final rows = await _client.from('inventory_items').select('status');
    final counts = <String, int>{};
    for (final r in rows as List) {
      final s = r['status'] as String? ?? 'Available';
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  /// توزيع القطع حسب حالة الملكية (Owned/Maintenance/Custody/Trial) —
  /// ده أساس "القطع الموجودة للصيانة/الأمانة دلوقتي".
  Future<Map<String, int>> getOwnershipBreakdown() async {
    final rows = await _client.from('inventory_items').select('ownership_status');
    final counts = <String, int>{};
    for (final r in rows as List) {
      final s = r['ownership_status'] as String? ?? 'Owned';
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  Future<int> getDispatchCountSince(DateTime since) async {
    final rows = await _client
        .from('transactions_log')
        .select('log_id')
        .eq('action_type', 'OUT')
        .gte('timestamp', since.toIso8601String());
    return (rows as List).length;
  }

  /// عدد عمليات الصرف يومياً لآخر [days] يوم (بما فيها الأيام اللي
  /// مفيهاش صرف = صفر، عشان الخط يبقى متصل).
  Future<List<MapEntry<DateTime, int>>> getDispatchTrend({int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final rows = await _client
        .from('transactions_log')
        .select('timestamp')
        .eq('action_type', 'OUT')
        .gte('timestamp', since.toIso8601String())
        .order('timestamp');

    final Map<String, int> byDay = {};
    for (final r in rows as List) {
      final ts = DateTime.tryParse(r['timestamp'].toString());
      if (ts == null) continue;
      final key = _dayKey(ts);
      byDay[key] = (byDay[key] ?? 0) + 1;
    }

    final result = <MapEntry<DateTime, int>>[];
    for (int i = days; i >= 0; i--) {
      final d = DateTime.now().subtract(Duration(days: i));
      final dayOnly = DateTime(d.year, d.month, d.day);
      result.add(MapEntry(dayOnly, byDay[_dayKey(d)] ?? 0));
    }
    return result;
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}