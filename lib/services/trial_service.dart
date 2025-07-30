import 'package:shared_preferences/shared_preferences.dart';
import '../models/license_model.dart';
import 'api_service.dart';
import 'device_service.dart';
import 'connectivity_cache.dart';
import 'secure_storage_service.dart';

class TrialService {
  static const int _trialDays = 7;
  static const Duration _dailyCheckInterval = Duration(hours: 24);
  static const Duration _mandatoryOnlineCheckInterval = Duration(days: 30);

  // Check trial status (online + offline with anti-tampering)
  static Future<TrialStatus> checkTrialStatus() async {
    // First check offline status
    final offlineStatus = await _checkOfflineTrialStatus();

    // Check for time tampering
    final timeTamperingDetected = await _detectTimeTampering();
    if (timeTamperingDetected) {
      return TrialStatus.expired; // Expire trial if tampering detected
    }

    // Check if online verification is mandatory
    final mandatoryOnlineCheck = await _isMandatoryOnlineCheckRequired();

    // If offline or trial expired offline, return offline status
    if (!await _isOnline()) {
      if (mandatoryOnlineCheck) {
        // Mandatory online check required but no internet
        return TrialStatus.expired;
      }
      return offlineStatus;
    }

    // If online and trial still active, check with server
    if (await _shouldCheckOnline() || mandatoryOnlineCheck) {
      return await _checkOnlineTrialStatus();
    }

    return offlineStatus;
  }

  // Check trial status offline
  static Future<TrialStatus> _checkOfflineTrialStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final trialStartTimeStr = prefs.getString('trial_start_time');

    if (trialStartTimeStr == null) {
      return TrialStatus.notStarted;
    }

    // First try to use stored trial end time from cloud
    final storedEndTime = await SecureStorageService.getTrialEndTime();
    if (storedEndTime != null) {
      final now = DateTime.now();
      if (now.isAfter(storedEndTime)) {
        return TrialStatus.expired;
      }
      return TrialStatus.active;
    }

    // Fallback to old calculation if no stored end time
    final trialStartTime = DateTime.parse(trialStartTimeStr);
    final trialEndTime = trialStartTime.add(Duration(days: _trialDays));
    final now = DateTime.now();

    if (now.isAfter(trialEndTime)) {
      return TrialStatus.expired;
    }

