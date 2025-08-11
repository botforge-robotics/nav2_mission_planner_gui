import 'package:firebase_auth/firebase_auth.dart';
import 'device_service.dart';
import 'firebase_service.dart';
import 'secure_storage_service.dart';

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
    final googleAccountId = await SecureStorageService.getGoogleAccountId();

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
      if (googleAccountId != null) 'googleAccountId': googleAccountId,
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
    final googleAccountId = await SecureStorageService.getGoogleAccountId();

    final res = await FirebaseService.callCloudFunction('startTrial', {
      'accountId': uid,
      'deviceId': deviceId,
      if (googleAccountId != null) 'googleAccountId': googleAccountId,
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

  // Update license on server after successful purchase
  static Future<Map<String, dynamic>> updateLicenseOnServer({
    required String productId,
    required String purchaseToken,
    String? googleAccountId,
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

    // Get Google account ID from secure storage if not provided
    googleAccountId ??= await SecureStorageService.getGoogleAccountId();

    print('📱 Using Google account ID: $googleAccountId');

    // Call the updateLicense function to update the server without verification
    final res = await FirebaseService.callCloudFunction('updateLicense', {
      'accountId': uid,
      'deviceId': deviceId,
      'purchaseToken': purchaseToken,
      'productId': productId,
      'orderId': 'CLIENT-${DateTime.now().millisecondsSinceEpoch}',
      if (googleAccountId != null) 'googleAccountId': googleAccountId,
    });

    print('📊 Server license update response: $res');
    return res.map((k, v) => MapEntry(k.toString(), v));
  }
}
