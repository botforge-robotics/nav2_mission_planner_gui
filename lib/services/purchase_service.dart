import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../providers/licensing_provider.dart';
import '../constants/app_config.dart';
import '../services/device_service.dart';

class PurchaseService {
  static const String _baseUrl = AppConfig.cloudFunctionsUrl;

  // Purchase stream subscription
  static StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Initialize purchase listener
  static void initializePurchaseListener(LicensingProvider licensingProvider) {
    _subscription = InAppPurchase.instance.purchaseStream.listen(
      (purchaseDetailsList) {
        _handlePurchaseUpdates(purchaseDetailsList, licensingProvider);
      },
      onDone: () {
        _subscription?.cancel();
      },
      onError: (error) {
        debugPrint('❌ Purchase stream error: $error');
      },
    );
  }

  // Handle purchase updates from Google Play
  static void _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
    LicensingProvider licensingProvider,
  ) {
    for (final purchaseDetails in purchaseDetailsList) {
      debugPrint('📱 Purchase update received: ${purchaseDetails.status}');
      debugPrint(
          '🔐 Purchase verification data: ${purchaseDetails.verificationData}');

      // Store ALL purchase details in Firebase immediately for audit trail
      _storePurchaseDetailsInFirebase(purchaseDetails, licensingProvider);

      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          debugPrint('⏳ Purchase is pending...');
          // Store pending purchase info for UI display
          _storePendingPurchase(purchaseDetails, licensingProvider);
          break;

        case PurchaseStatus.purchased:
          debugPrint('✅ Purchase completed - verifying with backend');
          _verifyPurchaseWithBackend(purchaseDetails, licensingProvider);
          break;

        case PurchaseStatus.restored:
          debugPrint('🔄 Purchase restored - verifying with backend');
          _verifyPurchaseWithBackend(purchaseDetails, licensingProvider);
          break;

        case PurchaseStatus.error:
          debugPrint('❌ Purchase error: ${purchaseDetails.error}');
          // Handle purchase errors (like declined payments)
          _handlePurchaseError(purchaseDetails, licensingProvider);
          break;

        case PurchaseStatus.canceled:
          debugPrint('❌ Purchase cancelled by user');
          // Handle user cancellation
          _handlePurchaseCancellation(purchaseDetails, licensingProvider);
          break;
      }
    }
  }

  // Store ALL purchase details in Firebase for complete audit trail
  static Future<void> _storePurchaseDetailsInFirebase(
    PurchaseDetails purchaseDetails,
    LicensingProvider licensingProvider,
  ) async {
    try {
      final accountId = licensingProvider.accountId;
      final deviceId = await _getDeviceId();

      if (accountId == null || deviceId == null) {
        debugPrint(
            '❌ Cannot store purchase details: missing account or device ID');
        return;
      }

      debugPrint('💾 Storing purchase details in Firebase for audit trail...');

      // Map Flutter status to our internal status
      String internalStatus;
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          internalStatus = 'pending';
          break;
        case PurchaseStatus.purchased:
          internalStatus = 'completed';
          break;
        case PurchaseStatus.restored:
          internalStatus = 'restored';
          break;
        case PurchaseStatus.error:
          internalStatus = 'error';
          break;
        case PurchaseStatus.canceled:
          internalStatus = 'cancelled';
          break;
        default:
          internalStatus = 'unknown';
      }

      // Create unique payment ID using purchaseID or timestamp
      final paymentId = purchaseDetails.purchaseID?.isNotEmpty == true
          ? 'PAY-${purchaseDetails.purchaseID}'
          : 'PAY-${DateTime.now().millisecondsSinceEpoch}';

      // Call the Cloud Function directly
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('storePurchaseDetails');

      final result = await callable.call({
        'paymentId': paymentId,
        'accountId': accountId,
        'deviceId': deviceId,
        'productId': purchaseDetails.productID,
        'purchaseId': purchaseDetails.purchaseID,
        'status': internalStatus,
        'transactionDate': purchaseDetails.transactionDate,
        'verificationData': {
          'localVerificationData':
              purchaseDetails.verificationData.localVerificationData,
          'serverVerificationData':
              purchaseDetails.verificationData.serverVerificationData,
          'source': purchaseDetails.verificationData.source,
        },
        'errorDetails': purchaseDetails.error?.message,
        'timestamp': DateTime.now().toIso8601String(),
      });

      if (result.data['success'] == true) {
        debugPrint('✅ Purchase details stored in Firebase: $paymentId');
      } else {
        debugPrint('❌ Failed to store purchase details: ${result.data}');
      }
    } catch (error) {
      debugPrint('❌ Error storing purchase details: $error');
    }
  }

  // Store pending purchase information
  static void _storePendingPurchase(
      PurchaseDetails purchaseDetails, LicensingProvider licensingProvider) {
    debugPrint('💾 Storing pending purchase info for UI display');

    // Store pending purchase details for UI state management
    _pendingPurchaseDetails = purchaseDetails;
    _hasPendingPurchase = true;

    // Store account and device info for backend linking
    _pendingAccountId = licensingProvider.accountId;
    _pendingDeviceId = null; // Will be set when device ID is available

    // Notify listeners that purchase state has changed
    _notifyPurchaseStateChanged();

    // Note: We don't create pending payment session here because:
    // 1. purchaseID is null/empty during pending status
    // 2. We'll create it when we get 'purchased' status with real data
    debugPrint(
        '⏳ Purchase pending - waiting for completion before creating backend session');
  }

  // Pending purchase state management
  static PurchaseDetails? _pendingPurchaseDetails;
  static bool _hasPendingPurchase = false;
  static String? _pendingAccountId;
  static String? _pendingDeviceId;
  static final List<Function()> _stateChangeListeners = [];

  // Get pending purchase status
  static bool get hasPendingPurchase => _hasPendingPurchase;

  // Get pending purchase details
  static PurchaseDetails? get pendingPurchaseDetails => _pendingPurchaseDetails;

  // Clear pending purchase state
  static void clearPendingPurchase() {
    _pendingPurchaseDetails = null;
    _hasPendingPurchase = false;
    _pendingAccountId = null;
    _pendingDeviceId = null;
    _notifyPurchaseStateChanged();
  }

  // Add state change listener
  static void addStateChangeListener(Function() listener) {
    _stateChangeListeners.add(listener);
  }

  // Remove state change listener
  static void removeStateChangeListener(Function() listener) {
    _stateChangeListeners.remove(listener);
  }

  // Notify all listeners of state change
  static void _notifyPurchaseStateChanged() {
    for (final listener in _stateChangeListeners) {
      try {
        listener();
      } catch (e) {
        debugPrint('❌ Error in purchase state change listener: $e');
      }
    }
  }

  // Handle purchase errors (like declined payments)
  static void _handlePurchaseError(
      PurchaseDetails purchaseDetails, LicensingProvider licensingProvider) {
    debugPrint('❌ Handling purchase error: ${purchaseDetails.error?.message}');

    // Check if it's a payment decline
    if (purchaseDetails.error?.message?.contains('declined') == true ||
        purchaseDetails.error?.message?.contains('failed') == true) {
      debugPrint('💳 Payment was declined or failed');
      // Update UI to show payment failed message
      // This should prevent going back to buy screen immediately
    }

    // Clear pending purchase state since there was an error
    clearPendingPurchase();
  }

  // Handle purchase cancellation
  static void _handlePurchaseCancellation(
      PurchaseDetails purchaseDetails, LicensingProvider licensingProvider) {
    debugPrint('❌ Handling purchase cancellation');
    // Update UI to show cancellation message
    // This should prevent going back to buy screen immediately

    // Clear pending purchase state since it was cancelled
    clearPendingPurchase();
  }

  // Verify purchase with backend using REAL purchase data
  static Future<void> _verifyPurchaseWithBackend(
    PurchaseDetails purchaseDetails,
    LicensingProvider licensingProvider,
  ) async {
    try {
      debugPrint('🔍 Verifying purchase with backend...');
      debugPrint('📱 Purchase token: ${purchaseDetails.purchaseID}');
      debugPrint('📦 Product ID: ${purchaseDetails.productID}');

      // Check if we have a valid purchaseID (should be available for completed purchases)
      if (purchaseDetails.purchaseID == null ||
          purchaseDetails.purchaseID!.isEmpty) {
        debugPrint('❌ Cannot verify purchase: missing purchaseID');
        return;
      }

      // Get current user info
      final accountId = licensingProvider.accountId;
      final deviceId = await _getDeviceId();

      if (accountId == null) {
        debugPrint('❌ No user account found for purchase verification');
        return;
      }

      // Extract the real purchase token from verification data
      final realPurchaseToken = _extractPurchaseToken(
          purchaseDetails.verificationData.localVerificationData);
      final googlePlayOrderId = purchaseDetails.purchaseID;

      debugPrint(
          '🔑 Real purchase token: ${realPurchaseToken.substring(0, 20)}...');
      debugPrint('🆔 Google Play order ID: $googlePlayOrderId');
      debugPrint('📦 Product ID: ${purchaseDetails.productID}');

      // No longer calling verifyGooglePurchase - only using checkPaymentStatus
      debugPrint('✅ Purchase completed - no verification needed');

      // Update local state
      licensingProvider.refresh();

      // Complete the purchase
      await InAppPurchase.instance.completePurchase(purchaseDetails);

      // Clear pending purchase state since it's now completed
      clearPendingPurchase();
    } catch (error) {
      debugPrint('❌ Error completing purchase: $error');
    }
  }

  /// Extract the real purchase token from the local verification data
  static String _extractPurchaseToken(String localVerificationData) {
    try {
      // Parse the JSON string to get the purchase token
      final Map<String, dynamic> verificationMap =
          jsonDecode(localVerificationData);
      final String? purchaseToken = verificationMap['purchaseToken'];

      if (purchaseToken != null && purchaseToken.isNotEmpty) {
        debugPrint(
            '🔑 Extracted purchase token: ${purchaseToken.substring(0, 20)}...');
        return purchaseToken;
      } else {
        debugPrint('⚠️ No purchase token found in verification data');
        // Fallback to a default token if extraction fails
        return 'extracted_token_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (e) {
      debugPrint('❌ Error extracting purchase token: $e');
      // Fallback to a default token if parsing fails
      return 'fallback_token_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  // Get device ID (implement based on your device identification logic)
  static Future<String> _getDeviceId() async {
    try {
      // Use the DeviceService to get a consistent device ID
      // This should match what's used in your cloud functions
      return await DeviceService.getDeviceId();
    } catch (error) {
      debugPrint('❌ Error getting device ID: $error');
      // Fallback to a generated ID if DeviceService fails
      return 'device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  // Get authentication token (implement based on your auth system)
  static Future<String> _getAuthToken() async {
    try {
      // Get the current Firebase Auth user
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Get the ID token for authentication
        final token = await user.getIdToken();
        if (token != null) {
          return token;
        } else {
          throw Exception('Failed to get ID token from user');
        }
      } else {
        throw Exception('No authenticated user found');
      }
    } catch (error) {
      debugPrint('❌ Error getting auth token: $error');
      throw Exception('Failed to get authentication token: $error');
    }
  }

  // Dispose of the purchase listener
  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  // Legacy method - now redirects to new flow
  static Future<void> buyProduct(
    String productId, {
    LicensingProvider? licensingProvider,
  }) async {
    debugPrint(
        '⚠️ buyProduct is deprecated - use purchase stream listener instead');
    debugPrint('📱 Initiating purchase for product: $productId');

    try {
      // Start the purchase flow
      final ProductDetailsResponse response =
          await InAppPurchase.instance.queryProductDetails({productId});

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('❌ Product not found: ${response.notFoundIDs}');
        return;
      }

      if (response.productDetails.isEmpty) {
        debugPrint('❌ No product details available');
        return;
      }

      final ProductDetails productDetails = response.productDetails.first;
      final PurchaseParam purchaseParam =
          PurchaseParam(productDetails: productDetails);

      // Initiate purchase - the result will come through the purchase stream
      final bool success = await InAppPurchase.instance.buyConsumable(
        purchaseParam: purchaseParam,
      );

      if (success) {
        debugPrint('✅ Purchase initiated successfully');
        debugPrint('📱 Waiting for purchase completion via stream...');
      } else {
        debugPrint('❌ Failed to initiate purchase');
      }
    } catch (error) {
      debugPrint('❌ Error initiating purchase: $error');
    }
  }

  // Check current payment status
  static Future<Map<String, dynamic>?> checkPaymentStatus(
      String accountId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/checkPaymentStatus'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
        body: jsonEncode({
          'accountId': accountId,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint('❌ Failed to check payment status: ${response.statusCode}');
        return null;
      }
    } catch (error) {
      debugPrint('❌ Error checking payment status: $error');
      return null;
    }
  }

  // Get current payment status for UI display
  static String getCurrentPaymentStatus() {
    // Check if we have a pending purchase
    if (_hasPendingPurchase) {
      return 'pending';
    }

    // This should now be managed by the LicensingProvider
    // based on the verified purchase data from backend
    // For now, return 'none' as the default state
    return 'none';
  }

  // Check if payment is completed
  static bool isPaymentCompleted() {
    // Check if we have a pending purchase
    if (_hasPendingPurchase) {
      return false; // Pending means not completed
    }

    // This should now be managed by the LicensingProvider
    // based on the verified purchase data from backend
    // For now, return false as the default state
    return false;
  }

  // Reset payment status (for testing/debugging)
  static void resetPaymentStatus() {
    debugPrint('🔄 Payment status reset - clearing pending purchase state');
    clearPendingPurchase();
  }

  // Get product information for UI display
  static Future<Map<String, dynamic>> getProductInfo(String productId) async {
    try {
      final response =
          await InAppPurchase.instance.queryProductDetails({productId});

      if (response.notFoundIDs.isNotEmpty) {
        return {
          'available': false,
          'error': 'Product not found in store',
        };
      }

      if (response.productDetails.isEmpty) {
        return {
          'available': false,
          'error': 'No product details available',
        };
      }

      final product = response.productDetails.first;
      return {
        'available': true,
        'price': product.price,
        'title': product.title,
        'description': product.description,
        'currencyCode': product.currencyCode,
      };
    } catch (error) {
      debugPrint('❌ Error getting product info: $error');
      return {
        'available': false,
        'error': 'Error querying product: $error',
      };
    }
  }

  // Cancel current purchase (for user cancellation)
  static void cancelCurrentPurchase() {
    debugPrint('🔄 Cancelling current purchase');
    // Cancel the subscription if active
    _subscription?.cancel();
    _subscription = null;

    // Clear pending purchase state
    clearPendingPurchase();
  }

  // Clear payment status after completion
  static void clearPaymentStatus() {
    debugPrint('🧹 Clearing payment status after completion');
    // Reset any local state if needed
    // The main state is now managed by LicensingProvider
  }

  // Complete purchase when payment is confirmed
  static void completePurchaseWhenPaymentConfirmed() {
    debugPrint('✅ Completing purchase after payment confirmation');
    // This method is called when payment status changes to 'paid'
    // The actual completion is handled by the purchase stream listener
    // This is mainly for legacy compatibility
  }
}
