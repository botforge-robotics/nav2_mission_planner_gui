import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ApiService {
  static const String baseUrl = 'https://n2mp.botforge.in/api';

  // Test API connectivity
  static Future<bool> testConnectivity() async {
    try {
      final url = Uri.parse('$baseUrl/device/register');

      final httpClient = HttpClient();
      httpClient.badCertificateCallback = (cert, host, port) => true;

      final request = await httpClient.postUrl(url);
      request.headers.set('Content-Type', 'application/json');

      final body = {
        'deviceId': 'test',
        'appVersion': '1.0.0',
        'platform': 'android',
        'model': 'test',
        'manufacturer': 'test',
      };

      request.write(jsonEncode(body));
      final response = await request.close();

      // Consider any 2xx-5xx response as server reachable
      return response.statusCode >= 200 && response.statusCode < 600;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> registerDevice(
      Map<String, dynamic> deviceData) async {
    try {
      final url = Uri.parse('$baseUrl/device/register');

      final httpClient = HttpClient();
      httpClient.badCertificateCallback = (cert, host, port) => true;

      final request = await httpClient.postUrl(url);
      request.headers.set('Content-Type', 'application/json');

      request.write(jsonEncode(deviceData));
      final response = await request.close();

      final responseBody = await response.transform(utf8.decoder).join();
      final responseData = jsonDecode(responseBody);

      return {
        'statusCode': response.statusCode,
        'body': responseData,
      };
    } catch (e) {
      return {
        'statusCode': 500,
        'body': {'error': e.toString()},
      };
    }
  }

  static Future<Map<String, dynamic>> verifyLicense({
    required String deviceId,
    required String token,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/license/verify');

      final httpClient = HttpClient();
      httpClient.badCertificateCallback = (cert, host, port) => true;

      final request = await httpClient.postUrl(url);
      request.headers.set('Content-Type', 'application/json');

      final body = {
        'androidId': deviceId, // Changed from 'deviceId' to 'androidId'
        'token': token,
      };

      request.write(jsonEncode(body));
      final response = await request.close();

      final responseBody = await response.transform(utf8.decoder).join();
      final responseData = jsonDecode(responseBody);

      return {
        'statusCode': response.statusCode,
        'body': responseData,
      };
    } catch (e) {
      return {
        'statusCode': 500,
        'body': {'error': e.toString()},
      };
    }
  }

  static Future<Map<String, dynamic>> generateShortId(String deviceId) async {
    try {
      final url = Uri.parse('$baseUrl/device/alias/generate');

      final httpClient = HttpClient();
      httpClient.badCertificateCallback = (cert, host, port) => true;

      final request = await httpClient.postUrl(url);
      request.headers.set('Content-Type', 'application/json');

      final body = {
        'deviceId': deviceId,
      };

      request.write(jsonEncode(body));
      final response = await request.close();

      final responseBody = await response.transform(utf8.decoder).join();
      final responseData = jsonDecode(responseBody);

      return {
        'statusCode': response.statusCode,
        'body': responseData,
      };
    } catch (e) {
      return {
        'statusCode': 500,
        'body': {'error': e.toString()},
      };
    }
  }

  static Future<Map<String, dynamic>> getTrialStatus(String deviceId) async {
    try {
      final url = Uri.parse('$baseUrl/trial/status');

      final httpClient = HttpClient();
      httpClient.badCertificateCallback = (cert, host, port) => true;

      final request = await httpClient.getUrl(url);
      request.headers.set('Content-Type', 'application/json');

      final response = await request.close();

      final responseBody = await response.transform(utf8.decoder).join();
      final responseData = jsonDecode(responseBody);

      return {
        'statusCode': response.statusCode,
        'body': responseData,
      };
    } catch (e) {
      return {
        'statusCode': 500,
        'body': {'error': e.toString()},
      };
    }
  }
}
