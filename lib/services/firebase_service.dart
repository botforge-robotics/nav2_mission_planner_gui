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

  // Initialize Firebase with App Check
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🚀 Starting Firebase initialization...');
      await Firebase.initializeApp();
      debugPrint('✅ Firebase.initializeApp() completed');

      // Initialize App Check (disable on client if requested)
      if (AppConfig.enableAppCheck) {
        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
        );
        if (kDebugMode) {
          // Force a token fetch to trigger printing of the App Check debug token in Logcat
          try {
            await FirebaseAppCheck.instance.getToken(true);
            // This does not debugPrint the token here; the native SDK logs it to Logcat.
            // Check Logcat for a line like: "App Check debug token: <TOKEN>"
          } catch (_) {
            // ignore
          }
        }
      }
      debugPrint(
          '✅ App Check activated with ${kDebugMode ? 'Debug' : 'PlayIntegrity'} provider');

      _functions = FirebaseFunctions.instance;
      // Set emulator in dev if needed (optional)
      // _functions!.useFunctionsEmulator('localhost', 5001);
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

      // Handle specific Firebase errors (short, user-friendly)
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
