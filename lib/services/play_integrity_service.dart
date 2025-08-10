import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class PlayIntegrityService {
  static const MethodChannel _channel = MethodChannel('play_integrity');
  static final PlayIntegrityService _instance =
      PlayIntegrityService._internal();
  factory PlayIntegrityService() => _instance;
  PlayIntegrityService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Get an integrity token for purchase verification
  Future<String?> getIntegrityToken() async {
    try {
      final String? token = await _channel.invokeMethod('getIntegrityToken');
      return token;
    } catch (e) {
      print('Error getting integrity token: $e');
      return null;
    }
  }

  /// Verify integrity token on the server side
  Future<bool> verifyIntegrityToken(String token) async {
    if (kDebugMode) return true; // Skip server verification in debug
    try {
      final result = await _functions
          .httpsCallable('verifyIntegrityToken')
          .call({'token': token});

      return result.data['success'] ?? false;
    } catch (e) {
      print('Error verifying integrity token: $e');
      return false;
    }
  }

  /// Check device integrity before processing purchase
  Future<bool> checkDeviceIntegrity() async {
    if (kDebugMode) return true; // Skip checks in debug builds
    try {
      final token = await getIntegrityToken();
      if (token == null) {
        print('Failed to get integrity token');
        return false;
      }

      return await verifyIntegrityToken(token);
    } catch (e) {
      print('Error checking device integrity: $e');
      return false;
    }
  }
}
