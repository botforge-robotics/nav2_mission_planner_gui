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
  bool _isStartingTrial = false;

  // Prevent multiple simultaneous license checks
  static bool _isChecking = false;

  // Getters
  LicenseStatus get status => _status;
  String? get errorMessage => _errorMessage;
  LicenseData? get licenseData => _licenseData;
  TrialData? get trialData => _trialData;
  bool get isStartingTrial => _isStartingTrial;

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

              // Check if cloud data is different from local data
              final localLicenseData =
                  await SecureStorageService.getLicenseData();
              bool shouldUpdateBranding = true;

              if (localLicenseData != null &&
                  licenseData.licenseType == localLicenseData.licenseType &&
                  licenseData.appTitle == localLicenseData.appTitle &&
                  licenseData.themeColor == localLicenseData.themeColor &&
                  licenseData.companyName == localLicenseData.companyName) {
                shouldUpdateBranding = false;
              }

              await SecureStorageService.storeLicenseData(licenseData);

              // Handle organization branding - always store for organization licenses
              if (licenseData.licenseType == 'organization' ||
                  licenseData.licenseType == 'organisation') {
                await SecureStorageService.storeOrganizationBranding(
                    licenseData);
                await _brandingProvider
                    ?.updateOrganizationBranding(licenseData);
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
          // Apply local branding immediately for fast startup
          if (localLicenseData.licenseType == 'organization' ||
              localLicenseData.licenseType == 'organisation') {
            await _brandingProvider
                ?.updateOrganizationBranding(localLicenseData);
          } else {
            _brandingProvider?.clearOrganizationBranding();
          }

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

          _errorMessage = null;
          notifyListeners();
          _isChecking = false;
          return;
        } else {
          // No local license data found
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

          // Handle 404 as new device - should have trial access
          if (response['statusCode'] == 404) {
            try {
              // Register the device automatically
              final deviceData =
                  await DeviceService.getDeviceRegistrationData();
              final registerResponse =
                  await ApiService.registerDevice(deviceData);

              if (registerResponse['statusCode'] == 200 &&
                  registerResponse['body']['success'] == true) {
                await SecureStorageService.storeDeviceRegistered(true);
              }
            } catch (e) {
              // Silent error handling
            }

            _status = LicenseStatus.welcome;
            _errorMessage = null;
            notifyListeners();
            _isChecking = false;
            return;
          }

          if (response['statusCode'] == 200 &&
              response['body']['success'] == true) {
            final cloudData = response['body']['data'];
            final cloudTrialStatus = cloudData['trialStatus'];

            // Handle different trial statuses
            if (cloudTrialStatus == 'not_started') {
              _status = LicenseStatus.welcome;
              _errorMessage = 'Trial available for 7 days - Activate trial';
              notifyListeners();
              _isChecking = false;
              return;
            } else if (cloudTrialStatus == 'valid') {
              // Store trial data if available
              if (cloudData['trialStartTime'] != null) {
                final cloudTrialStartTime =
                    DateTime.parse(cloudData['trialStartTime']);
                await SecureStorageService.storeTrialStartTime(
                    cloudTrialStartTime);
              }
              if (cloudData['trialEndTime'] != null) {
                final cloudTrialEndTime =
                    DateTime.parse(cloudData['trialEndTime']);
                await SecureStorageService.storeTrialEndTime(cloudTrialEndTime);
              }
              await SecureStorageService.storeDeviceRegistered(true);

              _status = LicenseStatus.welcome;
              _errorMessage = null;
              notifyListeners();
              _isChecking = false;
              return;
            } else {
              // Trial expired or other status - sync with cloud
              // Clear local trial data to sync with cloud
              await SecureStorageService.clearTrialData();

              // Update status to reflect expired trial
              _status = LicenseStatus.expired;
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

    print('🔍 Parsing license response:');
    print('License Type: $licenseType');
    print('Raw data: $data');

    // Handle case where data is an empty array or null
    Map<String, dynamic> dataMap = {};
    if (data is Map<String, dynamic>) {
      dataMap = data;
    }

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

  // Start trial using the new API endpoint
  Future<bool> startTrial() async {
    try {
      if (!await _isOnline()) {
        _errorMessage = 'Internet connection required to start trial';
        notifyListeners();
        return false;
      }

      _isStartingTrial = true;
      // Keep the current error message to maintain UI state during API call
      notifyListeners();

      final deviceId = await DeviceService.getDeviceId();
      final response = await ApiService.startTrial(deviceId);

      if (response['statusCode'] == 200 &&
          response['body']['success'] == true) {
        // Store trial data from response
        final data = response['body']['data'];
        if (data['trialStartTime'] != null) {
          final trialStartTime = DateTime.parse(data['trialStartTime']);
          await SecureStorageService.storeTrialStartTime(trialStartTime);
        }
        if (data['trialEndTime'] != null) {
          final trialEndTime = DateTime.parse(data['trialEndTime']);
          await SecureStorageService.storeTrialEndTime(trialEndTime);
        }

        await SecureStorageService.storeDeviceRegistered(true);

        // Only change status to trial after successful API response
        _status = LicenseStatus.trial;
        _errorMessage = null;
        _isStartingTrial = false;
        notifyListeners();
        return true;
      } else if (response['statusCode'] == 409) {
        _errorMessage = 'Trial already started';
        _isStartingTrial = false;
        // Keep status as welcome to prevent access without successful activation
        notifyListeners();
        return false;
      } else if (response['statusCode'] == 404) {
        _errorMessage = 'Device not found - please register first';
        _isStartingTrial = false;
        // Keep status as welcome to prevent access without successful activation
        notifyListeners();
        return false;
      } else {
        _errorMessage = response['body']['message'] ?? 'Failed to start trial';
        _isStartingTrial = false;
        // Keep status as welcome to prevent access without successful activation
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error starting trial: ${e.toString()}';
      _isStartingTrial = false;
      // Keep status as welcome to prevent access without successful activation
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
    _status = LicenseStatus.trial;
    _errorMessage = null;
    notifyListeners();
  }

  // Update license status (for license activation)
  Future<void> updateLicenseStatus(LicenseStatus status,
      {LicenseData? licenseData}) async {
    _status = status;
    _errorMessage = null;

    // If status is valid, clear trial data and load the license data
    if (status == LicenseStatus.valid) {
      // Clear trial data when a valid license is activated
      await TrialService.resetTrialData();
      _trialData = null;

      // Set the license data if provided
      if (licenseData != null) {
        _licenseData = licenseData;
      }
    }

    // If status is expired, clear trial data to sync with cloud
    if (status == LicenseStatus.expired) {
      await SecureStorageService.clearTrialData();
      _trialData = null;
    }

    notifyListeners();
  }
}
