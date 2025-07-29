import 'package:shared_preferences/shared_preferences.dart';
import '../models/license_model.dart';
import 'api_service.dart';
import 'device_service.dart';
import 'secure_storage_service.dart';
import 'connectivity_cache.dart';

class LicenseVerificationService {
  static const Duration _dailyCheckInterval = Duration(hours: 24);
  static const Duration _mandatoryOnlineCheckInterval = Duration(days: 30);

  // Check license status (online + offline with mandatory verification)
  static Future<LicenseVerificationResult> checkLicenseStatus() async {
    // Get stored license token
    final token = await SecureStorageService.getLicenseToken();
    if (token == null) {
      return LicenseVerificationResult(
        isValid: false,
        status: LicenseVerificationStatus.noLicense,
        errorMessage: 'No license found',
      );
    }

    // Check for time tampering
    final timeTamperingDetected = await _detectTimeTampering();
    if (timeTamperingDetected) {
      return LicenseVerificationResult(
        isValid: false,
        status: LicenseVerificationStatus.tamperingDetected,
        errorMessage: 'Time tampering detected',
      );
    }

    // Check if mandatory online verification is required
    final mandatoryOnlineCheck = await _isMandatoryOnlineCheckRequired();

    // Check if daily online verification is needed
    final shouldCheckOnline = await _shouldCheckOnline();

    // If online verification is needed and internet is available
    if (await _isOnline() && (shouldCheckOnline || mandatoryOnlineCheck)) {
      return await _verifyLicenseOnline(token);
    }

    // If mandatory online check is required but no internet
    if (mandatoryOnlineCheck && !await _isOnline()) {
      return LicenseVerificationResult(
        isValid: false,
        status: LicenseVerificationStatus.mandatoryCheckRequired,
        errorMessage: 'Mandatory online verification required',
      );
    }

    // Use cached verification result
    return await _getCachedVerificationResult();
  }

  // Verify license online
  static Future<LicenseVerificationResult> _verifyLicenseOnline(
      String token) async {
    try {
      final deviceId = await DeviceService.getDeviceId();
      final response = await ApiService.verifyLicense(
        deviceId: deviceId,
        token: token,
      );

      // Update last check time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'last_license_check', DateTime.now().toIso8601String());

      // Update mandatory check time if this was a mandatory check
      if (await _isMandatoryOnlineCheckRequired()) {
        await prefs.setString(
            'last_mandatory_license_check', DateTime.now().toIso8601String());
      }

      if (response['statusCode'] == 200 &&
          response['body']['licenseVerified'] == true) {
        // Store successful verification result
        final licenseData = response['body']['data'] != null
            ? LicenseData.fromJson(response['body']['data'])
            : null;
        await _storeVerificationResult(true, licenseData, null);

        return LicenseVerificationResult(
          isValid: true,
          status: LicenseVerificationStatus.valid,
          licenseData: licenseData,
        );
      } else {
        // License invalid - remove token
        await SecureStorageService.deleteLicenseToken();
        final errorMessage =
            response['body']['data']?['error'] ?? 'License verification failed';
        await _storeVerificationResult(false, null, errorMessage);

        return LicenseVerificationResult(
          isValid: false,
          status: LicenseVerificationStatus.invalid,
          errorMessage: errorMessage,
        );
      }
    } catch (e) {
      // If online verification fails, use cached result
      return await _getCachedVerificationResult();
    }
  }

  // Check if daily online verification is needed
  static Future<bool> _shouldCheckOnline() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckStr = prefs.getString('last_license_check');

    if (lastCheckStr == null) return true;

    final lastCheck = DateTime.parse(lastCheckStr);
    final now = DateTime.now();

