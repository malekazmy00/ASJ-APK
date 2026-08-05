import 'package:flutter/material.dart';
import '../../../core/models/transaction_log.dart';
import '../../../core/repositories/log_repository.dart';
import '../../../core/widgets/timeline_widget.dart';

/// تتبع القطعة: تكتب رقم القطعة، تجيب كل حركاتها من entry لحد الآن
/// (نفس الطلب الأصلي بالضبط).
class ItemTimelineScreen extends StatefulWidget {
  const ItemTimelineScreen({super.key});

  @override
  State<ItemTimelineScreen> createState() => _ItemTimelineScreenState();
}

class _ItemTimelineScreenState extends State<ItemTimelineScreen> {
  final _repo = LogRepository();
  final _controller = TextEditingController();
  List<TransactionLog> _logs = [];
  bool _loading = false;
  bool _searched = false;

  Future<void> _search() async {
    final partNumber = _controller.text.trim();
    if (partNumber.isEmpty) return;
    setState(() {
      _loading = true;
      _searched = true;
    });
    final logs = await _repo.getByPartNumber(partNumber);
    if (mounted) {
      setState(() {
        _logs = logs;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    hintText: 'رقم القطعة',
                    prefixIcon: Icon(Icons.qr_code),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _loading ? null : _search,
                child: const Text('بحث'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          if (_searched && !_loading)
            Expanded(
              child: SingleChildScrollView(
                child: TimelineWidget(
                  logs: _logs,
                  emptyMessage: 'لا توجد حركات مسجّلة لهذا الرقم',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
