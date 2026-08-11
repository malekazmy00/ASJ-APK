import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';

/// يفتح شاشة سكانر باركود كاملة ويرجع أول قيمة يتم مسحها، أو null لو
/// المستخدم رجع من غير ما يمسح حاجة.
///
/// الجولة الثالثة (باج ١٣ — محاولة تالتة): السكرين شوت الأخير كشف
/// الاستثناء الحقيقي جوه أندرويد نفسه (NullPointerException:
/// "getClass() on a null object reference") — ده نمط عام بيحصل في أي
/// Plugin أندرويد بيمرّر بيانات عبر Method Channel لما قيمة تبقى null
/// في مكان النظام مستني فيه كائن حقيقي، مش عيب خاص بمكتبة الكاميرا
/// تحديداً. عشان نعرف السبب بالظبط (مكتبة الكاميرا نفسها ولا
/// permission_handler) محتاجين الـ Stack Trace الكامل مش الرسالة بس —
/// دلوقتي بنطلعه كامل (PlatformException.stacktrace لو موجود) بدل ما
/// نفضل نخمّن.
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

    PermissionStatus status;
    try {
      status = await Permission.camera.request();
    } catch (e, st) {
      // لو حتى طلب الصلاحية نفسه فشل، ده مؤشر قوي إن المشكلة في
      // permission_handler نفسها مش في mobile_scanner.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = 'فشل طلب صلاحية الكاميرا (permission_handler):\n${_describeError(e, st)}';
      });
      return;
    }
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
    } catch (e, st) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = 'تعذر تشغيل الكاميرا (mobile_scanner):\n${_describeError(e, st)}';
      });
    }
  }

  /// بيبني وصف كامل للخطأ — النوع، الرسالة، وأهم سطرين من الـ Stack
  /// Trace (اللي بيوضح بالظبط مكتبة/سطر المشكلة). لو PlatformException
  /// (زي أي خطأ Method Channel أندرويد)، بيضيف الـ code والتفاصيل
  /// الأصلية من الجافا كمان.
  String _describeError(Object e, StackTrace st) {
    final buffer = StringBuffer();
    if (e is MobileScannerException) {
      buffer.writeln('MobileScannerErrorCode: ${e.errorCode}');
      if (e.errorDetails?.message != null) {
        buffer.writeln('التفاصيل: ${e.errorDetails!.message}');
      }
    } else if (e is PlatformException) {
      buffer.writeln('النوع: PlatformException');
      buffer.writeln('code: ${e.code}');
      if (e.message != null) buffer.writeln('message: ${e.message}');
      if (e.details != null) buffer.writeln('details: ${e.details}');
    } else {
      buffer.writeln('النوع: ${e.runtimeType}');
      buffer.writeln(e.toString());
    }
    final stackLines = st.toString().split('\n').take(6).join('\n');
    if (stackLines.isNotEmpty) {
      buffer.writeln('---');
      buffer.writeln(stackLines);
    }
    return buffer.toString().trim();
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
                final buffer = StringBuffer();
                buffer.writeln('MobileScannerErrorCode: ${error.errorCode}');
                if (error.errorDetails?.message != null) {
                  buffer.writeln('التفاصيل: ${error.errorDetails!.message}');
                }
                return _ErrorRetryView(
                  message: 'تعذر تشغيل الكاميرا (mobile_scanner):\n${buffer.toString().trim()}',
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
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
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