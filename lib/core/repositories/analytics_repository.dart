import 'package:supabase_flutter/supabase_flutter.dart';

/// بيانات تحليلية مبنية على الجداول الموجودة فعلاً (inventory_items،
/// transactions_log). التجميع بيتم في Dart لأن REST API بتاع Supabase
/// مباشرة مش بيدعم GROUP BY من غير RPC مخصص.
///
/// الجولة الثالثة (نقطة ٩): بدل ٥ مؤشرات ثابتة بس، الملف دلوقتي فيه
/// جزئين — "الأساسيات" (Part A: مؤشرات جاهزة، موسّعة شوية عن الـ٥
/// الأصليين) و"البناء الحر" (Part B: buildPivot، تختار عمود + تجميع +
/// نوع رسم بحرية بدل ما كل مؤشر جديد يحتاج كود جديد).
class AnalyticsRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // ============================================================
  // Part A — المؤشرات الأساسية الجاهزة (موسّعة عن الـ٥ الأصليين)
  // ============================================================

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

  /// توزيع أسباب الصرف (بيع/إعارة/تلف) لآخر [days] يوم — يعتمد على
  /// عمود exit_type.
  Future<Map<String, int>> getExitReasonBreakdown({int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final rows = await _client
        .from('transactions_log')
        .select('exit_type')
        .eq('action_type', 'OUT')
        .gte('timestamp', since.toIso8601String());
    final counts = <String, int>{};
    for (final r in rows as List) {
      final t = r['exit_type'] as String?;
      if (t == null) continue; // حركات صرف قديمة قبل إضافة العمود
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return counts;
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

  /// أكتر [topN] رقم قطعة اتصرفوا في آخر [days] يوم — إضافة جديدة
  /// للجزء الأساسي (Part A).
  Future<List<MapEntry<String, int>>> getTopDispatchedParts({
    int days = 30,
    int topN = 5,
  }) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final logRows = await _client
        .from('transactions_log')
        .select('item_id')
        .eq('action_type', 'OUT')
        .gte('timestamp', since.toIso8601String());
    final itemIds = (logRows as List)
        .map((r) => r['item_id'] as int?)
        .whereType<int>()
        .toList();
    if (itemIds.isEmpty) return [];

    final itemRows = await _client
        .from('inventory_items')
        .select('item_id, part_number')
        .inFilter('item_id', itemIds);
    final pnById = {
      for (final r in itemRows as List)
        r['item_id'] as int: (r['part_number'] as String?) ?? 'غير معروف'
    };

    final counts = <String, int>{};
    for (final id in itemIds) {
      final pn = pnById[id] ?? 'غير معروف';
      counts[pn] = (counts[pn] ?? 0) + 1;
    }
    final list = counts.entries.map((e) => MapEntry(e.key, e.value)).toList();
    list.sort((a, b) => b.value.compareTo(a.value));
    return list.take(topN).toList();
  }

  /// أداء صرف كل مهندس (عدد عمليات الصرف) في آخر [days] يوم — إضافة
  /// جديدة للجزء الأساسي (Part A).
  Future<Map<String, int>> getEngineerDispatchLeaderboard({int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final rows = await _client
        .from('transactions_log')
        .select('username')
        .eq('action_type', 'OUT')
        .gte('timestamp', since.toIso8601String());
    final counts = <String, int>{};
    for (final r in rows as List) {
      final u = r['username'] as String? ?? 'غير معروف';
      counts[u] = (counts[u] ?? 0) + 1;
    }
    return counts;
  }

  // ============================================================
  // Part B — البناء الحر (باني تحليل مرن، زي PivotTable مصغّر)
  // ============================================================

  /// الأعمدة المتاحة للتحليل الحر مع اسمها بالعربي — تُستخدم لتعبئة
  /// القايمة المنسدلة في الواجهة.
  static const Map<String, String> pivotColumns = {
    'item_type': 'نوع القطعة',
    'part_number': 'رقم القطعة',
    'status': 'حالة المخزون',
    'ownership_status': 'حالة الملكية',
    'location': 'المكان',
    'entry_type': 'نوع الإدخال',
    'condition': 'الحالة (جديد/مستعمل)',
  };

  /// أعمدة transactions_log المتاحة للتحليل الحر.
  static const Map<String, String> pivotLogColumns = {
    'action_type': 'نوع الحركة',
    'exit_type': 'سبب الصرف',
    'username': 'المستخدم',
  };

  /// بناء تحليل حر: يجمّع صفوف [table] حسب [groupByColumn]، بنوع
  /// تجميع [aggregation] (عدد فقط مدعوم دلوقتي لأن الجداول الحالية
  /// مفيهاش أعمدة رقمية قابلة للجمع/المتوسط غير الكميات نفسها).
  /// [since]/[until] فلتر زمني اختياري.
  Future<List<MapEntry<String, int>>> buildPivot({
    required String table,
    required String groupByColumn,
    DateTime? since,
    DateTime? until,
  }) async {
    final timeColumn = table == 'transactions_log' ? 'timestamp' : 'created_at';
    var q = _client.from(table).select(groupByColumn);
    if (since != null) q = q.gte(timeColumn, since.toIso8601String());
    if (until != null) q = q.lte(timeColumn, until.toIso8601String());
    final rows = await q;

    final counts = <String, int>{};
    for (final r in rows as List) {
      final key = (r[groupByColumn]?.toString().trim().isNotEmpty ?? false)
          ? r[groupByColumn].toString()
          : 'غير محدد';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final result = counts.entries.map((e) => MapEntry(e.key, e.value)).toList();
    result.sort((a, b) => b.value.compareTo(a.value));
    return result;
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}