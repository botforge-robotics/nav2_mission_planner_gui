import 'package:flutter/foundation.dart';
import 'firebase_service.dart';
import 'app_check_recovery_service.dart';
import '../constants/app_config.dart';

/// Service to test and debug App Check functionality
class AppCheckTestService {
  static final AppCheckTestService _instance = AppCheckTestService._internal();
  factory AppCheckTestService() => _instance;
  AppCheckTestService._internal();

  /// Run comprehensive App Check tests
  Future<Map<String, dynamic>> runTests() async {
    final results = <String, dynamic>{};

    try {
      debugPrint('🧪 Starting App Check tests...');

      // Test 1: Check initialization status
      results['initialization'] = await _testInitialization();

      // Test 2: Check token availability
      results['tokenAvailability'] = await _testTokenAvailability();

      // Test 3: Check health status
      results['healthStatus'] = await _testHealthStatus();

      // Test 4: Test recovery service
      results['recoveryService'] = await _testRecoveryService();

      debugPrint('✅ App Check tests completed');
    } catch (e) {
      debugPrint('❌ App Check tests failed: $e');
      results['error'] = e.toString();
    }

    return results;
  }

  /// Test Firebase initialization
  Future<Map<String, dynamic>> _testInitialization() async {
    try {
      final status = FirebaseService.getAppCheckStatus();
      return {
        'success': true,
        'enabled': status['enabled'],
        'hasCachedToken': status['hasCachedToken'],
        'tokenAge': status['tokenAge'],
        'nextRefreshIn': status['nextRefreshIn']
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Test token availability
  Future<Map<String, dynamic>> _testTokenAvailability() async {
    try {
      final token = await FirebaseService.refreshAppCheckToken();
      return {
        'success': true,
        'hasToken': token != null,
        'tokenLength': token?.length ?? 0
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Test health status
  Future<Map<String, dynamic>> _testHealthStatus() async {
    try {
      final recoveryService = AppCheckRecoveryService();
      final isHealthy = recoveryService.isHealthy();
      final healthStatus = recoveryService.getHealthStatus();

      return {
        'success': true,
        'isHealthy': isHealthy,
        'healthStatus': healthStatus
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Test recovery service
  Future<Map<String, dynamic>> _testRecoveryService() async {
    try {
      final recoveryService = AppCheckRecoveryService();
      final recoveryResult = await recoveryService.attemptRecovery();

      return {'success': true, 'recoverySuccessful': recoveryResult};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get detailed diagnostic information
  Map<String, dynamic> getDiagnostics() {
    try {
      final appCheckStatus = FirebaseService.getAppCheckStatus();
      final recoveryService = AppCheckRecoveryService();

      return {
        'timestamp': DateTime.now().toIso8601String(),
        'appCheckStatus': appCheckStatus,
        'isHealthy': recoveryService.isHealthy(),
        'config': {
          'enableAppCheck': AppConfig.enableAppCheck,
          'tokenRefreshIntervalMinutes': AppConfig.tokenRefreshIntervalMinutes,
          'minFetchIntervalSeconds': AppConfig.minFetchIntervalSeconds,
        }
      };
    } catch (e) {
      return {
        'timestamp': DateTime.now().toIso8601String(),
        'error': e.toString()
      };
    }
  }

  /// Test specific error scenarios
  Map<String, dynamic> testErrorScenarios() {
    final recoveryService = AppCheckRecoveryService();

    final testErrors = [
      'Too many attempts',
      'App Check failed',
      'Device attestation failed',
      'Token expired',
      'Unknown error'
    ];

    final results = <String, Map<String, String>>{};

    for (final error in testErrors) {
      results[error] = recoveryService.getErrorInfo(error);
    }

    return results;
  }
}
