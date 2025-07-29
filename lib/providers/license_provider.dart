import 'package:flutter/foundation.dart';
import '../models/license_model.dart';
import '../services/device_service.dart';
import '../services/secure_storage_service.dart';
import '../services/trial_service.dart';
import '../services/license_verification_service.dart';
import '../services/api_service.dart';
import '../providers/branding_provider.dart';

class LicenseProvider extends ChangeNotifier {
  LicenseStatus _status = LicenseStatus.checking;
  String? _errorMessage;
  LicenseData? _licenseData;
  TrialData? _trialData;
  BrandingProvider? _brandingProvider;

  // Prevent multiple simultaneous license checks
  static bool _isChecking = false;

  // Getters
  LicenseStatus get status => _status;
  String? get errorMessage => _errorMessage;
  LicenseData? get licenseData => _licenseData;
  TrialData? get trialData => _trialData;

  // Set branding provider reference
  void setBrandingProvider(BrandingProvider brandingProvider) {
    _brandingProvider = brandingProvider;
  }

  // Enhanced license check: cloud-first, every launch, grace periods, cloud data priority
  Future<void> checkLicense() async {
    if (_isChecking) return;
    _isChecking = true;
    _status = LicenseStatus.checking;
    _errorMessage = null;
    notifyListeners();
    try {
      // First, check for stored license data (both token and license data)
      final token = await SecureStorageService.getLicenseToken();
      final localLicenseData = await SecureStorageService.getLicenseData();

      // If we have license data stored, prioritize it over trial
      if (token != null || localLicenseData != null) {
        final isOnline = await _isOnline();
        final now = DateTime.now();
        bool cloudChecked = false;

        // Try cloud verification if online
        if (isOnline && token != null) {
          try {
            final deviceId = await DeviceService.getDeviceId();
            final response = await ApiService.verifyLicense(
                deviceId: deviceId, token: token);
            await SecureStorageService.storeLastLicenseCheck(now);
            cloudChecked = true;

            if (response['statusCode'] == 200 &&
                response['body']['licenseVerified'] == true) {
              // Parse and store the license data
              final licenseData = _parseLicenseResponse(response['body']);
              await SecureStorageService.storeLicenseData(licenseData);

              // Handle organization branding
              if (licenseData.licenseType == 'organization') {
                await SecureStorageService.storeOrganizationBranding(
                    licenseData);
                _brandingProvider?.updateOrganizationBranding(licenseData);
              } else {
                // Clear organization branding for individual licenses
                await SecureStorageService.clearOrganizationBranding();
                _brandingProvider?.clearOrganizationBranding();
              }

              _status = LicenseStatus.valid;
              _licenseData = licenseData;
              _errorMessage = null;
              notifyListeners();
              _isChecking = false;
              return;
            } else {
              await SecureStorageService.deleteLicenseToken();
              await SecureStorageService.deleteLicenseData();
              _status = LicenseStatus.expired;
              _errorMessage =
                  response['body']['message'] ?? 'License verification failed';
              notifyListeners();
              _isChecking = false;
              return;
            }
          } catch (e) {
            // Cloud check failed, fall back to local
          }
        }

        // Use local license data if available (offline or cloud failed)
        if (localLicenseData != null) {
          final lastCheck = await SecureStorageService.getLastLicenseCheck();

          if (lastCheck != null) {
            // Check if we need mandatory online verification (30-day grace period)
            if (!cloudChecked && now.difference(lastCheck).inDays > 30) {
              _status = LicenseStatus.mandatoryCheckRequired;
              _errorMessage = 'License requires online verification';
              notifyListeners();
              _isChecking = false;
              return;
            }
          }

          // Use local license data
          _status = LicenseStatus.valid;
          _licenseData = localLicenseData;

          // Update branding provider with local organization data
          if (localLicenseData.licenseType == 'organization') {
            _brandingProvider?.updateOrganizationBranding(localLicenseData);
          } else {
            _brandingProvider?.clearOrganizationBranding();
          }

          _errorMessage = null;
          notifyListeners();
          _isChecking = false;
          return;
        }

        // If we have token but no local data, and offline, require online verification
        if (token != null && !isOnline) {
          _status = LicenseStatus.mandatoryCheckRequired;
          _errorMessage = 'License requires online verification';
          notifyListeners();
          _isChecking = false;
          return;
        }

        // If we have token but verification failed and no local data
        _status = LicenseStatus.expired;
        _errorMessage = 'No valid license found';
        notifyListeners();
        _isChecking = false;
        return;
      }

      // Only check trial if no license data is available
      // Trial: always check cloud if online, else use local with 1-day grace
      final isOnline = await _isOnline();
      final lastCheck = await SecureStorageService.getLastTrialCheck();
      final trialNow = DateTime.now();
      bool cloudChecked = false;

      if (isOnline) {
        try {
          final deviceId = await DeviceService.getDeviceId();
          final response = await ApiService.getTrialStatus(deviceId);
          await SecureStorageService.storeLastTrialCheck(trialNow);
          cloudChecked = true;
          if (response['statusCode'] == 200 &&
              response['body']['success'] == true) {
            final cloudData = response['body']['data'];
            final cloudTrialStatus = cloudData['trialStatus'];
            final cloudTrialStartTime =
                DateTime.parse(cloudData['trialStartTime']);
            final cloudTrialEndTime = DateTime.parse(cloudData['trialEndTime']);
            await SecureStorageService.storeTrialStartTime(cloudTrialStartTime);
            await SecureStorageService.storeTrialEndTime(cloudTrialEndTime);
            await SecureStorageService.storeDeviceRegistered(true);

            // Always use cloud trial status, regardless of local status
            if (cloudTrialStatus == 'valid') {
              _status = LicenseStatus.welcome;
              _errorMessage = null;
              notifyListeners();
              _isChecking = false;
              return;
            } else {
              _status = LicenseStatus.welcome;
              _errorMessage = 'Trial expired';
              notifyListeners();
              _isChecking = false;
              return;
            }
          }
        } catch (e) {
          // Cloud check failed, fall back to local
        }
      }

      // If no internet and no local trial data, require internet connection
      if (!isOnline) {
        final hasLocalTrialData =
            await SecureStorageService.getTrialStartTime() != null;
        if (!hasLocalTrialData) {
          _status = LicenseStatus.noInternet;
          _errorMessage =
              'Internet connection required to check for existing trial';
          notifyListeners();
          _isChecking = false;
          return;
        }
      }

      // Local fallback - use stored cloud data if available
      final storedEndTime = await SecureStorageService.getTrialEndTime();
      final currentTime = DateTime.now();

      if (storedEndTime != null) {
        // Use stored cloud data
        if (currentTime.isBefore(storedEndTime)) {
          _status = LicenseStatus.welcome;
          _errorMessage = null;
          notifyListeners();
          _isChecking = false;
          return;
        } else {
          _status = LicenseStatus.welcome;
          _errorMessage = 'Trial expired';
          notifyListeners();
          _isChecking = false;
          return;
        }
      }

      // Fallback to old local trial status check only if no cloud data
      final localTrialStatus = await TrialService.checkTrialStatus();

      if (!cloudChecked &&
          lastCheck != null &&
          currentTime.difference(lastCheck).inDays > 1) {
        _status = LicenseStatus.mandatoryCheckRequired;
        _errorMessage = 'Trial requires online verification';
        notifyListeners();
        _isChecking = false;
        return;
      }
      if (localTrialStatus == TrialStatus.active) {
        _status = LicenseStatus.welcome;
        _errorMessage = null;
        notifyListeners();
        _isChecking = false;
        return;
      } else {
        _status = LicenseStatus.welcome;
        _errorMessage = 'Trial expired';
        notifyListeners();
        _isChecking = false;
        return;
      }
    } finally {
      _isChecking = false;
    }
  }

