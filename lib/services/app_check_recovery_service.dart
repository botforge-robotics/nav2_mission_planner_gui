import 'package:flutter/foundation.dart';
import 'firebase_service.dart';

/// Service to handle App Check errors and provide recovery mechanisms
class AppCheckRecoveryService {
  static final AppCheckRecoveryService _instance =
      AppCheckRecoveryService._internal();
  factory AppCheckRecoveryService() => _instance;
  AppCheckRecoveryService._internal();

  /// Attempt to recover from App Check errors
  /// Returns true if recovery was successful, false otherwise
  Future<bool> attemptRecovery() async {
    try {
      debugPrint('🔄 Attempting App Check recovery...');

      // Get current status
      final status = FirebaseService.getAppCheckStatus();
      debugPrint('📊 Current App Check status: $status');

      // If we have a cached token and it's not too old, try using it
      if (status['hasCachedToken'] == true && status['tokenAge'] != null) {
        final tokenAge = status['tokenAge'] as int;
        if (tokenAge < 60) {
          // Less than 1 hour old
          debugPrint('✅ Using relatively fresh cached token for recovery');
          return true;
        }
      }

      // Force refresh the token
      final newToken = await FirebaseService.refreshAppCheckToken();
      if (newToken != null) {
        debugPrint('✅ Successfully refreshed App Check token');
        return true;
      }

      debugPrint('❌ Failed to refresh App Check token');
      return false;
    } catch (e) {
      debugPrint('❌ App Check recovery failed: $e');
      return false;
    }
  }

  /// Check if the current error is recoverable
  bool isRecoverableError(String error) {
    final lowerError = error.toLowerCase();
    return lowerError.contains('too many attempts') ||
        lowerError.contains('app check') ||
        lowerError.contains('attestation failed') ||
        lowerError.contains('token expired');
  }

  /// Get user-friendly error message and recovery suggestion
  Map<String, String> getErrorInfo(String error) {
    final lowerError = error.toLowerCase();

    if (lowerError.contains('too many attempts')) {
      return {
        'title': 'Too Many Requests',
        'message':
            'You\'ve made too many requests. Please wait a moment and try again.',
        'recovery': 'Wait 1-2 minutes before retrying',
        'action': 'retry_later'
      };
    } else if (lowerError.contains('app check')) {
      return {
        'title': 'Device Verification Failed',
        'message':
            'Unable to verify your device. This may be a temporary issue.',
        'recovery': 'Try restarting the app or check your internet connection',
        'action': 'restart_app'
      };
    } else if (lowerError.contains('attestation failed')) {
      return {
        'title': 'Device Security Check Failed',
        'message': 'Your device failed a security verification check.',
        'recovery': 'Ensure you\'re using the official app from Google Play',
        'action': 'check_source'
      };
    } else if (lowerError.contains('token expired')) {
      return {
        'title': 'Security Token Expired',
        'message': 'Your security token has expired and needs to be refreshed.',
        'recovery': 'The app will automatically refresh this for you',
        'action': 'auto_refresh'
      };
    }

    // Default error
    return {
      'title': 'Verification Error',
      'message': 'An error occurred while verifying your device.',
      'recovery': 'Please try again or contact support if the issue persists',
      'action': 'contact_support'
    };
  }

  /// Get current App Check health status
  Map<String, dynamic> getHealthStatus() {
    return FirebaseService.getAppCheckStatus();
  }

  /// Check if App Check is healthy and ready for use
  bool isHealthy() {
    final status = getHealthStatus();
    return status['enabled'] == true &&
        status['hasCachedToken'] == true &&
        (status['tokenAge'] == null || status['tokenAge'] < 60);
  }
}
