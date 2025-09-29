import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

/// Service to track app usage patterns for the new trial flow
///
/// This service manages the state of whether a user has:
/// - Ever reached the teleop screen (trial trigger point)
/// - Completed first app launch
/// - Had their trial reset (for migration popup)
class AppUsageTracker {
  // Storage keys
  static const String _hasEverReachedTeleopKey = 'has_ever_reached_teleop';
  static const String _firstAppLaunchCompletedKey =
      'first_app_launch_completed';
  static const String _trialResetPopupShownKey = 'trial_reset_popup_shown';
  static const String _hadPreviousTrialKey = 'had_previous_trial';

  /// Check if user has ever reached the teleop screen
  /// This is the trigger point for starting trials
  static Future<bool> hasEverReachedTeleop() async {
    return await SecureStorageService.readBool(_hasEverReachedTeleopKey) ??
        false;
  }

  /// Mark that user has reached teleop screen for the first time
  /// This triggers trial eligibility
  static Future<void> markTeleopReached() async {
    await SecureStorageService.writeBool(_hasEverReachedTeleopKey, true);
    debugPrint('📱 Marked teleop as reached - trial eligibility triggered');
  }

  /// Check if this is the first app launch
  /// Returns true on first launch, then marks as completed
  static Future<bool> isFirstAppLaunch() async {
    final isFirst =
        await SecureStorageService.readBool(_firstAppLaunchCompletedKey) ??
            true;
    if (isFirst) {
      await SecureStorageService.writeBool(_firstAppLaunchCompletedKey, false);
      debugPrint('📱 First app launch detected');
    }
    return isFirst;
  }

  /// Check if trial reset popup has been shown
  static Future<bool> hasShownTrialResetPopup() async {
    return await SecureStorageService.readBool(_trialResetPopupShownKey) ??
        false;
  }

  /// Mark that trial reset popup has been shown
  static Future<void> markTrialResetPopupShown() async {
    await SecureStorageService.writeBool(_trialResetPopupShownKey, true);
    debugPrint('📱 Trial reset popup marked as shown');
  }

  /// Check if user had a previous trial (for migration detection)
  static Future<bool> hadPreviousTrial() async {
    return await SecureStorageService.readBool(_hadPreviousTrialKey) ?? false;
  }

  /// Mark that user had a previous trial (set during migration detection)
  static Future<void> markHadPreviousTrial() async {
    await SecureStorageService.writeBool(_hadPreviousTrialKey, true);
    debugPrint('📱 Marked user as having previous trial');
  }

  /// Reset all tracking data (for testing or complete reset)
  static Future<void> resetAllTracking() async {
    await SecureStorageService.delete(_hasEverReachedTeleopKey);
    await SecureStorageService.delete(_firstAppLaunchCompletedKey);
    await SecureStorageService.delete(_trialResetPopupShownKey);
    await SecureStorageService.delete(_hadPreviousTrialKey);
    debugPrint('📱 Reset all app usage tracking');
  }

  /// Check if user should see trial reset popup
  /// This is now a fallback method - primary check is done in MigrationService
  static Future<bool> shouldShowTrialResetPopup() async {
    final hadPrevious = await hadPreviousTrial();
    final popupShown = await hasShownTrialResetPopup();
    return hadPrevious && !popupShown;
  }
}
