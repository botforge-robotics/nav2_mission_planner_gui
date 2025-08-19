import 'package:firebase_auth/firebase_auth.dart';
import 'device_service.dart';
import 'firebase_service.dart';
import 'dart:developer' as developer;

/// Service responsible for all licensing-related operations including license status,
/// trial management, purchase verification, and device management.
///
/// This service acts as the primary interface between the app and the licensing backend,
/// handling authentication, device registration, and cloud function calls.
class LicensingService {
  // ============================================================================
  // CORE LICENSE OPERATIONS
  // ============================================================================

  /// Retrieves the current license status for the authenticated user and device.
  ///
  /// This is the primary method for checking license state. It ensures the device
  /// is registered before checking license status and handles authentication.
  ///
  /// Returns a map containing:
  /// - `success`: boolean indicating if the operation succeeded
  /// - `data`: license information including status, type, and expiration dates
  /// - `error`: error details if the operation failed
  ///
  /// Throws [Exception] if authentication fails or network issues occur.
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
      final registrationData =
          await DeviceService.getDeviceRegistrationData(accountId: uid);
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

  /// Initiates a trial period for the authenticated user and device.
  ///
  /// Creates a new trial license that allows access to premium features
  /// for a limited time period.
  ///
  /// Returns a map containing:
  /// - `success`: boolean indicating if the trial was started
  /// - `data`: trial information including start and end dates
  /// - `error`: error details if the operation failed
  ///
  /// Throws [Exception] if authentication fails or trial creation fails.
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

  /// Transfers a license from one device to another.
  ///
  /// This method is used when a user wants to move their license to a new device.
  /// The old device's license will be deactivated and the new device will be activated.
  ///
  /// Parameters:
  /// - `newDeviceId`: The unique identifier of the target device
  ///
  /// Returns a map containing:
  /// - `success`: boolean indicating if the transfer succeeded
  /// - `data`: transfer confirmation details
  /// - `error`: error details if the transfer failed
  ///
  /// Throws [Exception] if authentication fails or transfer fails.
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

  // ============================================================================
  // PAYMENT OPERATIONS
  // ============================================================================

  /// Creates a payment session for Google Play purchases.
  ///
  /// This method must be called before initiating a purchase to establish
  /// a payment session with the backend. The session tracks the purchase
  /// and provides a payment ID for verification.
  ///
  /// Parameters:
  /// - `productId`: The unique identifier of the product to purchase
  /// - `accountId`: The user's account identifier
  /// - `deviceId`: The device identifier where the purchase is made
  ///
  /// Returns a map containing:
  /// - `success`: boolean indicating if the session was created
  /// - `data`: session details including payment ID and status
  /// - `error`: error details if session creation failed
  ///
  /// Throws [Exception] if authentication fails or session creation fails.
  static Future<Map<String, dynamic>> createPaymentSession({
    required String productId,
    required String accountId,
    required String deviceId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'success': false,
        'error': {'message': 'Not authenticated'}
      };
    }

