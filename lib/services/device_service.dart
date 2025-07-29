import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class DeviceService {
  static const String _deviceIdKey = 'device_id';
  static const String _installationTimeKey = 'installation_time';

  static DeviceInfoPlugin? _deviceInfo;
  static PackageInfo? _packageInfo;

  // Initialize device service
  static Future<void> initialize() async {
    _deviceInfo = DeviceInfoPlugin();
    _packageInfo = await PackageInfo.fromPlatform();
  }

  // Get unique device identifier
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null) {
      deviceId = await _generateDeviceId();
      await prefs.setString(_deviceIdKey, deviceId);
    }

    return deviceId;
  }

  // Generate unique device ID
  static Future<String> _generateDeviceId() async {
    final deviceInfo = await _getDeviceInfo();
    final packageInfo = await _getPackageInfo();

    // Combine multiple device identifiers for uniqueness
    final deviceData = {
      'androidId': deviceInfo['androidId'] ?? '',
      'model': deviceInfo['model'] ?? '',
      'manufacturer': deviceInfo['manufacturer'] ?? '',
      'brand': deviceInfo['brand'] ?? '',
      'product': deviceInfo['product'] ?? '',
      'packageName': packageInfo.packageName,
      'version': packageInfo.version,
    };

    // Create hash from device data
    final jsonString = jsonEncode(deviceData);
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);

    return digest.toString();
  }

  // Get device installation time
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

  // Get device information
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    final deviceInfo = await _getDeviceInfo();
    final packageInfo = await _getPackageInfo();

    return {
      'deviceId': await getDeviceId(),
      'androidId': deviceInfo['androidId'] ?? '',
      'model': deviceInfo['model'] ?? '',
      'manufacturer': deviceInfo['manufacturer'] ?? '',
      'brand': deviceInfo['brand'] ?? '',
      'product': deviceInfo['product'] ?? '',
      'androidVersion': deviceInfo['version'] ?? '',
      'appVersion': packageInfo.version,
      'appBuildNumber': packageInfo.buildNumber,
      'packageName': packageInfo.packageName,
      'installationTime': (await getInstallationTime()).toIso8601String(),
      'platform': Platform.isAndroid ? 'android' : 'ios',
    };
  }

  // Get Android device info
  static Future<Map<String, dynamic>> _getDeviceInfo() async {
    if (_deviceInfo == null) {
      _deviceInfo = DeviceInfoPlugin();
    }

    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo!.androidInfo;
      return {
        'androidId': androidInfo.id,
        'model': androidInfo.model,
        'manufacturer': androidInfo.manufacturer,
        'brand': androidInfo.brand,
        'product': androidInfo.product,
        'version': androidInfo.version.release,
        'sdkInt': androidInfo.version.sdkInt,
      };
    } else {
      final iosInfo = await _deviceInfo!.iosInfo;
      return {
        'androidId': iosInfo.identifierForVendor,
        'model': iosInfo.model,
        'manufacturer': 'Apple',
        'brand': 'Apple',
        'product': iosInfo.name,
        'version': iosInfo.systemVersion,
      };
    }
  }

  // Get package info
  static Future<PackageInfo> _getPackageInfo() async {
    if (_packageInfo == null) {
      _packageInfo = await PackageInfo.fromPlatform();
    }
    return _packageInfo!;
  }

  // Check if device is compromised (basic root detection)
  static Future<bool> isDeviceCompromised() async {
    if (Platform.isAndroid) {
      final deviceInfo = await _getDeviceInfo();

      // Check for common root indicators
      final buildTags = deviceInfo['buildTags'] ?? '';
      final buildFingerprint = deviceInfo['buildFingerprint'] ?? '';

      final rootIndicators = [
        'test-keys',
        'debug',
        'userdebug',
        'eng',
        'su',
        'magisk',
        'supersu',
      ];

      for (final indicator in rootIndicators) {
        if (buildTags.toLowerCase().contains(indicator) ||
            buildFingerprint.toLowerCase().contains(indicator)) {
          return true;
        }
      }
    }

    return false;
  }

  // Get device registration data for API
  static Future<Map<String, dynamic>> getDeviceRegistrationData() async {
    final deviceInfo = await getDeviceInfo();

    return {
      'deviceId': deviceInfo['deviceId'],
      'appVersion': deviceInfo['appVersion'],
      'platform': deviceInfo['platform'],
      'installationTime': deviceInfo['installationTime'],
      'deviceModel': deviceInfo['model'],
      'androidVersion': deviceInfo['androidVersion'],
      'appBuildNumber': deviceInfo['appBuildNumber'],
    };
  }
}
