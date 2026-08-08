import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/analytics_repository.dart';

/// شاشة تحليل بيانات المخزون. مبنية بالكامل على بيانات حقيقية.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _repo = AnalyticsRepository();
  bool _loading = true;

  int _totalItems = 0;
  int _dispatchedWeek = 0;
  int _dispatchedMonth = 0;
  Map<String, int> _statusBreakdown = {};
  Map<String, int> _ownershipBreakdown = {};
  Map<String, int> _exitReasonBreakdown = {};
  List<MapEntry<DateTime, int>> _trend = [];

  static const _chartLabels = {
    'stats': 'أرقام سريعة (إجمالي/أسبوع/شهر)',
    'status': 'توزيع حالة المخزون',
    'ownership': 'الصيانة/الأمانة الآن',
    'exit_reason': 'سبب الصرف',
    'trend': 'اتجاه الصرف',
  };
  Set<String> _visibleCharts = _chartLabels.keys.toSet();

  Future<void> _pickVisibleCharts() async {
    final selection = Set<String>.from(_visibleCharts);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('اختار المؤشرات اللي عاوز تشوفها'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _chartLabels.entries.map((entry) {
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
      _loading = false;
    });
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _pickVisibleCharts,
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('اختار المؤشرات'),
            ),
          ),
          const SizedBox(height: 12),
          if (_visibleCharts.contains('stats')) ...[
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

          if (_visibleCharts.contains('status')) ...[
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

          if (_visibleCharts.contains('ownership')) ...[
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

          if (_visibleCharts.contains('exit_reason')) ...[
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

          if (_visibleCharts.contains('trend'))
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

          if (_visibleCharts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text('مفيش أي مؤشر مختار — دوس "اختار المؤشرات" لتظهر حاجة',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            ),
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