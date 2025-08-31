import 'package:flutter/material.dart';
import '../services/licensing_service.dart';
import '../services/secure_storage_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Represents the different states of the license gate system.
///
/// These states determine what UI is shown to the user and what actions
/// are available based on their current license status.
enum LicenseGateState {
  /// Initial loading state while checking license status
  loading,

  /// User has no active license or trial
  noLicense,

  /// User has an active trial period
  trialActive,

  /// User's trial period has expired
  trialExpired,

  /// User has an active paid license
  licenseActive,

  /// License is active on another device
  linkedToOtherDevice,

  /// License has been revoked by the system
  licenseRevoked,

  /// Payment is pending processing
  paymentPending,

  /// An error occurred while checking license status
  error,
}

/// Provider responsible for managing the application's licensing state and operations.
///
/// This provider handles all licensing-related logic including:
/// - License status checking and caching
/// - Trial management
/// - License activation and deactivation
/// - Device linking and transfer
/// - Offline grace period management
///
/// The provider maintains the current license state and notifies listeners
/// when the state changes, allowing the UI to update accordingly.
class LicensingProvider extends ChangeNotifier {
  // ============================================================================
  // STATE PROPERTIES
  // ============================================================================

  /// Current state of the license gate
  LicenseGateState state = LicenseGateState.loading;

  /// Human-readable message describing the current status or error
  String? statusMessage;

  /// ID of the device where the license is currently linked (if applicable)
  String? linkedDeviceId;

  /// Type of license (e.g., 'individual', 'enterprise', 'trial')
  String? licenseType;

  /// Enterprise identifier for enterprise licenses
  String? enterpriseId;

  /// Timestamp until which offline access is allowed
  DateTime? offlineAllowedUntil;

  /// Timestamp when the trial period ends
  DateTime? trialEndTime;

  // ============================================================================
  // CONSTRUCTOR AND DISPOSAL
  // ============================================================================

  /// Constructor that sets up authentication state listener
  LicensingProvider() {
    // Listen to authentication state changes
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        debugPrint('🔐 User signed in, refreshing license status');
        // User signed in - refresh license status if already initialized
        if (state != LicenseGateState.loading) {
          refresh();
        } else {
          debugPrint('⏳ Provider not initialized yet, will refresh when ready');
        }
      } else {
        debugPrint('🔓 User signed out, setting state to noLicense');
        // User signed out - set to no license
        state = LicenseGateState.noLicense;
        statusMessage = 'Please sign in to continue';
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    // Clean up any resources if needed
    super.dispose();
  }

  // ============================================================================
  // CORE STATE MANAGEMENT
  // ============================================================================

  /// Gets the current user's Firebase account ID.
  ///
  /// Returns the UID of the currently authenticated Firebase user,
  /// or null if no user is authenticated or an error occurs.
  String? get accountId {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (e) {
      debugPrint('⚠️ Error getting account ID: $e');
      return null;
    }
  }

  /// Signs out the current user and resets the licensing state.
  ///
  /// This method should be called when the user explicitly signs out
  /// to ensure the licensing state is properly reset.
  Future<void> signOut() async {
    debugPrint('🔓 LicensingProvider.signOut() called');

    // Reset all licensing state
    state = LicenseGateState.noLicense;
    statusMessage = 'Please sign in to continue';
    linkedDeviceId = null;
    licenseType = null;
    enterpriseId = null;
    offlineAllowedUntil = null;
    trialEndTime = null;

    // Clear cached data
    await SecureStorageService.clearLicenseSummary();

    // Notify listeners
    notifyListeners();

    debugPrint('✅ Licensing state reset after sign out');
  }

  // ============================================================================
  // INITIALIZATION AND REFRESH OPERATIONS
  // ============================================================================

  /// Initializes the licensing provider by loading cached data and refreshing status.
  ///
  /// This method is called when the app starts to:
  /// 1. Load any cached license information
  /// 2. Attempt to refresh the license status from the server
  /// 3. Fall back to cached data if the refresh fails
  ///
  /// The method prioritizes cached data for offline functionality while
  /// attempting to get the latest status from the server.
  Future<void> initialize() async {
    debugPrint('🚀 LicensingProvider.initialize() called');

    // Check if user is authenticated first
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('⚠️ User not authenticated, setting state to noLicense');
      state = LicenseGateState.noLicense;
      statusMessage = 'Please sign in to continue';
      notifyListeners();
      return;
    }

    // User is authenticated, try to load from cache first
    final usedCache = await tryLoadFromCache();

