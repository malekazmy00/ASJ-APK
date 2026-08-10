import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';

/// يفتح شاشة سكانر باركود كاملة ويرجع أول قيمة يتم مسحها، أو null لو
/// المستخدم رجع من غير ما يمسح حاجة.
///
/// الجولة الثالثة (باج ١٣ — محاولة تانية بعد التأكد إن الصلاحية
/// شغّالة): السكرين شوت أكّد إن صلاحية الكاميرا بتتوافق عليها تلقائي
/// من غير مشكلة (مفيش نافذة صلاحية فشلت ولا زرار "فتح الإعدادات"
/// ظهر) — يبقى `genericError` مش سببه الصلاحية خالص، والمشكلة في
/// بدء تشغيل الكاميرا نفسها (CameraX).
///
/// حسب توثيق مكتبة mobile_scanner نفسها، نفس تصنيف الخطأ ده بيظهر
/// كمان لما الـ controller يتحاول يبدأ (`start()`) مرتين في نفس
/// الوقت — بيحصل غالباً لما `autoStart` التلقائي بيتعارض مع انتقال
/// الشاشة نفسه. اتشال الاعتماد على autoStart، وبقى فيه بدء يدوي
/// محكوم + إيقاف صريح قبل أي إعادة محاولة أو إغلاق للشاشة. كمان
/// بقينا نطلع تفاصيل الخطأ الحقيقية (errorDetails) مش بس التصنيف
/// العام، عشان لو استمرت المشكلة نعرف السبب الدقيق من الرسالة نفسها.
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
  bool _busy = true;
  bool _ready = false;
  String? _errorText;
  bool _canOpenSettings = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _busy = true;
      _errorText = null;
      _canOpenSettings = false;
      _ready = false;
    });

    // إيقاف أي كنترولر قديم قبل أي محاولة جديدة، عشان نضمن مفيش
    // بدء تشغيل مزدوج (السبب الموثّق لنفس تصنيف الخطأ ده).
    if (_controller != null) {
      try {
        await _controller!.stop();
      } catch (_) {}
      await _controller!.dispose();
      _controller = null;
    }

    final status = await Permission.camera.request();
    if (!mounted) return;

    if (!status.isGranted) {
      setState(() {
        _busy = false;
        _canOpenSettings = status.isPermanentlyDenied;
        _errorText = status.isPermanentlyDenied
            ? 'إذن الكاميرا مرفوض بشكل دائم. افتح إعدادات التطبيق من الموبايل وفعّل صلاحية الكاميرا يدوياً.'
            : 'محتاجين إذن الكاميرا عشان نقدر نمسح الباركود.';
      });
      return;
    }

    final controller = MobileScannerController(autoStart: false);
    try {
      await controller.start();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _busy = false;
        _ready = true;
      });
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      final detail = e is MobileScannerException
          ? (e.errorDetails?.message ?? e.errorCode.toString())
          : e.toString();
      setState(() {
        _busy = false;
        _errorText = 'تعذر تشغيل الكاميرا:\n$detail';
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _controller?.stop();
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
          if (_ready && _controller != null)
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () => _controller!.toggleTorch(),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_busy)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_errorText != null)
            _ErrorRetryView(
              message: _errorText!,
              onRetry: _init,
              onOpenSettings: _canOpenSettings ? openAppSettings : null,
            )
          else if (_ready && _controller != null)
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) {
                final detail = error.errorDetails?.message ?? error.errorCode.toString();
                return _ErrorRetryView(
                  message: 'تعذر تشغيل الكاميرا:\n$detail',
                  onRetry: _init,
                  onOpenSettings: null,
                );
              },
            ),
          if (_ready && _errorText == null)
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