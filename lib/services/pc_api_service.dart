import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// PC-side Express API (claim / heartbeat / nearby / defaults).
/// In Docker, nginx proxies `/api` → `:3001`.
class PcApiService {
  PcApiService._();

  static String get baseUrl {
    // Same origin when served behind nginx; override for local flutter run.
    const fromEnv = String.fromEnvironment('PC_API_BASE', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) {
      // Relative to the page origin (http://localhost:8080/api/...)
      return '';
    }
    return 'http://127.0.0.1:3001';
  }

  static Uri _uri(String path, [Map<String, String>? query]) {
    final root = baseUrl;
    if (root.isEmpty) {
      return Uri(path: path, queryParameters: query);
    }
    return Uri.parse('$root$path').replace(queryParameters: query);
  }

  static Future<Map<String, dynamic>?> getClaim() async {
    try {
      final res = await http.get(_uri('/api/claim')).timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;
      if (res.body.isEmpty || res.body == 'null') return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> claim({
    required String ip,
    required String port,
    required String name,
    String? id,
  }) async {
    try {
      final res = await http
          .post(
            _uri('/api/claim'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'ip': ip,
              'port': port,
              'name': name,
              if (id != null) 'id': id,
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> releaseClaim() async {
    try {
      await http.delete(_uri('/api/claim')).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> heartbeat() async {
    try {
      final res =
          await http.get(_uri('/api/heartbeat')).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> nearby({bool scan = false}) async {
    try {
      final res = await http
          .get(_uri('/api/nearby', {if (scan) 'scan': '1'}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      if (data is Map && data['robots'] is List) {
        return (data['robots'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isRosbridgeReachable(String ip, String port) async {
    try {
      final res = await http
          .get(_uri('/api/probe', {'ip': ip, 'port': port}))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return true; // allow connect attempt
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['online'] == true;
    } catch (_) {
      return true;
    }
  }
}
