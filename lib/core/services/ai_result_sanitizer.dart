/// TASK-318: الـ AI بيرجع اقتراح، مش مصدر حقيقة — الشاشات اللي بتستخدم
/// analyze-part أصلاً بتحط النتيجة في حقول قابلة للتعديل يراجعها
/// المستخدم قبل الحفظ (مفيش حفظ تلقائي من غير مراجعة بشرية). الدالة
/// دي بتعمل تنظيف/تحقق أساسي إضافي قبل ما النتيجة توصل للحقول خالص،
/// عشان تمنع أخطاء شائعة معروفة بدل ما تتسيب للمستخدم يلاحظها بعينه:
///  - قيم "placeholder" حرفية (زي "N/A"/"غير معروف") بترجع فاضية بدل
///    ما تتحط كنص فعلي في الحقل.
///  - لو الرقم التسلسلي جه مطابق تماماً لرقم القطعة (خطأ شائع من الـ
///    AI، خصوصاً إن الرقم التسلسلي المفروض ييجي من الصورة بس مش من
///    البحث العام)، بيتفضّى ويتحط تحذير للمستخدم.
class AiResultSanitizer {
  static const _placeholders = {
    'n/a',
    'na',
    'unknown',
    'null',
    '-',
    '—',
    'غير معروف',
    'غير محدد',
    'لا يوجد',
    'مش معروف',
    'unspecified',
  };

  static const _fields = [
    'Brand',
    'Category',
    'Part_Number',
    'Part_Model',
    'Serial_Number',
    'Compatible_Model',
    'Additional_Compatibility',
    'Market_Value',
    'Gemini_Insights',
  ];

  static ({Map<String, String> values, List<String> warnings}) sanitize(
    Map<String, dynamic> raw,
  ) {
    String clean(String key) {
      final v = (raw[key] as String? ?? '').trim();
      return _placeholders.contains(v.toLowerCase()) ? '' : v;
    }

    final warnings = <String>[];
    final values = <String, String>{
      for (final key in _fields) key: clean(key),
    };

    final partNumber = values['Part_Number'] ?? '';
    final serial = values['Serial_Number'] ?? '';
    if (partNumber.isNotEmpty && partNumber == serial) {
      values['Serial_Number'] = '';
      warnings.add(
        'الرقم التسلسلي المقترح جه مطابق لرقم القطعة — تم تفريغه، اكتبه يدوياً من على القطعة لو موجود',
      );
    }

    return (values: values, warnings: warnings);
  }
}
