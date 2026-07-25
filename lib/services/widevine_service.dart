import 'package:flutter/services.dart';

class WidevineService {
  static const MethodChannel _channel = MethodChannel('widevine_service');

  /// Get Widevine device ID for stable device identification
  static Future<String?> getWidevineId() async {
    try {
      final String? widevineId = await _channel.invokeMethod('getWidevineId');
      return widevineId;
    } on PlatformException {
      // Log error but don't throw - fallback to other methods
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Check if Widevine is supported on this device
  static Future<bool> isWidevineSupported() async {
    try {
      final bool isSupported =
          await _channel.invokeMethod('isWidevineSupported');
      return isSupported;
    } on PlatformException {
      return false;
    } catch (e) {
      return false;
    }
  }
}
