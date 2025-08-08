import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'device_service.dart';

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

      // Initialize App Check with Debug provider for development
      // Use AndroidProvider.debug for debug builds, PlayIntegrity for release (production)
      await FirebaseAppCheck.instance.activate(
        androidProvider: bool.fromEnvironment('dart.vm.product')
            ? AndroidProvider.playIntegrity
            : AndroidProvider.debug,
      );
      print(
          '✅ App Check activated with ${bool.fromEnvironment('dart.vm.product') ? 'PlayIntegrity' : 'Debug'} provider');

      _functions = FirebaseFunctions.instance;
      _isInitialized = true;
      _initializationError = null;

      print('✅ Firebase initialized successfully with App Check');
      print(
          '🔒 App Check enabled with ${bool.fromEnvironment('dart.vm.product') ? 'PlayIntegrity' : 'Debug'} provider for ${bool.fromEnvironment('dart.vm.product') ? 'production' : 'development'}');
    } catch (e) {
      print('❌ Firebase initialization failed: $e');
      _initializationError = e.toString();
      _isInitialized = true; // Mark as initialized to prevent repeated attempts
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

      // Handle specific Firebase errors
      String errorMessage = e.toString();
      if (errorMessage.contains('Device not found')) {
        errorMessage = 'Device not found';
      } else if (errorMessage.contains('PERMISSION_DENIED')) {
        errorMessage = 'Permission denied';
      } else if (errorMessage.contains('UNAVAILABLE')) {
        errorMessage = 'Service unavailable';
      } else if (errorMessage.contains('timed out')) {
        errorMessage = 'Request timed out';
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
