import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/analytics_repository.dart';
import '../../../core/repositories/field_permissions_repository.dart';
import '../../auth/presentation/auth_providers.dart';

/// شاشة تحليل بيانات المخزون.
///
/// الجولة الثالثة (نقطة ٨+٩): بدل ٥ مؤشرات ثابتة بس، الشاشة دلوقتي
/// فيها جزئين — "الأساسيات" (مؤشرات جاهزة موسّعة) و"بناء تحليل حر"
/// (زي PivotTable مصغّر: اختار عمود + نوع رسم بحرية). وإصلاح باج
/// دايالوج اختيار المؤشرات (كان بيطفح من غير سكرول على الشاشات الصغيرة).
/// نقطة ٢٧: أي مؤشر (بما فيه "بناء تحليل حر" نفسه) قابل للإخفاء
/// لحساب معين من الأدمن — لو مخفي، مش بيظهر خالص حتى لو موجود في
/// اختيارات المستخدم الشخصية (_visibleCharts).
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  final _repo = AnalyticsRepository();
  final _fieldRepo = FieldPermissionsRepository();
  bool _loading = true;
  Map<String, bool> _fieldOverrides = {};

  int _totalItems = 0;
  int _dispatchedWeek = 0;
  int _dispatchedMonth = 0;
  Map<String, int> _statusBreakdown = {};
  Map<String, int> _ownershipBreakdown = {};
  Map<String, int> _exitReasonBreakdown = {};
  List<MapEntry<DateTime, int>> _trend = [];
  List<MapEntry<String, int>> _topParts = [];
  Map<String, int> _engineerLeaderboard = {};

  // Part A — الأساسيات (موسّعة عن الـ٥ الأصليين بإضافة أكتر القطع
  // صرفاً وأداء المهندسين). المفاتيح هنا نفسها field_key المستخدمة في
  // FieldPermissionsRepository.tabFields['analytics'] — نفس التسمية
  // بالظبط ما عدا 'stats' هنا اللي مقابلها 'stat_totals' هناك، وباقي
  // المفاتيح متطابقة حرفياً.
  static const _chartLabels = {
    'stats': 'أرقام سريعة (إجمالي/أسبوع/شهر)',
    'status': 'توزيع حالة المخزون',
    'ownership': 'الصيانة/الأمانة الآن',
    'exit_reason': 'سبب الصرف',
    'trend': 'اتجاه الصرف',
    'top_parts': 'أكتر القطع صرفاً (٣٠ يوم)',
    'engineer_leaderboard': 'أداء صرف المهندسين (٣٠ يوم)',
  };

  /// يحوّل مفتاح شاشة الأساسيات المحلي (_chartLabels) لمفتاح جدول
  /// الصلاحيات (FieldPermissionsRepository.tabFields['analytics']).
  static const Map<String, String> _fieldKeyFor = {
    'stats': 'stat_totals',
    'status': 'status_chart',
    'ownership': 'ownership_chart',
    'exit_reason': 'exit_reason_chart',
    'trend': 'trend_chart',
    'top_parts': 'top_parts_chart',
    'engineer_leaderboard': 'engineer_leaderboard_chart',
  };

  Set<String> _visibleCharts = _chartLabels.keys.toSet();

  // Part B — بناء تحليل حر
  String _pivotTable = 'inventory_items';
  String _pivotColumn = 'status';
  List<MapEntry<String, int>>? _pivotResult;
  bool _pivotLoading = false;

  Map<String, String> get _pivotColumnOptions => _pivotTable == 'inventory_items'
      ? AnalyticsRepository.pivotColumns
      : AnalyticsRepository.pivotLogColumns;

  bool _fieldVisible(String fieldKey) =>
      FieldPermissionsRepository.isVisible(_fieldOverrides, fieldKey);

  /// نفس مؤشر _chartLabels لكن معدّي كمان من فلترة الأدمن.
  bool _chartAllowed(String chartKey) => _fieldVisible(_fieldKeyFor[chartKey]!);

  Future<void> _loadFieldOverrides() async {
    final username = ref.read(authControllerProvider)?.username;
    if (username == null) return;
    final overrides = await _fieldRepo.getOverrides(username, 'analytics');
    if (mounted) setState(() => _fieldOverrides = overrides);
  }

  Future<void> _pickVisibleCharts() async {
    final selection = Set<String>.from(_visibleCharts);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('اختار المؤشرات اللي عاوز تشوفها'),
          content: SizedBox(
            width: double.maxFinite,
            // إصلاح الجولة الثالثة (نقطة ٨): من غير SingleChildScrollView
            // هنا، القايمة كانت بتطفح على الشاشات الصغيرة من غير سكرول،
            // فالعناصر اللي تحت بتتقفل تحت أزرار الـ actions.
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  // نقطة ٢٧: المؤشرات اللي الأدمن مخفيها لهذا الحساب
                  // مابتظهرش في القايمة دي خالص كخيار للمستخدم.
                  children: _chartLabels.entries
                      .where((entry) => _chartAllowed(entry.key))
                      .map((entry) {
                    return CheckboxListTile(
                      value: selection.contains(entry.key),
                      title: Text(entry.value, textAlign: TextAlign.right),
                      onChanged: (v) => setDialogState(() {
                        if (v == true) {
                          selection.add(entry.key);
                        } else {
                          selection.remove(entry.key);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(selection),
              child: const Text('تم'),
            ),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _visibleCharts = result);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadFieldOverrides();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final results = await Future.wait([
      _repo.getTotalItemsCount(),
      _repo.getDispatchCountSince(now.subtract(const Duration(days: 7))),
      _repo.getDispatchCountSince(now.subtract(const Duration(days: 30))),
      _repo.getStatusBreakdown(),
      _repo.getOwnershipBreakdown(),
      _repo.getExitReasonBreakdown(),
      _repo.getDispatchTrend(days: 30),
      _repo.getTopDispatchedParts(days: 30, topN: 5),
      _repo.getEngineerDispatchLeaderboard(days: 30),
    ]);
    if (!mounted) return;
    setState(() {
      _totalItems = results[0] as int;
      _dispatchedWeek = results[1] as int;
      _dispatchedMonth = results[2] as int;
      _statusBreakdown = results[3] as Map<String, int>;
      _ownershipBreakdown = results[4] as Map<String, int>;
      _exitReasonBreakdown = results[5] as Map<String, int>;
      _trend = results[6] as List<MapEntry<DateTime, int>>;
      _topParts = results[7] as List<MapEntry<String, int>>;
      _engineerLeaderboard = results[8] as Map<String, int>;
      _loading = false;
    });
  }

  Future<void> _buildPivot() async {
    setState(() => _pivotLoading = true);
    try {
      final result = await _repo.buildPivot(table: _pivotTable, groupByColumn: _pivotColumn);
      if (mounted) setState(() => _pivotResult = result);
    } finally {
      if (mounted) setState(() => _pivotLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final statusData = _statusBreakdown.entries
        .map((e) => _Slice(ItemStatus.fromDb(e.key).arabicLabel, e.value))
        .toList();
    final ownershipData = _ownershipBreakdown.entries
        .map((e) => _Slice(OwnershipStatus.fromDb(e.key).arabicLabel, e.value))
        .toList();
    final exitReasonData = _exitReasonBreakdown.entries
        .map((e) => _Slice(ExitType.fromDb(e.key).arabicLabel, e.value))
        .toList();
    final inCustodyCount = _ownershipBreakdown.entries
        .where((e) => e.key != 'Owned')
        .fold<int>(0, (sum, e) => sum + e.value);
    final leaderboardData =
        _engineerLeaderboard.entries.map((e) => _Slice(e.key, e.value)).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('الأساسيات',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              OutlinedButton.icon(
                onPressed: _pickVisibleCharts,
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('اختار المؤشرات'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_visibleCharts.contains('stats') && _chartAllowed('stats')) ...[
            Row(
              children: [
                Expanded(child: _StatCard(label: 'إجمالي القطع', value: '$_totalItems')),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(label: 'صرف هذا الأسبوع', value: '$_dispatchedWeek')),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(label: 'صرف هذا الشهر', value: '$_dispatchedMonth')),
              ],
            ),
            const SizedBox(height: 20),
          ],

          if (_visibleCharts.contains('status') && _chartAllowed('status')) ...[
            _ChartCard(
              title: 'توزيع حالة المخزون',
              child: SfCircularChart(
                legend: const Legend(isVisible: true, overflowMode: LegendItemOverflowMode.wrap),
                series: <CircularSeries>[
                  PieSeries<_Slice, String>(
                    dataSource: statusData,
                    xValueMapper: (d, _) => d.label,
                    yValueMapper: (d, _) => d.value,
                    dataLabelSettings: const DataLabelSettings(isVisible: true),
                    pointColorMapper: (d, i) => _statusColor(d.label),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_visibleCharts.contains('ownership') && _chartAllowed('ownership')) ...[
            _ChartCard(
              title: 'القطع الموجودة للصيانة/الأمانة الآن ($inCustodyCount)',
              child: SfCircularChart(
                legend: const Legend(isVisible: true, overflowMode: LegendItemOverflowMode.wrap),
                series: <CircularSeries>[
                  DoughnutSeries<_Slice, String>(
                    dataSource: ownershipData,
                    xValueMapper: (d, _) => d.label,
                    yValueMapper: (d, _) => d.value,
                    dataLabelSettings: const DataLabelSettings(isVisible: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_visibleCharts.contains('exit_reason') && _chartAllowed('exit_reason')) ...[
            _ChartCard(
              title: 'توزيع الصرف حسب السبب — آخر 30 يوم',
              child: exitReasonData.isEmpty
                  ? const Center(
                      child: Text(
                        'لا توجد حركات صرف مسجّلة بسبب محدد بعد',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : SfCircularChart(
                      legend: const Legend(isVisible: true, overflowMode: LegendItemOverflowMode.wrap),
                      series: <CircularSeries>[
                        PieSeries<_Slice, String>(
                          dataSource: exitReasonData,
                          xValueMapper: (d, _) => d.label,
                          yValueMapper: (d, _) => d.value,
                          dataLabelSettings: const DataLabelSettings(isVisible: true),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
          ],

          if (_visibleCharts.contains('trend') && _chartAllowed('trend')) ...[
            _ChartCard(
              title: 'اتجاه الصرف — آخر 30 يوم',
              child: SfCartesianChart(
                primaryXAxis: DateTimeAxis(
                  dateFormat: null,
                  intervalType: DateTimeIntervalType.days,
                  interval: 5,
                ),
                primaryYAxis: const NumericAxis(minimum: 0),
                series: <CartesianSeries>[
                  LineSeries<MapEntry<DateTime, int>, DateTime>(
                    dataSource: _trend,
                    xValueMapper: (e, _) => e.key,
                    yValueMapper: (e, _) => e.value,
                    color: AppColors.accent,
                    markerSettings: const MarkerSettings(isVisible: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_visibleCharts.contains('top_parts') && _chartAllowed('top_parts')) ...[
            _ChartCard(
              title: 'أكتر القطع صرفاً — آخر 30 يوم',
              child: _topParts.isEmpty
                  ? const Center(
                      child: Text('لا توجد بيانات صرف كافية بعد',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                    )
                  : SfCartesianChart(
                      primaryXAxis: const CategoryAxis(),
                      primaryYAxis: const NumericAxis(minimum: 0),
                      series: <CartesianSeries>[
                        BarSeries<MapEntry<String, int>, String>(
                          dataSource: _topParts,
                          xValueMapper: (e, _) => e.key,
                          yValueMapper: (e, _) => e.value,
                          color: AppColors.primary,
                          dataLabelSettings: const DataLabelSettings(isVisible: true),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
          ],

          if (_visibleCharts.contains('engineer_leaderboard') && _chartAllowed('engineer_leaderboard'))
            _ChartCard(
              title: 'أداء صرف المهندسين — آخر 30 يوم',
              child: leaderboardData.isEmpty
                  ? const Center(
                      child: Text('لا توجد بيانات صرف كافية بعد',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                    )
                  : SfCartesianChart(
                      primaryXAxis: const CategoryAxis(),
                      primaryYAxis: const NumericAxis(minimum: 0),
                      series: <CartesianSeries>[
                        BarSeries<_Slice, String>(
                          dataSource: leaderboardData,
                          xValueMapper: (e, _) => e.label,
                          yValueMapper: (e, _) => e.value,
                          color: AppColors.accent,
                          dataLabelSettings: const DataLabelSettings(isVisible: true),
                        ),
                      ],
                    ),
            ),

          if (_visibleCharts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text('مفيش أي مؤشر مختار — دوس "اختار المؤشرات" لتظهر حاجة',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            ),

          if (_fieldVisible('pivot_builder')) ...[
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 12),
            Text('بناء تحليل حر', textAlign: TextAlign.right, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'اختار أي عمود من بيانات المخزون أو حركات الصرف وشوف عدد كل قيمة — زي جدول محوري مصغّر.',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _pivotTable,
                    decoration: const InputDecoration(labelText: 'مصدر البيانات'),
                    items: const [
                      DropdownMenuItem(value: 'inventory_items', child: Text('المخزون')),
                      DropdownMenuItem(value: 'transactions_log', child: Text('حركات الصرف/السجل')),
                    ],
                    onChanged: (v) => setState(() {
                      _pivotTable = v ?? _pivotTable;
                      _pivotColumn = _pivotColumnOptions.keys.first;
                      _pivotResult = null;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _pivotColumn,
                    decoration: const InputDecoration(labelText: 'العمود'),
                    items: _pivotColumnOptions.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _pivotColumn = v ?? _pivotColumn;
                      _pivotResult = null;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _pivotLoading ? null : _buildPivot,
              icon: _pivotLoading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bar_chart),
              label: const Text('بناء التحليل'),
            ),
            if (_pivotResult != null) ...[
              const SizedBox(height: 16),
              _ChartCard(
                title: 'النتيجة',
                child: _pivotResult!.isEmpty
                    ? const Center(
                        child: Text('لا توجد بيانات', style: TextStyle(color: AppColors.textMuted)),
                      )
                    : SfCartesianChart(
                        primaryXAxis: const CategoryAxis(),
                        primaryYAxis: const NumericAxis(minimum: 0),
                        series: <CartesianSeries>[
                          BarSeries<MapEntry<String, int>, String>(
                            dataSource: _pivotResult!.take(15).toList(),
                            xValueMapper: (e, _) => e.key,
                            yValueMapper: (e, _) => e.value,
                            color: AppColors.primary,
                            dataLabelSettings: const DataLabelSettings(isVisible: true),
                          ),
                        ],
                      ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Color _statusColor(String label) {
    switch (label) {
      case 'متاح':
        return AppColors.success;
      case 'صادر':
        return AppColors.roleEngineer;
      case 'محجوز':
        return AppColors.warning;
      case 'تالف':
        return AppColors.danger;
      default:
        return AppColors.textMuted;
    }
  }
}

class _Slice {
  final String label;
  final int value;
  _Slice(this.label, this.value);
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E9EC)),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.primary)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E9EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6, right: 4),
            child: Text(title,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary)),
          ),
          SizedBox(height: 220, child: child),
        ],
      ),
    );
  }
}