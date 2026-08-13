import 'package:device_info_plus/device_info_plus.dart';
import 'app_logger.dart';

/// وصف مختصر للجهاز (موديل + نسخة أندرويد) — بيتسجل مع كل جلسة دخول.
Future<String> getDeviceDescription() async {
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return '${info.manufacturer} ${info.model} (Android ${info.version.release})';
  } catch (e, st) {
    AppLogger.logError('getDeviceDescription', e, st);
    return 'جهاز غير معروف';
  }
}