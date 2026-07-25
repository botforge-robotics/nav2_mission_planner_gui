import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widevine_service.dart';

class DeviceService {
  static const String _deviceIdKey = 'device_id';
  static const String _installationTimeKey = 'installation_time';
  static const String _fallbackIdPrefix = 'DEV-';

  static DeviceInfoPlugin? _deviceInfo;
  static PackageInfo? _packageInfo;

  static Future<void> initialize() async {
    _deviceInfo = DeviceInfoPlugin();
    _packageInfo = await PackageInfo.fromPlatform();
  }

  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null || deviceId.isEmpty) {
      final widevine = await _getWidevineId();
      deviceId = widevine ?? _generateFallbackId();
      await prefs.setString(_deviceIdKey, deviceId);
    }

    return deviceId;
  }

  static Future<String?> _getWidevineId() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final isSupported = await WidevineService.isWidevineSupported();
        if (isSupported) {
          return await WidevineService.getWidevineId();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _generateFallbackId() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final random = (millis % 1000000).toRadixString(36).toUpperCase();
    return '$_fallbackIdPrefix$random$millis';
  }

  static Future<DateTime> getInstallationTime() async {
    final prefs = await SharedPreferences.getInstance();
    final installationTimeStr = prefs.getString(_installationTimeKey);

    if (installationTimeStr == null) {
      final now = DateTime.now();
      await prefs.setString(_installationTimeKey, now.toIso8601String());
      return now;
    }

    return DateTime.parse(installationTimeStr);
  }

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final deviceInfo = await _getDeviceInfo();
    final packageInfo = await _getPackageInfo();
    final widevineId = await _getWidevineId();

    String platform = 'unknown';
    if (kIsWeb) {
      platform = 'web';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      platform = 'android';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      platform = 'ios';
    } else if (defaultTargetPlatform == TargetPlatform.linux) {
      platform = 'linux';
    }

    return {
      'deviceId': widevineId ?? '',
      'model': deviceInfo['model'] ?? '',
      'manufacturer': deviceInfo['manufacturer'] ?? '',
      'brand': deviceInfo['brand'] ?? '',
      'product': deviceInfo['product'] ?? '',
      'androidVersion': deviceInfo['version'] ?? '',
      'appVersion': packageInfo.version,
      'appBuildNumber': packageInfo.buildNumber,
      'packageName': packageInfo.packageName,
      'installationTime': (await getInstallationTime()).toIso8601String(),
      'platform': platform,
    };
  }

  static Future<Map<String, dynamic>> _getDeviceInfo() async {
    _deviceInfo ??= DeviceInfoPlugin();

    if (kIsWeb) {
      final web = await _deviceInfo!.webBrowserInfo;
      return {
        'model': web.browserName.name,
        'manufacturer': web.vendor ?? '',
        'brand': web.platform ?? 'web',
        'product': web.userAgent ?? '',
        'version': web.appVersion ?? '',
      };
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidInfo = await _deviceInfo!.androidInfo;
      return {
        'model': androidInfo.model,
        'manufacturer': androidInfo.manufacturer,
        'brand': androidInfo.brand,
        'product': androidInfo.product,
        'version': androidInfo.version.release,
        'sdkInt': androidInfo.version.sdkInt,
      };
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosInfo = await _deviceInfo!.iosInfo;
      return {
        'model': iosInfo.model,
        'manufacturer': 'Apple',
        'brand': 'Apple',
        'product': iosInfo.name,
        'version': iosInfo.systemVersion,
      };
    }

    return {
      'model': 'desktop',
      'manufacturer': '',
      'brand': '',
      'product': '',
      'version': '',
    };
  }

  static Future<PackageInfo> _getPackageInfo() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!;
  }

  static Future<bool> isDeviceCompromised() async {
    return false;
  }
}
