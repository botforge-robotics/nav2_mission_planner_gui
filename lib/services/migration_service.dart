import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';
import 'app_usage_tracker.dart';

/// Service to handle migration detection and trial reset functionality
///
/// This service uses cloud-first approach to determine if a user should see
/// the migration popup. It prioritizes cloud data over local data and only
/// shows popup to users whose trials expired before October 5th, 2025.
class MigrationService {
  /// Check if user should see trial reset popup
  /// Uses cloud data as primary source, local data as fallback
  static Future<bool> shouldShowTrialResetPopup() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      // First check cloud data (primary source)
      final cloudResult = await _checkCloudMigrationStatus(user.uid);
      if (cloudResult != null) {
        return cloudResult;
      }

      // Fallback to local check if cloud fails
      debugPrint('⚠️ Cloud check failed, falling back to local check');
      return await AppUsageTracker.shouldShowTrialResetPopup();
    } catch (e) {
      debugPrint('Error checking migration status: $e');
      // Final fallback to local check
      return await AppUsageTracker.shouldShowTrialResetPopup();
    }
  }

  /// Check migration status from cloud (primary method)
  static Future<bool?> _checkCloudMigrationStatus(String accountId) async {
    try {
      final result =
          await FirebaseService.callCloudFunction('getMigrationStatus', {
        'accountId': accountId,
      });

      if (result['success'] == true) {
        final data = result['data'];
        final needsPopup = data['needsMigrationPopup'] ?? false;
        final migrationDate = data['migrationDate'];

        debugPrint(
            '📊 Cloud migration status: needsPopup=$needsPopup, migrationDate=$migrationDate');
        debugPrint('📊 Full response data: $data');

        // Update local cache for faster future access
        await AppUsageTracker.markHadPreviousTrial();
        if (needsPopup) {
          // Don't mark as shown yet - wait for user to actually see popup
        }

        return needsPopup;
      }

      return null; // Cloud check failed
    } catch (e) {
      debugPrint('Error checking cloud migration status: $e');
      return null;
    }
  }

  /// Mark migration popup as shown in cloud and locally
  /// This also resets the user's trial data to give them a fresh start
  static Future<void> markMigrationPopupShown() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('⚠️ No user logged in, cannot mark migration popup');
        return;
      }

      debugPrint(
          '🔄 Marking migration popup as shown and resetting trial data...');

      // Mark in cloud (primary) - this now also resets trial data
      final cloudResult =
          await FirebaseService.callCloudFunction('markMigrationPopupShown', {
        'accountId': user.uid,
      });

      if (cloudResult['success'] == true) {
        debugPrint(
            '✅ Migration popup marked as shown and trial data reset in cloud');
      } else {
        debugPrint(
            '⚠️ Failed to mark migration popup in cloud: ${cloudResult['error']}');
      }

      // Always mark locally (even if cloud fails)
      await AppUsageTracker.markTrialResetPopupShown();
      debugPrint('✅ Migration popup marked as shown locally');
    } catch (e) {
      debugPrint('❌ Error marking migration popup: $e');
      // Still mark locally even if cloud fails
      try {
        await AppUsageTracker.markTrialResetPopupShown();
        debugPrint('✅ Migration popup marked as shown locally (fallback)');
      } catch (localError) {
        debugPrint('❌ Failed to mark migration popup locally: $localError');
      }
    }
  }

  /// Check if user had previous trial (for migration detection)
  static Future<bool> checkMigrationStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      // Check with cloud to get accurate migration status
      final result =
          await FirebaseService.callCloudFunction('getMigrationStatus', {
        'accountId': user.uid,
      });

      if (result['success'] == true) {
        final data = result['data'];
        final needsPopup = data['needsMigrationPopup'] ?? false;

        // Update local tracking if user had previous trial
        if (data['hadPreviousTrial'] == true) {
          await AppUsageTracker.markHadPreviousTrial();
        }

        return needsPopup;
      }

      return false;
    } catch (e) {
      debugPrint('Error checking migration status: $e');
      return false;
    }
  }
}