    return now.difference(lastCheck) >= _dailyCheckInterval;
  }

  // Check if mandatory online verification is required (every 30 days)
  static Future<bool> _isMandatoryOnlineCheckRequired() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMandatoryCheckStr =
        prefs.getString('last_mandatory_license_check');

    if (lastMandatoryCheckStr == null) return true;

    final lastMandatoryCheck = DateTime.parse(lastMandatoryCheckStr);
    final now = DateTime.now();

    return now.difference(lastMandatoryCheck) >= _mandatoryOnlineCheckInterval;
  }

  // Detect time tampering
  static Future<bool> _detectTimeTampering() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastTimeCheckStr = prefs.getString('last_license_time_check');

      final now = DateTime.now();

      if (lastTimeCheckStr != null) {
        final lastTimeCheck = DateTime.parse(lastTimeCheckStr);
        final timeDifference = now.difference(lastTimeCheck).abs();

        // If time difference is more than 2 days, suspect tampering
        if (timeDifference.inDays > 2) {
          return true;
        }
      }

      // Store current time for next check
      await prefs.setString('last_license_time_check', now.toIso8601String());

      return false;
    } catch (e) {
      return false;
    }
  }

  // Check network connectivity with caching
  static Future<bool> _isOnline() async {
    return await ConnectivityCache.getConnectivityStatus(() async {
      return await ApiService.testConnectivity();
    });
  }

  // Store verification result
  static Future<void> _storeVerificationResult(
    bool isValid,
    LicenseData? licenseData,
    String? errorMessage,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('license_is_valid', isValid);
    await prefs.setString(
        'license_verification_time', DateTime.now().toIso8601String());

    if (errorMessage != null) {
      await prefs.setString('license_error_message', errorMessage);
    } else {
      await prefs.remove('license_error_message');
    }
  }

  // Get cached verification result
  static Future<LicenseVerificationResult>
      _getCachedVerificationResult() async {
    final prefs = await SharedPreferences.getInstance();
    final isValid = prefs.getBool('license_is_valid') ?? false;
    final errorMessage = prefs.getString('license_error_message');

    if (isValid) {
      return LicenseVerificationResult(
        isValid: true,
        status: LicenseVerificationStatus.valid,
        licenseData: null, // License data not cached for security
      );
    } else {
      return LicenseVerificationResult(
        isValid: false,
        status: LicenseVerificationStatus.invalid,
        errorMessage: errorMessage ?? 'License verification failed',
      );
    }
  }

  // Force online verification
  static Future<LicenseVerificationResult> forceOnlineVerification() async {
    final token = await SecureStorageService.getLicenseToken();
    if (token == null) {
      return LicenseVerificationResult(
        isValid: false,
        status: LicenseVerificationStatus.noLicense,
        errorMessage: 'No license found',
      );
    }

    if (!await _isOnline()) {
      return LicenseVerificationResult(
        isValid: false,
        status: LicenseVerificationStatus.noInternet,
        errorMessage: 'Internet connection required',
      );
    }

    return await _verifyLicenseOnline(token);
  }

  // Check if mandatory online verification is required
  static Future<bool> isMandatoryOnlineCheckRequired() async {
    return await _isMandatoryOnlineCheckRequired();
  }

  // Get days until mandatory online verification
  static Future<int> getDaysUntilMandatoryCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMandatoryCheckStr =
        prefs.getString('last_mandatory_license_check');

    if (lastMandatoryCheckStr == null) return 0;

    final lastMandatoryCheck = DateTime.parse(lastMandatoryCheckStr);
    final now = DateTime.now();
    final nextMandatoryCheck =
        lastMandatoryCheck.add(_mandatoryOnlineCheckInterval);

    final remaining = nextMandatoryCheck.difference(now).inDays;
    return remaining > 0 ? remaining : 0;
  }

  // Get last verification time
  static Future<DateTime?> getLastVerificationTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckStr = prefs.getString('last_license_check');

    if (lastCheckStr != null) {
      return DateTime.parse(lastCheckStr);
    }
    return null;
  }

  // Clear license verification data
  static Future<void> clearVerificationData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('license_is_valid');
    await prefs.remove('license_verification_time');
    await prefs.remove('license_error_message');
    await prefs.remove('last_license_check');
    await prefs.remove('last_mandatory_license_check');
    await prefs.remove('last_license_time_check');

    // Clear connectivity cache
    ConnectivityCache.clearCache();
  }

  // Clear connectivity cache (for manual refresh)
  static void clearConnectivityCache() {
    ConnectivityCache.clearCache();
  }
}

// License verification result
class LicenseVerificationResult {
  final bool isValid;
  final LicenseVerificationStatus status;
  final LicenseData? licenseData;
  final String? errorMessage;

  LicenseVerificationResult({
    required this.isValid,
    required this.status,
    this.licenseData,
    this.errorMessage,
  });
}

// License verification status
enum LicenseVerificationStatus {
  valid,
  invalid,
  noLicense,
  noInternet,
  mandatoryCheckRequired,
  tamperingDetected,
}
