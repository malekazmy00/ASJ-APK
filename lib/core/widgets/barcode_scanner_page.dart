import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';

/// يفتح شاشة سكانر باركود كاملة ويرجع أول قيمة يتم مسحها، أو null لو
/// المستخدم رجع من غير ما يمسح حاجة. إذن الكاميرا بيتطلب من النظام
/// تلقائياً وقت فتح الشاشة (مش صلاحية إدارية من الأدمن).
///
/// إصلاح باج: كانت الشاشة القديمة بتعرض شاشة سودا فاضية لو الكاميرا
/// فشلت (رفض الإذن، الكاميرا مستخدمة في حاجة تانية...) من غير أي
/// رسالة توضح السبب. دلوقتي بتستخدم errorBuilder عشان توري السبب
/// الحقيقي ورسالة واضحة بدل شاشة سودا مالهاش تفسير.
Future<String?> scanBarcode(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (context) => const _BarcodeScannerPage()),
  );
}

class _BarcodeScannerPage extends StatefulWidget {
  const _BarcodeScannerPage();

  @override
  State<_BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  final _controller = MobileScannerController();
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  String _errorMessage(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'إذن الكاميرا مرفوض. افتح إعدادات التطبيق من الموبايل وفعّل صلاحية الكاميرا يدوياً.';
      case MobileScannerErrorCode.unsupported:
        return 'الجهاز ده مش بيدعم مسح الباركود.';
      default:
        return 'تعذر تشغيل الكاميرا (${error.errorCode}). جرّب تقفل الشاشة وتفتحها تاني.';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('امسح الباركود'),
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Container(
                color: Colors.black,
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 42),
                      const SizedBox(height: 14),
                      Text(
                        _errorMessage(error),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 2.5),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}