  // Parse license response into LicenseData model
  LicenseData _parseLicenseResponse(Map<String, dynamic> response) {
    final data = response['data'];
    final licenseType = response['licenseType'] ?? 'individual';

    // Handle case where data is an empty array or null
    Map<String, dynamic> dataMap = {};
    if (data is Map<String, dynamic>) {
      dataMap = data;
    } else {}

    final licenseData = LicenseData(
      licenseType: licenseType,
      companyName: dataMap['companyName'],
      appTitle: dataMap['appTitle'],
      supportEmail: dataMap['supportEmail'],
      themeColor: dataMap['themeColor'],
      website: dataMap['website'],
      logoUrl: dataMap['logoUrl'],
      faviconUrl: dataMap['faviconUrl'],
      tagLine: dataMap['tagLine'],
      footerCredits: dataMap['footerCredits'],
    );

    return licenseData;
  }

  // Register device and start trial
  Future<bool> startTrial() async {
    try {
      if (!await _isOnline()) {
        _errorMessage = 'Internet connection required to start trial';
        notifyListeners();
        return false;
      }

      final deviceData = await DeviceService.getDeviceRegistrationData();
      final response = await ApiService.registerDevice(deviceData);

      if (response['statusCode'] == 200 &&
          response['body']['success'] == true) {
        await SecureStorageService.storeDeviceRegistered(true);
        await TrialService.startTrial();

        _status = LicenseStatus.trial;
        _trialData = await TrialService.getTrialData() as TrialData?;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _errorMessage = response['body']['message'] ?? 'Failed to start trial';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error starting trial: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Add license token and verify
  Future<bool> addLicenseToken(String token) async {
    try {
      if (!await _isOnline()) {
        _errorMessage = 'Internet connection required to verify license';
        notifyListeners();
        return false;
      }

      // Store token first
      await SecureStorageService.storeLicenseToken(token);

      // Verify license online
      final verificationResult =
          await LicenseVerificationService.forceOnlineVerification();

      if (verificationResult.isValid) {
        _status = LicenseStatus.valid;
        _licenseData = verificationResult.licenseData;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        // Remove invalid token
        await SecureStorageService.deleteLicenseToken();
        _errorMessage = verificationResult.errorMessage;
        notifyListeners();
        return false;
      }
    } catch (e) {
      await SecureStorageService.deleteLicenseToken();
      _errorMessage = 'Error verifying license: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Refresh trial status (force online check)
  Future<void> refreshTrialStatus() async {
    try {
      final trialStatus = await TrialService.forceOnlineCheck();

      switch (trialStatus) {
        case TrialStatus.active:
          _status = LicenseStatus.trial;
          _trialData = await TrialService.getTrialData() as TrialData?;
          _errorMessage = null;
          break;
        case TrialStatus.expired:
          _status = LicenseStatus.expired;
          _errorMessage = 'Trial period has expired';
          break;
        case TrialStatus.notStarted:
          _status = LicenseStatus.error;
          _errorMessage = 'Trial not started';
          break;
      }

      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error refreshing trial: ${e.toString()}';
      notifyListeners();
    }
  }

  // Force online license verification
  Future<void> forceOnlineLicenseVerification() async {
    try {
      final verificationResult =
          await LicenseVerificationService.forceOnlineVerification();

      switch (verificationResult.status) {
        case LicenseVerificationStatus.valid:
          _status = LicenseStatus.valid;
          _licenseData = verificationResult.licenseData;
          _errorMessage = null;
          break;
        case LicenseVerificationStatus.invalid:
          _status = LicenseStatus.expired;
          _errorMessage = verificationResult.errorMessage;
          break;
        case LicenseVerificationStatus.noInternet:
          _status = LicenseStatus.noInternet;
          _errorMessage = 'Internet connection required';
          break;
        case LicenseVerificationStatus.noLicense:
          _status = LicenseStatus.error;
          _errorMessage = 'No license found';
          break;
        default:
          _status = LicenseStatus.error;
          _errorMessage = verificationResult.errorMessage;
          break;
      }

      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error verifying license: ${e.toString()}';
      notifyListeners();
    }
  }

  // Get trial remaining days
  Future<int> getTrialRemainingDays() async {
    return await TrialService.getTrialRemainingDays();
  }

  // Get trial data
  Future<TrialData?> getTrialData() async {
    return await TrialService.getTrialData() as TrialData?;
  }

  // Check if mandatory online verification is required
  Future<bool> isMandatoryOnlineCheckRequired() async {
    final token = await SecureStorageService.getLicenseToken();
    if (token != null) {
      return await LicenseVerificationService.isMandatoryOnlineCheckRequired();
    } else {
      return await TrialService.isMandatoryOnlineCheckRequired();
    }
  }

  // Get days until mandatory check
  Future<int> getDaysUntilMandatoryCheck() async {
    final token = await SecureStorageService.getLicenseToken();
    if (token != null) {
      return await LicenseVerificationService.getDaysUntilMandatoryCheck();
    } else {
      return await TrialService.getDaysUntilMandatoryCheck();
    }
  }

  // Check network connectivity
  Future<bool> _isOnline() async {
    try {
      final isOnline = await ApiService.testConnectivity();
      return isOnline;
    } catch (e) {
      return false;
    }
  }

  // Clear all license data
  Future<void> clearLicenseData() async {
    await SecureStorageService.clearAllLicenseData();
    await TrialService.resetTrialData();
    await LicenseVerificationService.clearVerificationData();

    _status = LicenseStatus.welcome;
    _errorMessage = null;
    _licenseData = null;
    _trialData = null;
    notifyListeners();
  }

  // Get status description for UI
  String getStatusDescription() {
    switch (_status) {
      case LicenseStatus.checking:
        return 'Checking license...';
      case LicenseStatus.welcome:
        return 'Welcome to Nav2 Mission Planner';
      case LicenseStatus.trial:
        return 'Trial Period Active';
      case LicenseStatus.expired:
        return 'Trial/License Expired';
      case LicenseStatus.valid:
        return 'License Valid';
      case LicenseStatus.noInternet:
        return 'Internet Connection Required';
      case LicenseStatus.error:
        return 'Error: ${_errorMessage ?? 'Unknown error'}';
      case LicenseStatus.mandatoryCheckRequired:
        return 'Mandatory Online Verification Required';
      case LicenseStatus.tamperingDetected:
        return 'Time Tampering Detected';
    }
  }

  // Check if user can use the app
  bool canUseApp() {
    return _status == LicenseStatus.valid || _status == LicenseStatus.trial;
  }

  // Check if license is valid
  bool isLicenseValid() {
    return _status == LicenseStatus.valid;
  }

  // Check if trial is active
  bool isTrialActive() {
    return _status == LicenseStatus.trial;
  }

  // Check if user has active trial (regardless of current status)
  Future<bool> hasActiveTrial() async {
    final remainingDays = await getTrialRemainingDays();
    return remainingDays > 0;
  }

  // Check if trial has expired
  bool isTrialExpired() {
    return _status == LicenseStatus.expired;
  }

  // Check if internet is required
  bool requiresInternet() {
    return _status == LicenseStatus.noInternet;
  }

  // Allow trial usage (called from trial modal)
  void allowTrialUsage() {
    _status = LicenseStatus.valid;
    _errorMessage = null;
    notifyListeners();
  }

  // Update license status (for license activation)
  Future<void> updateLicenseStatus(LicenseStatus status) async {
    _status = status;
    _errorMessage = null;

    // If status is valid, load the license data
    if (status == LicenseStatus.valid) {
      // Note: This will need to be updated when the new LicenseData model is integrated
      // For now, we'll leave it as null to avoid type conflicts
      _licenseData = null;
    }

    notifyListeners();
  }
}
