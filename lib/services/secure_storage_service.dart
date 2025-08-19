import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/license_data.dart';
import 'image_cache_service.dart';

class SecureStorageService {
  // Storage keys
  static const String _licenseTokenKey = 'license_token';
  static const String _trialStartTimeKey = 'trial_start_time';
  static const String _lastTrialCheckKey = 'last_trial_check';
  static const String _deviceRegisteredKey = 'device_registered';
  static const String _lastLicenseCheckKey = 'last_license_check';
  static const String _licenseDataKey = 'license_data';
  static const String _lastMandatoryTrialCheckKey =
      'last_mandatory_trial_check';
  static const String _trialEndTimeKey = 'trial_end_time';
  static const String _organizationBrandingKey = 'organization_branding';
  static const String _licenseSummaryKey = 'license_summary';
  static const String _googleAccountIdKey = 'google_account_id';

  // Initialize secure storage
  static Future<void> initialize() async {
    // Using SharedPreferences for now
  }

  // Store license token securely
  static Future<void> storeLicenseToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedToken = await _encryptData(token);
    await prefs.setString(_licenseTokenKey, encryptedToken);
  }

  // Retrieve license token
  static Future<String?> getLicenseToken() async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedToken = prefs.getString(_licenseTokenKey);
    if (encryptedToken != null) {
      return await _decryptData(encryptedToken);
    }
    return null;
  }

  // Delete license token
  static Future<void> deleteLicenseToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_licenseTokenKey);
  }

  // Store trial start time
  static Future<void> storeTrialStartTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_trialStartTimeKey, time.toIso8601String());
  }

  // Get trial start time
  static Future<DateTime?> getTrialStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_trialStartTimeKey);
    if (timeStr != null) {
      return DateTime.parse(timeStr);
    }
    return null;
  }

  // Store last trial check time
  static Future<void> storeLastTrialCheck(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastTrialCheckKey, time.toIso8601String());
  }

  // Get last trial check time
  static Future<DateTime?> getLastTrialCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_lastTrialCheckKey);
    if (timeStr != null) {
      return DateTime.parse(timeStr);
    }
    return null;
  }

  // Store device registration status
  static Future<void> storeDeviceRegistered(bool registered) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deviceRegisteredKey, registered);
  }

  // Get device registration status
  static Future<bool> isDeviceRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_deviceRegisteredKey) ?? false;
  }

  // Store last license check time
  static Future<void> storeLastLicenseCheck(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastLicenseCheckKey, time.toIso8601String());
  }

  // Get last license check time
  static Future<DateTime?> getLastLicenseCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_lastLicenseCheckKey);
    if (timeStr != null) {
      return DateTime.parse(timeStr);
    }
    return null;
  }

  // Store license data
  static Future<void> storeLicenseData(LicenseData licenseData) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(licenseData.toJson());
    final encryptedData = await _encryptData(jsonString);
    await prefs.setString(_licenseDataKey, encryptedData);
  }

  // Get license data
  static Future<LicenseData?> getLicenseData() async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedData = prefs.getString(_licenseDataKey);
    if (encryptedData != null) {
      try {
        final decryptedData = await _decryptData(encryptedData);
        final jsonData = jsonDecode(decryptedData);
        final licenseData = LicenseData.fromJson(jsonData);
        return licenseData;
      } catch (e) {
        // Clear corrupted data
        await deleteLicenseData();
        return null;
      }
    }
    return null;
  }

  // Delete license data
  static Future<void> deleteLicenseData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_licenseDataKey);
  }

  // Store last mandatory trial check time
  static Future<void> storeLastMandatoryTrialCheck(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastMandatoryTrialCheckKey, time.toIso8601String());
  }

  // Get last mandatory trial check time
  static Future<DateTime?> getLastMandatoryTrialCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_lastMandatoryTrialCheckKey);
    if (timeStr != null) {
      return DateTime.parse(timeStr);
    }
    return null;
  }

  // Store trial end time
  static Future<void> storeTrialEndTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_trialEndTimeKey, time.toIso8601String());
  }

  // Get trial end time
  static Future<DateTime?> getTrialEndTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_trialEndTimeKey);
    if (timeStr != null) {
      return DateTime.parse(timeStr);
    }
    return null;
  }

  // Clear all license data
  static Future<void> clearAllLicenseData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_licenseTokenKey);
    await prefs.remove(_trialStartTimeKey);
    await prefs.remove(_lastTrialCheckKey);
    await prefs.remove(_deviceRegisteredKey);
    await prefs.remove(_lastLicenseCheckKey);
  }

  // Clear trial data only
  static Future<void> clearTrialData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_trialStartTimeKey);
    await prefs.remove(_trialEndTimeKey);
    await prefs.remove(_lastTrialCheckKey);
    await prefs.remove(_lastMandatoryTrialCheckKey);
  }

  // Store minimal license summary for offline gate
  static Future<void> storeLicenseSummary({
    required String status,
    String? licenseType,
    String? enterpriseId,
    String? offlineAllowedUntil,
    String? trialEndTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final summary = {
      'status': status,
      if (licenseType != null) 'licenseType': licenseType,
      if (enterpriseId != null) 'enterpriseId': enterpriseId,
      if (offlineAllowedUntil != null)
        'offlineAllowedUntil': offlineAllowedUntil,
      if (trialEndTime != null) 'trialEndTime': trialEndTime,
    };
    final jsonString = jsonEncode(summary);
    final encrypted = await _encryptData(jsonString);
    await prefs.setString(_licenseSummaryKey, encrypted);
  }

  static Future<Map<String, dynamic>?> getLicenseSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = prefs.getString(_licenseSummaryKey);
    if (encrypted == null) return null;
    try {
      final jsonStr = await _decryptData(encrypted);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      await prefs.remove(_licenseSummaryKey);
      return null;
    }
  }

  static Future<void> clearLicenseSummary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_licenseSummaryKey);
  }

  // Simple encryption (for basic security)
  static Future<String> _encryptData(String data) async {
    try {
      // Simple base64 encoding for now to avoid JSON corruption
      return base64Encode(utf8.encode(data));
    } catch (e) {
      rethrow;
    }
  }

  // Simple decryption
  static Future<String> _decryptData(String encryptedData) async {
    try {
      final decoded = utf8.decode(base64Decode(encryptedData));
      return decoded;
    } catch (e) {
      rethrow;
    }
  }

  // Get all stored data (for debugging)
  static Future<Map<String, dynamic>> getAllStoredData() async {
    final licenseToken = await getLicenseToken();
    final trialStartTime = await getTrialStartTime();
    final lastTrialCheck = await getLastTrialCheck();
    final isRegistered = await isDeviceRegistered();
    final lastLicenseCheck = await getLastLicenseCheck();

    return {
      'licenseToken': licenseToken != null ? '***HIDDEN***' : null,
      'trialStartTime': trialStartTime?.toIso8601String(),
      'lastTrialCheck': lastTrialCheck?.toIso8601String(),
      'isDeviceRegistered': isRegistered,
      'lastLicenseCheck': lastLicenseCheck?.toIso8601String(),
    };
  }

  // Store organization branding data
  static Future<void> storeOrganizationBranding(LicenseData data) async {
    if (data.licenseType == 'organization' ||
        data.licenseType == 'organisation') {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(data.toJson());
      final encryptedData = await _encryptData(jsonString);
      await prefs.setString(_organizationBrandingKey, encryptedData);

      // Cache images if URLs provided
      if (data.logoUrl != null) {
        await ImageCacheService.cacheImage(data.logoUrl!, 'logo');
      }
      if (data.faviconUrl != null) {
        await ImageCacheService.cacheImage(data.faviconUrl!, 'favicon');
      }
    }
  }

  // Get cached organization branding
  static Future<LicenseData?> getOrganizationBranding() async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedData = prefs.getString(_organizationBrandingKey);

    if (encryptedData != null) {
      try {
        final decryptedData = await _decryptData(encryptedData);
        final jsonData = jsonDecode(decryptedData);
        final licenseData = LicenseData.fromJson(jsonData);
        return licenseData;
      } catch (e) {
        // Clear corrupted data
        await clearOrganizationBranding();
        return null;
      }
    }
    return null;
  }

  // Clear organization branding (for individual licenses)
  static Future<void> clearOrganizationBranding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_organizationBrandingKey);
    await ImageCacheService.clearCachedImages();
  }

  // Store Google account ID
  static Future<void> storeGoogleAccountId(String googleId) async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedId = await _encryptData(googleId);
    await prefs.setString(_googleAccountIdKey, encryptedId);
    debugPrint('🔑 Google account ID stored securely');
  }

  // Get Google account ID
  static Future<String?> getGoogleAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedId = prefs.getString(_googleAccountIdKey);
    if (encryptedId != null) {
      try {
        return await _decryptData(encryptedId);
      } catch (e) {
        debugPrint('⚠️ Error retrieving Google account ID: $e');
        return null;
      }
    }
    return null;
  }

  // Clear Google account ID
  static Future<void> clearGoogleAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_googleAccountIdKey);
  }
}
