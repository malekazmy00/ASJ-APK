import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';

/// يفتح شاشة سكانر باركود كاملة ويرجع أول قيمة يتم مسحها، أو null لو
/// المستخدم رجع من غير ما يمسح حاجة.
///
/// الجولة الثالثة (باج ١٣ — إصلاح جذري): السبب الحقيقي وراء
/// `MobileScannerErrorCode.genericError` كان إن صلاحية الكاميرا ممكن
/// متتضافش فعلياً جوه AndroidManifest.xml وقت البناء (السكريبت في
/// codemagic.yaml كان بيحاول يضيفها من غير أي تحقق إنها اتضافت
/// فعلاً — اتصلح هناك). هنا طبقة حماية تانية: نطلب صلاحية الكاميرا
/// صراحة قبل ما نفتح الكاميرا خالص (مش نسيب mobile_scanner يطلبها
/// لوحده)، مع زرار "إعادة المحاولة" لو فشلت بدل ما المستخدم يضطر
/// يقفل الشاشة ويفتحها تاني.
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
  MobileScannerController? _controller;
  bool _handled = false;
  bool _checkingPermission = true;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndInit();
  }

  Future<void> _requestPermissionAndInit() async {
    setState(() {
      _checkingPermission = true;
      _permissionError = null;
    });

    final status = await Permission.camera.request();

    if (!mounted) return;

    if (status.isGranted) {
      setState(() {
        _controller = MobileScannerController();
        _checkingPermission = false;
      });
      return;
    }

    setState(() {
      _checkingPermission = false;
      _permissionError = status.isPermanentlyDenied
          ? 'إذن الكاميرا مرفوض بشكل دائم. افتح إعدادات التطبيق من الموبايل وفعّل صلاحية الكاميرا يدوياً.'
          : 'محتاجين إذن الكاميرا عشان نقدر نمسح الباركود.';
    });
  }

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
        return 'تعذر تشغيل الكاميرا (${error.errorCode}). دوس "إعادة المحاولة" تحت.';
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
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
          if (_controller != null)
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () => _controller!.toggleTorch(),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_checkingPermission)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_permissionError != null)
            _ErrorRetryView(
              message: _permissionError!,
              onRetry: _requestPermissionAndInit,
              onOpenSettings: openAppSettings,
            )
          else
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) {
                return _ErrorRetryView(
                  message: _errorMessage(error),
                  onRetry: _requestPermissionAndInit,
                  onOpenSettings: null,
                );
              },
            ),
          if (!_checkingPermission && _permissionError == null)
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

class _ErrorRetryView extends StatelessWidget {
  const _ErrorRetryView({
    required this.message,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final String message;
  final VoidCallback onRetry;
  final Future<bool> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) {
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
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
            if (onOpenSettings != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('فتح إعدادات التطبيق', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}