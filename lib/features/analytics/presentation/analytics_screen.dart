import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/enums.dart';
import '../../../core/repositories/analytics_repository.dart';

/// شاشة تحليل بيانات المخزون. مبنية بالكامل على بيانات حقيقية موجودة
/// في القاعدة دلوقتي (حالة القطع، حالة الملكية، حركات الصرف) — لسه
/// ناقص "توزيع الصرف حسب السبب" لحد ما نضيف dropdown سبب الصرف
/// (بيع/إعارة/تلف) في شاشة الصرف نفسها، عشان مفيش عمود بيانات
/// موثوق نبني عليه الرسم ده دلوقتي.
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
  List<MapEntry<DateTime, int>> _trend = [];

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
      _repo.getDispatchTrend(days: 30),
    ]);
    if (!mounted) return;
    setState(() {
      _totalItems = results[0] as int;
      _dispatchedWeek = results[1] as int;
      _dispatchedMonth = results[2] as int;
      _statusBreakdown = results[3] as Map<String, int>;
      _ownershipBreakdown = results[4] as Map<String, int>;
      _trend = results[5] as List<MapEntry<DateTime, int>>;
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
    final inCustodyCount = _ownershipBreakdown.entries
        .where((e) => e.key != 'Owned')
        .fold<int>(0, (sum, e) => sum + e.value);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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