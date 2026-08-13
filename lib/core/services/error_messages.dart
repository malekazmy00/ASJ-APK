/// رسالة "منطق عمل" واضحة وجاهزة جاية من السيرفر نفسه (زي "القطعة دي
/// اتصرفت للتو" أو "الطلب ده اتحسم قبل كده") — مش استثناء تقني عايز
/// نترجمه، هو أصلاً الرسالة النهائية اللي المفروض المستخدم يشوفها.
/// راجع migrations/016_state_transition_guards.sql + rpcErrorResponse
/// في الـ Edge Functions.
class BusinessException implements Exception {
  final String message;
  const BusinessException(this.message);
  @override
  String toString() => message;
}

/// يحوّل استثناء تقني لرسالة عربية مفهومة للمستخدم النهائي، بدل ما
/// نعرض exception.toString() الخام زي ما كان بيحصل في أكتر من شاشة
/// (راجع H-08: "فشل الحفظ: $e" بيسرّب تفاصيل داخلية زي اسم الجدول أو
/// نوع الخطأ في Supabase للمستخدم). التفاصيل التقنية الكاملة لسه
/// بتتسجل عبر AppLogger في نفس اللحظة في كل موضع بينادي الدالة دي —
/// مش بتضيع، بس المستخدم النهائي مش المفروض يشوفها.
///
/// ملحوظة: فحص بالنص (string matching) بسيط ومقصود بسيط كده — مش محتاج
/// مكتبة تصنيف أخطاء كاملة عشان نوصّل رسالة عربية مناسبة لأكتر
/// الحالات شيوعاً (شبكة/مهلة/تكرار بيانات/صلاحية منتهية).
String friendlyErrorMessage(Object error) {
  if (error is BusinessException) return error.message;

  final text = error.toString().toLowerCase();

  if (text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused')) {
    return 'تأكد من الاتصال بالإنترنت وحاول تاني';
  }
  if (text.contains('timeoutexception') || text.contains('timeout')) {
    return 'استغرق الاتصال وقت أطول من اللازم — حاول تاني';
  }
  if (text.contains('camera') || text.contains('كاميرا') || text.contains('permission')) {
    return 'تأكد من إذن الكاميرا للتطبيق من إعدادات الجهاز وحاول تاني';
  }
  if (text.contains('duplicate key') || text.contains('unique constraint')) {
    return 'القيمة دي مسجّلة قبل كده — تأكد من البيانات وحاول تاني';
  }
  if (text.contains('401') || text.contains('unauthorized') || text.contains('جلسة منتهية')) {
    return 'جلسة الدخول انتهت — سجّل دخول تاني';
  }
  if (text.contains('403') || text.contains('forbidden') || text.contains('صلاحية')) {
    return 'مفيش صلاحية كافية لتنفيذ العملية دي';
  }
  if (text.contains('postgrestexception') || text.contains('functionexception')) {
    return 'حدث خطأ أثناء حفظ البيانات — حاول تاني، ولو استمرت المشكلة كلّم الأدمن';
  }
  return 'حدث خطأ غير متوقع — حاول تاني';
}
