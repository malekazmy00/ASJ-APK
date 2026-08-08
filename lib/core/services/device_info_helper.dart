import 'package:device_info_plus/device_info_plus.dart';

/// وصف مختصر للجهاز (موديل + نسخة أندرويد) — بيتسجل مع كل جلسة دخول.
Future<String> getDeviceDescription() async {
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return '${info.manufacturer} ${info.model} (Android ${info.version.release})';
  } catch (_) {
    return 'جهاز غير معروف';
  }
}