import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/enums.dart';
import '../models/transaction_log.dart';
import '../theme/app_theme.dart';

/// عنصر واجهة مشترك (زي ما اتفقنا في نقاش الأفكار): نفس شكل التايم لاين
/// يُستخدم في تتبع القطعة (فلترة بـ part_number) وتتبع المستخدم (فلترة
/// بـ username) — نفس مصدر البيانات (transactions_log)، عرض مختلف حسب
/// السياق فقط.
class TimelineWidget extends StatelessWidget {
  const TimelineWidget({
    super.key,
    required this.logs,
    this.emptyMessage = 'لا توجد حركات مسجّلة',
    this.showUsername = true,
  });

  final List<TransactionLog> logs;
  final String emptyMessage;
  final bool showUsername;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(emptyMessage, textAlign: TextAlign.center),
      );
    }

    final formatter = DateFormat('yyyy-MM-dd  HH:mm');

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        final isLast = index == logs.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _colorFor(log.actionType),
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(width: 2, color: Colors.grey.shade300),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.actionType.arabicLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (log.details != null && log.details!.isNotEmpty)
                        Text(log.details!),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (showUsername && log.username != null) log.username!,
                          if (log.timestamp != null) formatter.format(log.timestamp!),
                        ].join('  •  '),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _colorFor(ActionType actionType) {
    switch (actionType.dbValue) {
      case 'INSERT':
        return AppColors.success;
      case 'OUT':
        return AppColors.warning;
      case 'DELETE':
        return AppColors.danger;
      case 'LOGIN':
      case 'LOGOUT':
        return AppColors.accent;
      default:
        return AppColors.primary;
    }
  }
}