    try {
      // Attempt to refresh from server
      await refresh();
    } catch (e) {
      debugPrint('⚠️ Failed to refresh license status: $e');
      if (!usedCache) {
        // If we have no cache and refresh failed, set error state
        state = LicenseGateState.error;
        statusMessage = 'Failed to check license status. Please try again.';
        notifyListeners();
        rethrow;
      }
      // If we have cache, continue with cached data
      debugPrint('✅ Using cached license data as fallback');
    }
  }

  /// Refreshes the license status from the server and updates the local state.
  ///
  /// This is the primary method for checking the current license status.
  /// It:
  /// 1. Sets the state to loading
  /// 2. Calls the licensing service to get current status
  /// 3. Updates local state based on the response
  /// 4. Caches the license summary for offline use
  /// 5. Notifies listeners of state changes
  ///
  /// If the server call fails, it attempts to use cached data as a fallback.
  Future<void> refresh() async {
    debugPrint('🔄 LicensingProvider.refresh() called');
    state = LicenseGateState.loading;
    statusMessage = null;
    notifyListeners();
    try {
      debugPrint('📞 Calling getLicenseStatus...');
      final response = await LicensingService.getLicenseStatus();
      debugPrint('📊 Raw response: $response');
      if (response['success'] == true) {
        final rawData = response['data'];
        final Map<String, dynamic> data = rawData is Map
            ? rawData.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{};
        debugPrint('📋 Processed data: $data');
        final status = data['status'] as String?;
        debugPrint('🏷️ License status: $status');
        final offlineStr = data['offlineAllowedUntil'] as String?;
        if (offlineStr != null) {
          offlineAllowedUntil = DateTime.tryParse(offlineStr);
        }
        // If server didn't include offlineAllowedUntil, grant 24h grace after any successful check
        offlineAllowedUntil ??= DateTime.now().add(const Duration(days: 1));
        // Cache trial end if present
        final trialStr = data['trialEndTime'] as String?;
        if (trialStr != null) {
          trialEndTime = DateTime.tryParse(trialStr);
        }
        if (data['enterpriseId'] != null) enterpriseId = data['enterpriseId'];
        licenseType = data['licenseType'];
        debugPrint('🔍 Processing status: $status');
        switch (status) {
          case 'no_license':
            debugPrint('❌ Setting state to noLicense');
            state = LicenseGateState.noLicense;
            break;
          case 'trial_active':
            trialEndTime = DateTime.tryParse(data['trialEndTime'] ?? '');
            debugPrint('🆓 Setting state to trialActive');
            state = LicenseGateState.trialActive;
            break;
          case 'trial_expired':
            debugPrint('⏰ Setting state to trialExpired');
            // Check if there are any pending payments before showing trial expired
            await _checkForPendingPayments();
            break;
          case 'license_active':
            debugPrint('✅ Setting state to licenseActive');
            state = LicenseGateState.licenseActive;
            break;
          case 'linked_to_other_device':
            linkedDeviceId = data['linkedDeviceId'];
            debugPrint('🔗 Setting state to linkedToOtherDevice');
            state = LicenseGateState.linkedToOtherDevice;
            break;
          case 'license_revoked':
            debugPrint('🚫 Setting state to licenseRevoked');
            state = LicenseGateState.licenseRevoked;
            break;
          default:
            // Treat unknown status as no license instead of error to avoid user being stuck
            debugPrint('❓ Unknown status, treating as noLicense');
            state = LicenseGateState.noLicense;
        }
        debugPrint('🎯 Final state: $state');
        // cache minimal summary for offline gate
        await SecureStorageService.storeLicenseSummary(
          status: status ?? 'error',
          licenseType: licenseType,
          enterpriseId: enterpriseId,
          offlineAllowedUntil: offlineAllowedUntil?.toIso8601String(),
          trialEndTime: trialEndTime?.toIso8601String(),
        );
        debugPrint('💾 License summary cached, notifying listeners...');
        statusMessage = null;
        notifyListeners();
        debugPrint('🔔 Listeners notified');
      } else {
        debugPrint('❌ API call failed: ${response['error']}');
        final usedCache = await _fallbackFromCacheIfValid();
        if (!usedCache) {
          state = LicenseGateState.error;
          statusMessage = response['error']?['message'];
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('💥 Exception in refresh: $e');
      final usedCache = await _fallbackFromCacheIfValid();
      if (!usedCache) {
        state = LicenseGateState.error;
        statusMessage = e.toString();
        notifyListeners();
      }
    }
  }

  // ============================================================================
  // LICENSE OPERATIONS
  // ============================================================================

  /// Transfers a license from another device to the current device.
  ///
  /// This method is used when a user wants to move their license to a new device.
  /// It:
  /// 1. Sets the state to loading
  /// 2. Calls the licensing service to transfer the license
  /// 3. Sets the license as active immediately for UI responsiveness
  /// 4. Refreshes the license status after a delay to ensure server consistency
  /// 5. Handles any errors that occur during the transfer
  ///
  /// Parameters:
  /// - `newDeviceId`: The unique identifier of the current device
  ///
  /// Throws [Exception] if the transfer fails or the user is not authenticated.
  Future<void> transferLicense(String newDeviceId) async {
    debugPrint(
        '📲 LicensingProvider.transferLicense(newDeviceId: $newDeviceId)');
    state = LicenseGateState.loading;
    statusMessage = null;
    notifyListeners();
    try {
      final res = await LicensingService.transferLicense(
        newDeviceId: newDeviceId,
      );
      if (res['success'] == true) {
        debugPrint(
            '✅ License transfer successful, setting as active immediately');

        // Set license as active immediately for UI responsiveness
        // This prevents the user from seeing the "linked to other device" screen again
        final transferData = res['data'] as Map<String, dynamic>?;
        final licenseType = transferData?['licenseType'] ?? 'individual';
        final enterpriseId = transferData?['enterpriseId'];

        // Set state to license active immediately
        state = LicenseGateState.licenseActive;
        this.licenseType = licenseType;
        this.enterpriseId = enterpriseId;

        // Set offline allowed until 24 hours from now
        offlineAllowedUntil = DateTime.now().add(const Duration(days: 1));

        // Cache license summary
        await SecureStorageService.storeLicenseSummary(
          status: 'license_active',
          licenseType: licenseType,
          enterpriseId: enterpriseId,
          offlineAllowedUntil: offlineAllowedUntil?.toIso8601String(),
          trialEndTime: null,
        );

        // Notify listeners immediately
        statusMessage = null;
        notifyListeners();

        debugPrint(
            '🔑 License set to active after transfer, refreshing from server in background');

        // Refresh from server after a delay to ensure consistency
        // This allows the server to fully process the transfer
        Future.delayed(const Duration(seconds: 2), () async {
          try {
            await refresh();
          } catch (e) {
            debugPrint('⚠️ Background refresh after transfer failed: $e');
            // Don't change the UI state if background refresh fails
            // The license is already active locally
          }
        });
      } else {
        statusMessage = res['error']?['message'] ?? 'License transfer failed';
        await refresh();
      }
    } catch (e) {
      statusMessage = e.toString();
      await refresh();
    }
  }

  /// Sets the license as active directly from the purchase flow.
  ///
  /// This method is used when skipping server verification for purchases
  /// to provide immediate UI responsiveness. It:
  /// 1. Sets the state to license active immediately
  /// 2. Updates license properties
  /// 3. Sets offline grace period
  /// 4. Caches the license summary
  /// 5. Notifies listeners
  /// 6. Refreshes from server to ensure consistency
  ///
  /// Parameters:
  /// - `licenseType`: The type of license being activated
  /// - `productId`: The product identifier for the license
  /// - `enterpriseId`: Optional enterprise identifier for enterprise licenses
  ///
  /// Throws [Exception] if the license cannot be set or cached.
  Future<void> setLicenseActive({
    required String licenseType,
    required String productId,
    String? enterpriseId,
  }) async {
    debugPrint('🔑 Setting license active directly: $licenseType');

    // Set state to license active immediately for UI responsiveness
    debugPrint('🔑 Setting state to LicenseGateState.licenseActive');
    final oldState = state;
    state = LicenseGateState.licenseActive;
    debugPrint('🔑 State changed from $oldState to: $state');
    debugPrint(
        '🔑 State comparison: ${state == LicenseGateState.licenseActive}');

    // Set license properties
    this.licenseType = licenseType;
    this.enterpriseId = enterpriseId;

    // Set offline allowed until 24 hours from now
    offlineAllowedUntil = DateTime.now().add(const Duration(days: 1));

    // Cache license summary
    await SecureStorageService.storeLicenseSummary(
      status: 'license_active',
      licenseType: licenseType,
      enterpriseId: enterpriseId,
      offlineAllowedUntil: offlineAllowedUntil?.toIso8601String(),
      trialEndTime: null,
    );

    // Notify listeners immediately
    statusMessage = null;
    notifyListeners();
    debugPrint('✅ License set to active for $licenseType');

    // No hardcoded delays per spec - process immediately
    // await Future.delayed(const Duration(milliseconds: 200)); - REMOVED

    // Refresh license status from Firebase
    await refresh();
  }

  // ============================================================================
  // CACHE AND OFFLINE OPERATIONS
  // ============================================================================

  /// Attempts to load license information from cached data.
  ///
  /// This method checks if there's valid cached license data and if the
  /// offline grace period is still active. If valid data is found, it
  /// updates the local state and returns true.
  ///
  /// Returns true if valid cached data was loaded, false otherwise.
  ///
  /// This method is used during initialization and as a fallback when
  /// network requests fail.
  Future<bool> tryLoadFromCache() async {
    final summary = await SecureStorageService.getLicenseSummary();
    if (summary == null) return false;
    final offlineStr = summary['offlineAllowedUntil'] as String?;
    if (offlineStr == null) return false;
    final until = DateTime.tryParse(offlineStr);
    if (until != null && DateTime.now().isBefore(until)) {
      final status = summary['status'] as String?;
      if (status == 'license_active') {
        state = LicenseGateState.licenseActive;
      } else if (status == 'trial_active') {
        state = LicenseGateState.trialActive;
      } else {
        return false;
      }
      offlineAllowedUntil = until;
      licenseType = summary['licenseType'];
      enterpriseId = summary['enterpriseId'];
      // For trial badge support: attempt to read cached trialEndTime if present
      final trialStr = summary['trialEndTime'] as String?;
      if (trialStr != null) {
        trialEndTime = DateTime.tryParse(trialStr);
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Attempts to use cached license summary if still within offline grace period.
  ///
  /// This is a fallback method used when network requests fail. It checks
  /// if cached data is still valid and updates the state accordingly.
  ///
  /// Returns true if cached data was successfully used, false otherwise.
  ///
  /// This method is called internally by [refresh] when the server request fails.
  Future<bool> _fallbackFromCacheIfValid() async {
    try {
      final summary = await SecureStorageService.getLicenseSummary();
      if (summary == null) return false;
      final offlineStr = summary['offlineAllowedUntil'] as String?;
      if (offlineStr == null) return false;
      final until = DateTime.tryParse(offlineStr);
      if (until != null && DateTime.now().isBefore(until)) {
        final cachedStatus = summary['status'] as String?;
        if (cachedStatus == 'license_active') {
          state = LicenseGateState.licenseActive;
        } else if (cachedStatus == 'trial_active') {
          state = LicenseGateState.trialActive;
        } else {
          return false;
        }
        offlineAllowedUntil = until;
        licenseType = summary['licenseType'] as String?;
        enterpriseId = summary['enterpriseId'] as String?;
        final trialStr = summary['trialEndTime'] as String?;
        if (trialStr != null) {
          trialEndTime = DateTime.tryParse(trialStr);
        }
        debugPrint(
            '🛟 Using cached license state due to network issue: $state');
        statusMessage = null;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Checks if there are any pending payments for the current user.
  /// If pending payments are found, sets the state to paymentPending.
  /// Otherwise, sets the state to trialExpired.
  Future<void> _checkForPendingPayments() async {
    try {
      final accountId = this.accountId;
      if (accountId == null) {
        debugPrint('⚠️ No account ID available for payment check');
        state = LicenseGateState.trialExpired;
        notifyListeners();
        return;
      }

      debugPrint('🔍 Checking for pending payments for account: $accountId');

      // Call the checkPaymentStatus Cloud Function
      final response = await LicensingService.checkPaymentStatus();

      if (response['success'] == true) {
        final paymentStatus = response['data']?['paymentStatus'];
        final latestPayment = response['data']?['latestPayment'];

        debugPrint('📊 Payment status check result: $paymentStatus');

        if (paymentStatus == 'pending' && latestPayment != null) {
          debugPrint(
              '⏳ Pending payment found, setting state to paymentPending');
          state = LicenseGateState.paymentPending;
          statusMessage = 'Payment is being processed. Please wait...';
        } else {
          debugPrint('✅ No pending payments, setting state to trialExpired');
          state = LicenseGateState.trialExpired;
        }
      } else {
        debugPrint(
            '⚠️ Payment status check failed, defaulting to trialExpired');
        state = LicenseGateState.trialExpired;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error checking pending payments: $e');
      // Fall back to trial expired if payment check fails
      state = LicenseGateState.trialExpired;
      notifyListeners();
    }
  }
}
