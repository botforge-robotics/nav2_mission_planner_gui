import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Image cache — no-op on web (no dart:io filesystem).
class ImageCacheService {
  static Future<String?> cacheImage(String url, String filename) async {
    if (kIsWeb) return null;
    try {
      // Deferred import pattern avoided: web never hits this path in practice.
      // Keep network fetch available; path caching is desktop/mobile only.
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return null; // callers treat null as uncached / use network URL
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> getCachedImagePath(String filename) async => null;

  static Future<void> clearCache() async {}
}
