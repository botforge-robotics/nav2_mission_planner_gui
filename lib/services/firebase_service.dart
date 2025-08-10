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
      print('🚀 Starting Firebase initialization...');
      await Firebase.initializeApp();
      print('✅ Firebase.initializeApp() completed');

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
            // This does not print the token here; the native SDK logs it to Logcat.
            // Check Logcat for a line like: "App Check debug token: <TOKEN>"
          } catch (_) {
            // ignore
          }
        }
      }
      print(
          '✅ App Check activated with ${kDebugMode ? 'Debug' : 'PlayIntegrity'} provider');

      _functions = FirebaseFunctions.instance;
      // Set emulator in dev if needed (optional)
      // _functions!.useFunctionsEmulator('localhost', 5001);
      _isInitialized = true;
      _initializationError = null;

      if (AppConfig.enableAppCheck) {
        print('✅ Firebase initialized with App Check');
      } else {
        print('ℹ️ App Check disabled on client (dev mode)');
      }
    } catch (e) {
      print('❌ Firebase initialization failed: $e');
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
        print('❌ Firebase Functions not available');
        if (_initializationError != null) {
          print('📋 Initialization error: $_initializationError');
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

      print('📞 Calling Cloud Function: $functionName');
      print('📊 Data: $data');

      final callable = _functions!.httpsCallable(functionName);

      // Add timeout to prevent hanging
      final result = await callable.call(data).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Cloud function call timed out after 30 seconds');
        },
      );

      print('✅ Cloud Function call successful');
      print('📊 Response: ${result.data}');

      return result.data;
    } catch (e) {
      print('❌ Cloud Function call failed: $e');

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
      print('🏥 Testing health check...');
      return await callCloudFunction('healthCheck', {});
    } catch (e) {
      print('❌ Health check failed: $e');
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
      print('❌ Connectivity test failed: $e');
      return false;
    }
  }
}