    return TrialStatus.active;
  }

  // Check if we should verify online (once per day)
  static Future<bool> _shouldCheckOnline() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckStr = prefs.getString('last_trial_check');

    if (lastCheckStr == null) return true;

    final lastCheck = DateTime.parse(lastCheckStr);
    final now = DateTime.now();

    return now.difference(lastCheck) >= _dailyCheckInterval;
  }

  // Check if mandatory online check is required (every 30 days)
  static Future<bool> _isMandatoryOnlineCheckRequired() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMandatoryCheckStr = prefs.getString('last_mandatory_trial_check');

    if (lastMandatoryCheckStr == null) return true;

    final lastMandatoryCheck = DateTime.parse(lastMandatoryCheckStr);
    final now = DateTime.now();

    return now.difference(lastMandatoryCheck) >= _mandatoryOnlineCheckInterval;
  }

  // Check trial status online
  static Future<TrialStatus> _checkOnlineTrialStatus() async {
    try {
      final deviceId = await DeviceService.getDeviceId();
      final response = await ApiService.getTrialStatus(deviceId);

      // Update last check time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'last_trial_check', DateTime.now().toIso8601String());

      // Update mandatory check time if this was a mandatory check
      if (await _isMandatoryOnlineCheckRequired()) {
        await prefs.setString(
            'last_mandatory_trial_check', DateTime.now().toIso8601String());
      }

      if (response['statusCode'] == 200 &&
          response['body']['success'] == true) {
        final trialStatus = response['body']['data']['trialStatus'];
        switch (trialStatus) {
          case 'valid':
            return TrialStatus.active;
          case 'expired':
            // Sync local storage when cloud reports trial expired
            await SecureStorageService.clearTrialData();
            return TrialStatus.expired;
          default:
            return TrialStatus.notStarted;
        }
      } else {
        return TrialStatus.expired;
      }
    } catch (e) {
      // If online check fails, return offline status
      return await _checkOfflineTrialStatus();
    }
  }

  // Detect time tampering
  static Future<bool> _detectTimeTampering() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckStr = prefs.getString('last_trial_check');
      final lastTimeCheckStr = prefs.getString('last_time_check');

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
      await prefs.setString('last_time_check', now.toIso8601String());

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

  // Get trial remaining days
  static Future<int> getTrialRemainingDays() async {
    final endTime = await SecureStorageService.getTrialEndTime();
    final now = DateTime.now();
    if (endTime != null) {
      final remaining = endTime.difference(now).inDays;
      return remaining > 0 ? remaining : 0;
    }
    // fallback to old logic
    final prefs = await SharedPreferences.getInstance();
    final trialStartTimeStr = prefs.getString('trial_start_time');
    if (trialStartTimeStr == null) return _trialDays;
    final trialStartTime = DateTime.parse(trialStartTimeStr);
    final trialEndTime = trialStartTime.add(Duration(days: _trialDays));
    final daysSinceStart = now.difference(trialStartTime).inDays;
    final remaining = _trialDays - daysSinceStart;
    return remaining > 0 ? remaining : 0;
  }

  // Get trial start time
  static Future<DateTime?> getTrialStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    final trialStartTimeStr = prefs.getString('trial_start_time');

    if (trialStartTimeStr != null) {
      return DateTime.parse(trialStartTimeStr);
    }
    return null;
  }

  // Get trial end time
  static Future<DateTime?> getTrialEndTime() async {
    final startTime = await getTrialStartTime();
    if (startTime != null) {
      return startTime.add(Duration(days: _trialDays));
    }
    return null;
  }

  // Start trial period
  static Future<void> startTrial() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString('trial_start_time', now.toIso8601String());
    await prefs.setString('last_trial_check', now.toIso8601String());
    await prefs.setString('last_mandatory_trial_check', now.toIso8601String());
    await prefs.setString('last_time_check', now.toIso8601String());
  }

  // Check if trial is active
  static Future<bool> isTrialActive() async {
    final status = await checkTrialStatus();
    return status == TrialStatus.active;
  }

  // Check if trial has expired
  static Future<bool> isTrialExpired() async {
    final status = await checkTrialStatus();
    return status == TrialStatus.expired;
  }

  // Get trial data for display
  static Future<TrialData> getTrialData() async {
    final startTime = await getTrialStartTime();
    final endTime = await getTrialEndTime();
    final remainingDays = await getTrialRemainingDays();
    final status = await checkTrialStatus();

    return TrialData(
      status: status,
      remainingDays: remainingDays,
      startTime: startTime,
      endTime: endTime,
    );
  }

  // Force online check (for manual refresh)
  static Future<TrialStatus> forceOnlineCheck() async {
    if (!await _isOnline()) {
      return await _checkOfflineTrialStatus();
    }

    try {
      final deviceId = await DeviceService.getDeviceId();
      final response = await ApiService.getTrialStatus(deviceId);

      // Update last check time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'last_trial_check', DateTime.now().toIso8601String());

      if (response['statusCode'] == 200 &&
          response['body']['success'] == true) {
        final trialStatus = response['body']['data']['trialStatus'];
        switch (trialStatus) {
          case 'valid':
            return TrialStatus.active;
          case 'expired':
            return TrialStatus.expired;
          default:
            return TrialStatus.notStarted;
        }
      } else {
        return TrialStatus.expired;
      }
    } catch (e) {
      return await _checkOfflineTrialStatus();
    }
  }

  // Check if mandatory online verification is required
  static Future<bool> isMandatoryOnlineCheckRequired() async {
    return await _isMandatoryOnlineCheckRequired();
  }

  // Get days until mandatory online check
  static Future<int> getDaysUntilMandatoryCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMandatoryCheckStr = prefs.getString('last_mandatory_trial_check');

    if (lastMandatoryCheckStr == null) return 0;

    final lastMandatoryCheck = DateTime.parse(lastMandatoryCheckStr);
    final now = DateTime.now();
    final nextMandatoryCheck =
        lastMandatoryCheck.add(_mandatoryOnlineCheckInterval);

    final remaining = nextMandatoryCheck.difference(now).inDays;
    return remaining > 0 ? remaining : 0;
  }

  // Reset trial data (for testing or reset)
  static Future<void> resetTrialData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('trial_start_time');
    await prefs.remove('last_trial_check');
    await prefs.remove('last_mandatory_trial_check');
    await prefs.remove('last_time_check');

    // Clear connectivity cache
    ConnectivityCache.clearCache();
  }

  // Clear connectivity cache (for manual refresh)
  static void clearConnectivityCache() {
    ConnectivityCache.clearCache();
  }
}
