import 'package:flutter/material.dart';
import '../services/licensing_service.dart';
import '../services/secure_storage_service.dart';

enum LicenseGateState {
  loading,
  noLicense,
  trialActive,
  trialExpired,
  licenseActive,
  linkedToOtherDevice,
  licenseRevoked,
  error,
}

class LicensingProvider extends ChangeNotifier {
  LicenseGateState state = LicenseGateState.loading;
  String? statusMessage;
  String? linkedDeviceId;
  String? licenseType;
  String? enterpriseId;
  DateTime? offlineAllowedUntil;
  DateTime? trialEndTime;

  Future<void> refresh() async {
    print('🔄 LicensingProvider.refresh() called');
    state = LicenseGateState.loading;
    statusMessage = null;
    notifyListeners();
    try {
      print('📞 Calling getLicenseStatus...');
      final response = await LicensingService.getLicenseStatus();
      print('📊 Raw response: $response');
      if (response['success'] == true) {
        final rawData = response['data'];
        final Map<String, dynamic> data = rawData is Map
            ? rawData.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{};
        print('📋 Processed data: $data');
        final status = data['status'] as String?;
        print('🏷️ License status: $status');
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
        print('🔍 Processing status: $status');
        switch (status) {
          case 'no_license':
            print('❌ Setting state to noLicense');
            state = LicenseGateState.noLicense;
            break;
          case 'trial_active':
            trialEndTime = DateTime.tryParse(data['trialEndTime'] ?? '');
            print('🆓 Setting state to trialActive');
            state = LicenseGateState.trialActive;
            break;
          case 'trial_expired':
            print('⏰ Setting state to trialExpired');
            state = LicenseGateState.trialExpired;
            break;
          case 'license_active':
            print('✅ Setting state to licenseActive');
            state = LicenseGateState.licenseActive;
            break;
          case 'linked_to_other_device':
            linkedDeviceId = data['linkedDeviceId'];
            print('🔗 Setting state to linkedToOtherDevice');
            state = LicenseGateState.linkedToOtherDevice;
            break;
          case 'license_revoked':
            print('🚫 Setting state to licenseRevoked');
            state = LicenseGateState.licenseRevoked;
            break;
          default:
            // Treat unknown status as no license instead of error to avoid user being stuck
            print('❓ Unknown status, treating as noLicense');
            state = LicenseGateState.noLicense;
        }
        print('🎯 Final state: $state');
        // cache minimal summary for offline gate
        await SecureStorageService.storeLicenseSummary(
          status: status ?? 'error',
          licenseType: licenseType,
          enterpriseId: enterpriseId,
          offlineAllowedUntil: offlineAllowedUntil?.toIso8601String(),
          trialEndTime: trialEndTime?.toIso8601String(),
        );
        print('💾 License summary cached, notifying listeners...');
        statusMessage = null;
        notifyListeners();
        print('🔔 Listeners notified');
      } else {
        print('❌ API call failed: ${response['error']}');
        final usedCache = await _fallbackFromCacheIfValid();
        if (!usedCache) {
          state = LicenseGateState.error;
          statusMessage = response['error']?['message'];
          notifyListeners();
        }
      }
    } catch (e) {
      print('💥 Exception in refresh: $e');
      final usedCache = await _fallbackFromCacheIfValid();
      if (!usedCache) {
        state = LicenseGateState.error;
        statusMessage = e.toString();
        notifyListeners();
      }
    }
  }

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

  // Attempt to use cached license summary if still within offline grace period
  // Method to set license as active directly from purchase flow
  // This is used when skipping server verification for purchases
  Future<void> setLicenseActive({
    required String licenseType,
    required String productId,
    String? enterpriseId,
  }) async {
    print('🔑 Setting license active directly: $licenseType');

    // Set state to license active immediately for UI responsiveness
    print('🔑 Setting state to LicenseGateState.licenseActive');
    final oldState = state;
    state = LicenseGateState.licenseActive;
    print('🔑 State changed from $oldState to: $state');
    print('🔑 State comparison: ${state == LicenseGateState.licenseActive}');

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
    print('✅ License set to active for $licenseType');

    // Ensure UI has time to process the state change
    await Future.delayed(const Duration(milliseconds: 200));

    // Final notification to ensure UI updates
    notifyListeners();

    // Do Firebase refresh in background after a longer delay to ensure server has updated
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        print('🔄 Starting background Firebase refresh...');
        await refresh();
        print('✅ Background Firebase refresh completed');
      } catch (e) {
        print(
            '⚠️ Background Firebase refresh failed, but license is still active: $e');
        // Even if Firebase refresh fails, the license is still active locally
        // The user can continue using the app
      }
    });
  }

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
        print('🛟 Using cached license state due to network issue: $state');
        statusMessage = null;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }
}
