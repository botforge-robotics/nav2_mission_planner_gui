import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_config.dart';

class FirebaseService {
  static FirebaseFunctions? _functions;
  static bool _isInitialized = false;
  static String? _initializationError;

  // App Check token management
  static String? _cachedAppCheckToken;
  static DateTime? _lastTokenFetch;
  static Duration get _tokenRefreshInterval =>
      Duration(minutes: AppConfig.tokenRefreshIntervalMinutes);
  static Duration get _minFetchInterval =>
      Duration(seconds: AppConfig.minFetchIntervalSeconds);

  // Initialize Firebase with App Check
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🚀 Starting Firebase initialization...');
      await Firebase.initializeApp();
      debugPrint('✅ Firebase.initializeApp() completed');

      // Initialize App Check with proper configuration
      if (AppConfig.enableAppCheck) {
        await _initializeAppCheck();
      }
      debugPrint(
          '✅ App Check activated with ${kDebugMode ? 'Debug' : 'PlayIntegrity'} provider');

      _functions = FirebaseFunctions.instance;
      _isInitialized = true;
      _initializationError = null;

      if (AppConfig.enableAppCheck) {
        debugPrint('✅ Firebase initialized with App Check');
      } else {
        debugPrint('ℹ️ App Check disabled on client (dev mode)');
      }
    } catch (e) {
      debugPrint('❌ Firebase initialization failed: $e');
      _initializationError = e.toString();
      _isInitialized = true; // Mark as initialized to prevent repeated attempts
    }
  }

  // Initialize App Check with proper error handling and rate limiting
  static Future<void> _initializeAppCheck() async {
    try {
      // Configure App Check provider based on build mode
      if (kDebugMode) {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.debug,
        );
        debugPrint('✅ App Check activated with Debug provider');
      } else {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.playIntegrity,
        );
        debugPrint('✅ App Check activated with Play Integrity provider');
      }

      // Pre-fetch initial token to avoid delays
      await _getAppCheckToken();
    } catch (e) {
      debugPrint('❌ App Check initialization failed: $e');
      // Don't fail the entire initialization, just log the error
    }
  }

  // Get App Check token with caching and rate limiting
  static Future<String?> _getAppCheckToken() async {
    try {
      // Check if we have a valid cached token
      if (_cachedAppCheckToken != null && _lastTokenFetch != null) {
        final timeSinceLastFetch = DateTime.now().difference(_lastTokenFetch!);
        if (timeSinceLastFetch < _tokenRefreshInterval) {
          debugPrint(
              '✅ Using cached App Check token (age: ${timeSinceLastFetch.inMinutes}m)');
          return _cachedAppCheckToken;
        }
      }

      // Check rate limiting
      if (_lastTokenFetch != null) {
        final timeSinceLastFetch = DateTime.now().difference(_lastTokenFetch!);
        if (timeSinceLastFetch < _minFetchInterval) {
          debugPrint(
              '⏳ Rate limiting App Check token fetch (waiting ${(_minFetchInterval - timeSinceLastFetch).inSeconds}s)');
          // Return cached token if available, otherwise wait
          if (_cachedAppCheckToken != null) {
            return _cachedAppCheckToken;
          }
          await Future.delayed(_minFetchInterval - timeSinceLastFetch);
        }
      }

      debugPrint('🔄 Fetching new App Check token...');
      final token = await FirebaseAppCheck.instance.getToken(true);
      _cachedAppCheckToken = token;
      _lastTokenFetch = DateTime.now();

      debugPrint('✅ App Check token fetched successfully');
      return token;
    } catch (e) {
      debugPrint('❌ Failed to get App Check token: $e');

      // If we have a cached token, use it even if expired
      if (_cachedAppCheckToken != null) {
        debugPrint('⚠️ Using expired cached token due to fetch failure');
        return _cachedAppCheckToken;
      }

      return null;
    }
  }

  // Ensure App Check token is available before making calls
  static Future<void> _ensureAppCheckToken() async {
    if (!AppConfig.enableAppCheck) return;

    try {
      final token = await _getAppCheckToken();
      if (token == null) {
        debugPrint('⚠️ No App Check token available');
      }
    } catch (e) {
      debugPrint('❌ Error ensuring App Check token: $e');
    }
  }

  // Manually refresh App Check token (useful for recovery from errors)
  static Future<String?> refreshAppCheckToken() async {
    if (!AppConfig.enableAppCheck) return null;

    try {
      debugPrint('🔄 Manually refreshing App Check token...');
      _cachedAppCheckToken = null; // Clear cache to force refresh
      _lastTokenFetch = null; // Reset timing
      return await _getAppCheckToken();
    } catch (e) {
      debugPrint('❌ Failed to manually refresh App Check token: $e');
      return null;
    }
  }

  // Get current App Check token status
  static Map<String, dynamic> getAppCheckStatus() {
    return {
      'enabled': AppConfig.enableAppCheck,
      'hasCachedToken': _cachedAppCheckToken != null,
      'lastFetchTime': _lastTokenFetch?.toIso8601String(),
      'tokenAge': _lastTokenFetch != null
          ? DateTime.now().difference(_lastTokenFetch!).inMinutes
          : null,
      'nextRefreshIn': _lastTokenFetch != null
          ? _tokenRefreshInterval.inMinutes -
              DateTime.now().difference(_lastTokenFetch!).inMinutes
          : null,
    };
  }

  static Future<User?> ensureSignedInAnonymously() async {
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser != null) return auth.currentUser;
      final cred = await auth.signInAnonymously();
      return cred.user;
    } catch (e) {
      return null;
    }
  }

  // Call Cloud Function with App Check
  static Future<Map<String, dynamic>> callCloudFunction(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    try {
      if (_functions == null) {
        debugPrint('❌ Firebase Functions not available');
        if (_initializationError != null) {
          debugPrint('📋 Initialization error: $_initializationError');
        }
        return {
          'success': false,
          'error': {
            'message': 'Firebase Functions not available',
            'details':
                _initializationError ?? 'Firebase not properly initialized'
          },
        };
      }

      // Ensure App Check token is available before making the call
      await _ensureAppCheckToken();

      debugPrint('📞 Calling Cloud Function: $functionName');
      debugPrint('📊 Data: $data');

      final callable = _functions!.httpsCallable(functionName);

      // Add timeout to prevent hanging
      final result = await callable.call(data).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Cloud function call timed out after 30 seconds');
        },
      );

      debugPrint('✅ Cloud Function call successful');
      debugPrint('📊 Response: ${result.data}');

      return result.data;
    } catch (e) {
      debugPrint('❌ Cloud Function call failed: $e');

      // Handle specific Firebase errors including App Check errors
      String errorMessage = 'Service unavailable. Please try again.';
      final err = e.toString().toLowerCase();
      if (err.contains('permission_denied')) {
        errorMessage = 'Permission denied.';
      } else if (err.contains('unavailable')) {
        errorMessage = 'Service unavailable.';
      } else if (err.contains('timed out')) {
        errorMessage = 'Request timed out.';
      } else if (err.contains('unauthenticated')) {
        errorMessage = 'Authentication required.';
      } else if (err.contains('app attestation failed')) {
        errorMessage = 'Device attestation failed.';
      } else if (err.contains('too many attempts')) {
        errorMessage = 'Too many requests. Please wait a moment and try again.';
      } else if (err.contains('app check')) {
        errorMessage = 'Device verification failed. Please restart the app.';
      }

      // Log App Check errors for debugging
      if (err.contains('too many attempts') || err.contains('app check')) {
        debugPrint('⚠️ App Check error detected: $e');
        debugPrint('📊 Current App Check status: ${getAppCheckStatus()}');
      }

      return {
        'success': false,
        'error': {
          'message': errorMessage,
          'details': e.toString(),
        },
      };
    }
  }

  // Health check function - replaces API connectivity test
  static Future<Map<String, dynamic>> healthCheck() async {
    try {
      debugPrint('🏥 Testing health check...');
      return await callCloudFunction('healthCheck', {});
    } catch (e) {
      debugPrint('❌ Health check failed: $e');
      return {
        'success': false,
        'error': {
          'message': 'Health check failed',
          'details': e.toString(),
        },
      };
    }
  }

  // Test connectivity using health check
  static Future<bool> testConnectivity() async {
    try {
      final result = await healthCheck();
      return result['success'] == true;
    } catch (e) {
      debugPrint('❌ Connectivity test failed: $e');
      return false;
    }
  }
}
