import 'package:firebase_auth/firebase_auth.dart';
import 'device_service.dart';
import 'firebase_service.dart';

class LicensingService {
  // getPricing removed; pricing is handled by storefront configuration

  static Future<Map<String, dynamic>> getLicenseStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'success': false,
        'error': {'message': 'Not authenticated'}
      };
    }
    final uid = user.uid;
    final deviceId = await DeviceService.getDeviceId();
    // Ensure device is registered before checking license
    try {
      final registrationData = await DeviceService.getDeviceRegistrationData();
      await FirebaseService.callCloudFunction(
          'registerDevice', registrationData);
    } catch (_) {
      // Non-fatal: continue to license status even if registration fails
    }
    final res = await FirebaseService.callCloudFunction('getLicenseStatus', {
      'accountId': uid,
      'deviceId': deviceId,
    });
    // Ensure map<String,dynamic> shape for downstream
    return res.map((k, v) => MapEntry(k.toString(), v));
  }

  static Future<Map<String, dynamic>> startTrial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'success': false,
        'error': {'message': 'Not authenticated'}
      };
    }
    final uid = user.uid;
    final deviceId = await DeviceService.getDeviceId();
    final res = await FirebaseService.callCloudFunction('startTrial', {
      'accountId': uid,
      'deviceId': deviceId,
    });
    return res.map((k, v) => MapEntry(k.toString(), v));
  }

  static Future<Map<String, dynamic>> verifyGooglePurchase({
    required String purchaseToken,
    required String productId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'success': false,
        'error': {'message': 'Not authenticated'}
      };
    }
    final uid = user.uid;
    final deviceId = await DeviceService.getDeviceId();
    final res =
        await FirebaseService.callCloudFunction('verifyGooglePurchase', {
      'accountId': uid,
      'deviceId': deviceId,
      'purchaseToken': purchaseToken,
      'productId': productId,
    });
    return res.map((k, v) => MapEntry(k.toString(), v));
  }

  static Future<Map<String, dynamic>> transferLicense({
    required String newDeviceId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'success': false,
        'error': {'message': 'Not authenticated'}
      };
    }
    final uid = user.uid;
    final res = await FirebaseService.callCloudFunction('transferLicense', {
      'accountId': uid,
      'newDeviceId': newDeviceId,
    });
    return res.map((k, v) => MapEntry(k.toString(), v));
  }

  static Future<Map<String, dynamic>> getEnterpriseBranding(
      String enterpriseId) async {
    return await FirebaseService.callCloudFunction('getEnterpriseBranding', {
      'enterpriseId': enterpriseId,
    });
  }
}
