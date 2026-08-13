import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner_plus/flutter_barcode_scanner_plus.dart';
import '../theme/app_theme.dart';
import '../services/app_logger.dart';
import '../services/error_messages.dart';

/// يفتح شاشة سكانر باركود ويرجع أول قيمة يتم مسحها، أو null لو
/// المستخدم رجع من غير ما يمسح حاجة.
///
/// الجولة الثالثة (باج ١٣ — الحل النهائي بعد محاولتين فشلوا): كنا
/// مستخدمين `mobile_scanner` (مبني على CameraX)، وكانت بتطلع
/// NullPointerException حقيقية جوه الكود الأصلي للمكتبة
/// (`getClass() on a null object reference`) — بحثنا فيها كويس، مفيش
/// أي حل موثّق ليها، وتشخيصها أعمق مستحيل من غير PC (يحتاج
/// READ_LOGS، مينفعش يتفعّل من غير جهاز متصل بكمبيوتر أو Root).
///
/// بدل ما نفضل نخمّن في مكتبة بمشكلة غير معروفة، استبدلناها بمكتبة
/// تانية (`flutter_barcode_scanner_plus`) بمسار كود مختلف تماماً —
/// شاشة مسح كاملة من نظام أندرويد نفسه (native Activity) مبنية على
/// ZXing (Camera القديمة)، مش platform view مطعّم جوه Flutter زي
/// الأولى. المكتبة دي بتدير طلب صلاحية الكاميرا وواجهة المسح
/// بنفسها بالكامل، فمش محتاجين أي كود إضافي هنا.
Future<String?> scanBarcode(BuildContext context) async {
  try {
    final result = await FlutterBarcodeScanner.scanBarcode(
      '#0A2540', // لون خط المسح — نفس الكحلي الأساسي في التطبيق
      'إلغاء',
      true, // إظهار أيقونة الفلاش
      ScanMode.DEFAULT,
    );
    // "-1" هي القيمة المتفق عليها في المكتبة دي لما المستخدم يرجع
    // بزرار الرجوع من غير ما يمسح حاجة — مش نتيجة مسح فعلية.
    if (result == '-1' || result.isEmpty) return null;
    return result;
  } catch (e, st) {
    AppLogger.logError('scanBarcode', e, st);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e)),
          backgroundColor: AppColors.danger,
        ),
      );
    }
    return null;
  }
}