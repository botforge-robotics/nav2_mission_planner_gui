import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';

class GooglePlayService {
  static const MethodChannel _channel = MethodChannel('google_play_service');

  /// Get the Google account ID that was used to install the app from Play Store
  /// This is the account that will be used for licensing
  static Future<String?> getGoogleAccountId() async {
    try {
      debugPrint('🔍 Attempting to get Google account ID...');

      // Strategy 1: Try native method channel (most reliable)
      try {
        final accountId = await _channel.invokeMethod('getGoogleAccountId');
        if (accountId != null && accountId.toString().isNotEmpty) {
          debugPrint(
              '✅ Got Google account ID from native method: ${accountId.toString().substring(0, 20)}...');
          return accountId.toString();
        }
      } catch (e) {
        debugPrint('⚠️ Native method channel failed: $e');
      }

      // Strategy 2: Try to get from Play Store billing client
      try {
        final isAvailable = await InAppPurchase.instance.isAvailable();
        if (isAvailable) {
          debugPrint(
              '📱 Play Store is available, attempting to get account from billing client...');
          // This will trigger the billing client to initialize and potentially give us account info
          final response = await InAppPurchase.instance
              .queryProductDetails({'nav2_mission_planner_license'});
          if (response.error == null && response.productDetails.isNotEmpty) {
            debugPrint(
                '✅ Play Store connection successful, using device account');
            // For now, return a placeholder - the actual account will be determined during purchase
            return await _getDeviceAccountFallback();
          }
        }
      } catch (e) {
        debugPrint('⚠️ Play Store method failed: $e');
      }

      // Strategy 3: Device-based fallback
      return await _getDeviceAccountFallback();
    } catch (e) {
      debugPrint('❌ All methods failed to get Google account ID: $e');
      return null;
    }
  }

  /// Fallback method to get account ID from device information
  static Future<String?> _getDeviceAccountFallback() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      // Create a unique identifier based on device characteristics
      final deviceId = androidInfo.id;
      final brand = androidInfo.brand;
      final model = androidInfo.model;
      final manufacturer = androidInfo.manufacturer;

      // Create a hash-based account ID that's consistent for this device
      final accountHash =
          _generateAccountHash(deviceId, brand, model, manufacturer);
      debugPrint(
          '🔄 Using device-based account ID: ${accountHash.substring(0, 20)}...');

      return accountHash;
    } catch (e) {
      debugPrint('❌ Device fallback failed: $e');
      return null;
    }
  }

  /// Generate a consistent hash-based account ID from device characteristics
  static String _generateAccountHash(
      String deviceId, String brand, String model, String manufacturer) {
    final combined = '$deviceId-$brand-$model-$manufacturer';
    final hash = combined.hashCode.abs();
    return 'DEVICE_${hash.toString().padLeft(10, '0')}';
  }

  /// Check if we have a valid Google account ID
  static bool isValidAccountId(String? accountId) {
    if (accountId == null || accountId.isEmpty) return false;

    // Check if it's a device fallback ID
    if (accountId.startsWith('DEVICE_')) {
      debugPrint(
          '⚠️ Using device fallback account ID - this may limit some features');
      return true;
    }

    // Check if it looks like a valid Google account ID
    if (accountId.contains('@') || accountId.length > 20) {
      return true;
    }

    return false;
  }

  /// Get account type for debugging
  static String getAccountType(String? accountId) {
    if (accountId == null) return 'null';
    if (accountId.startsWith('DEVICE_')) return 'device_fallback';
    if (accountId.contains('@')) return 'google_account';
    return 'unknown';
  }

  /// Test method to verify account ID retrieval
  static Future<Map<String, dynamic>> testAccountRetrieval() async {
    try {
      debugPrint('🧪 Testing Google account ID retrieval...');

      final startTime = DateTime.now();
      final accountId = await getGoogleAccountId();
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      final result = {
        'success': accountId != null,
        'accountId': accountId,
        'accountType': getAccountType(accountId),
        'isValid': isValidAccountId(accountId),
        'duration': duration.inMilliseconds,
        'timestamp': DateTime.now().toIso8601String(),
      };

      debugPrint('🧪 Test results: $result');
      return result;
    } catch (e) {
      debugPrint('❌ Test failed: $e');
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// Check if we have the required permissions for account access
  static Future<bool> hasRequiredPermissions() async {
    try {
      final accountId = await getGoogleAccountId();
      return accountId != null &&
          accountId != "PERMISSION_PENDING" &&
          accountId != "NO_GOOGLE_ACCOUNT" &&
          !accountId.startsWith("ERROR:");
    } catch (e) {
      return false;
    }
  }

  /// Get detailed status about account access
  static Future<Map<String, dynamic>> getAccountStatus() async {
    try {
      final accountId = await getGoogleAccountId();

      return {
        'hasAccount': accountId != null,
        'accountId': accountId,
        'accountType': getAccountType(accountId),
        'isValid': isValidAccountId(accountId),
        'permissionStatus': accountId == "PERMISSION_PENDING"
            ? "pending"
            : accountId == "NO_GOOGLE_ACCOUNT"
                ? "no_account"
                : accountId?.startsWith("ERROR:") == true
                    ? "error"
                    : "granted",
        'canProceedWithPurchase': accountId != null &&
            accountId != "PERMISSION_PENDING" &&
            accountId != "NO_GOOGLE_ACCOUNT" &&
            !accountId.startsWith("ERROR:"),
        'recommendation': _getRecommendation(accountId),
      };
    } catch (e) {
      return {
        'hasAccount': false,
        'error': e.toString(),
        'canProceedWithPurchase': false,
        'recommendation': 'Check device settings and try again',
      };
    }
  }

  /// Get user-friendly recommendation based on account status
  static String _getRecommendation(String? accountId) {
    if (accountId == null) return 'Unable to determine account status';
    if (accountId == "PERMISSION_PENDING") {
      return 'Please grant account access permission when prompted';
    }
    if (accountId == "NO_GOOGLE_ACCOUNT") {
      return 'No Google account found on device. Please add a Google account in device settings.';
    }
    if (accountId.startsWith("ERROR:")) {
      return 'Error accessing accounts. Please check device settings.';
    }
    if (accountId.startsWith("DEVICE_")) {
      return 'Using device-based identification. Some features may be limited.';
    }
    return 'Account access successful';
  }
}