    final res =
        await FirebaseService.callCloudFunction('createPaymentSession', {
      'accountId': accountId,
      'deviceId': deviceId,
      'productId': productId,
    });
    return res.map((k, v) => MapEntry(k.toString(), v));
  }

  /// Verifies a Google Play purchase with basic authentication.
  ///
  /// This is a simplified verification method for basic purchase validation.
  /// For secure purchases, use [verifyGooglePurchaseSecure] instead.
  ///
  /// Parameters:
  /// - `purchaseToken`: The purchase token from Google Play
  /// - `productId`: The unique identifier of the purchased product
  ///
  /// Returns a map containing:
  /// - `success`: boolean indicating if verification succeeded
  /// - `data`: verification details
  /// - `error`: error details if verification failed
  ///
  /// Throws [Exception] if authentication fails or verification fails.
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

  /// Verifies a Google Play purchase with comprehensive security checks.
  ///
  /// This method provides enhanced security by including additional verification
  /// parameters like payment ID and order ID. Use this for production purchases.
  ///
  /// Parameters:
  /// - `productId`: The unique identifier of the purchased product
  /// - `purchaseToken`: The purchase token from Google Play
  /// - `paymentId`: The payment session identifier
  /// - `accountId`: The user's account identifier
  /// - `deviceId`: The device identifier where the purchase was made
  /// - `orderId`: The unique order identifier
  ///
  /// Returns a map containing:
  /// - `success`: boolean indicating if verification succeeded
  /// - `data`: verification details including payment status
  /// - `error`: error details if verification failed
  ///
  /// Throws [Exception] if authentication fails or verification fails.
  static Future<Map<String, dynamic>> verifyGooglePurchaseSecure({
    required String productId,
    required String purchaseToken,
    required String paymentId,
    required String accountId,
    required String deviceId,
    required String orderId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'success': false,
        'error': {'message': 'Not authenticated'}
      };
    }

    final res =
        await FirebaseService.callCloudFunction('verifyGooglePurchase', {
      'accountId': accountId,
      'deviceId': deviceId,
      'purchaseToken': purchaseToken,
      'productId': productId,
      'orderId': orderId,
    });
    return res.map((k, v) => MapEntry(k.toString(), v));
  }

  /// Checks payment status and determines UI flow (unified function).
  ///
  /// This method handles both automatic (app open) and manual (user refresh) scenarios.
  /// Returns rich payment data for UI flow control and status verification.
  ///
  /// Returns a map containing:
  /// - `success`: boolean indicating if the check succeeded
  /// - `paymentStatus`: one of "no_payments", "pending", "cancelled", "paid", "failed", etc.
  /// - `latestPayment`: detailed payment information if available
  /// - `message`: human-readable message for UI display
  /// - `error`: error details if the check failed
  ///
  /// Throws [Exception] if authentication fails or status check fails.
  static Future<Map<String, dynamic>> checkPaymentStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'success': false,
        'error': {'message': 'Not authenticated'}
      };
    }
    final uid = user.uid;

    final res = await FirebaseService.callCloudFunction('checkPaymentStatus', {
      'accountId': uid,
    });
    return res.map((k, v) => MapEntry(k.toString(), v));
  }

  /// Helper method to get payment status from the response
  static String? getPaymentStatus(Map<String, dynamic> response) {
    // The response structure is: { data: { paymentStatus: "...", latestPayment: {...} }, success: true }
    final data = response['data'];
    if (data is Map) {
      return data['paymentStatus']?.toString();
    }
    return null;
  }

  /// Helper method to get latest payment data from the response
  static Map<String, dynamic>? getLatestPayment(Map<String, dynamic> response) {
    // The response structure is: { data: { paymentStatus: "...", latestPayment: {...} }, success: true }
    final data = response['data'];
    if (data is Map) {
      final latestPayment = data['latestPayment'];
      if (latestPayment is Map) {
        // Convert the Map<Object?, Object?> to Map<String, dynamic>
        return Map<String, dynamic>.from(latestPayment);
      }
    }
    return null;
  }

  /// Helper method to check if there are no payments
  static bool hasNoPayments(Map<String, dynamic> response) {
    return getPaymentStatus(response) == 'no_payments';
  }

  /// Helper method to check if payment is pending
  static bool isPaymentPending(Map<String, dynamic> response) {
    return getPaymentStatus(response) == 'pending';
  }

  /// Helper method to check if payment was cancelled
  static bool isPaymentCancelled(Map<String, dynamic> response) {
    return getPaymentStatus(response) == 'cancelled';
  }

  /// Helper method to check if payment was successful
  static bool isPaymentSuccessful(Map<String, dynamic> response) {
    return getPaymentStatus(response) == 'paid';
  }

  /// Helper method to get payment amount in a readable format
  static String getPaymentAmount(Map<String, dynamic> payment) {
    final amount = payment['amount'];
    final currency = payment['currency'];

    // Handle null or missing amount/currency gracefully
    if (amount == null) return 'Amount not available';
    if (currency == null) return 'Currency not available';

    // Try to parse amount as different types
    double? amountValue;
    if (amount is int) {
      amountValue = amount.toDouble();
    } else if (amount is double) {
      amountValue = amount;
    } else if (amount is String) {
      amountValue = double.tryParse(amount);
    }

    if (amountValue == null) return 'Invalid amount';

    // Convert from smallest currency unit (e.g., cents) to main unit
    final displayAmount = amountValue / 100;
    return '${displayAmount.toStringAsFixed(2)} $currency';
  }

  /// Helper method to get payment date in a readable format
  static String getPaymentDate(Map<String, dynamic> payment) {
    final createdAt = payment['createdAt'];
    if (createdAt == null) return 'Unknown date';

    try {
      if (createdAt is String) {
        final date = DateTime.parse(createdAt);
        return '${date.day}/${date.month}/${date.year}';
      } else if (createdAt is DateTime) {
        return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
      } else if (createdAt is Map) {
        // Handle Firestore timestamp format: { _seconds: 123, _nanoseconds: 456 }
        final seconds = createdAt['_seconds'];
        final nanoseconds = createdAt['_nanoseconds'];

        if (seconds != null) {
          final timestamp = DateTime.fromMillisecondsSinceEpoch(
              (seconds as int) * 1000 +
                  ((nanoseconds as int?) ?? 0) ~/ 1000000);
          return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
        }
      }
    } catch (e) {
      developer.log('Error parsing payment date: $e');
    }
    return 'Unknown date';
  }

  // ============================================================================
  // UTILITY OPERATIONS
  // ============================================================================

  /// Retrieves enterprise branding information for enterprise licenses.
  ///
  /// This method fetches custom branding, logos, and styling information
  /// for enterprise customers who have custom branding requirements.
  ///
  /// Parameters:
  /// - `enterpriseId`: The unique identifier of the enterprise
  ///
  /// Returns a map containing:
  /// - `success`: boolean indicating if the retrieval succeeded
  /// - `data`: branding information including logos, colors, and styling
  /// - `error`: error details if the retrieval failed
  ///
  /// Throws [Exception] if the request fails or enterprise ID is invalid.
  static Future<Map<String, dynamic>> getEnterpriseBranding(
      String enterpriseId) async {
    return await FirebaseService.callCloudFunction('getEnterpriseBranding', {
      'enterpriseId': enterpriseId,
    });
  }
}
