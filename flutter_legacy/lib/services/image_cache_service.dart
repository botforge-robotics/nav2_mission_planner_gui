import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ImageCacheService {
  static const String _cacheDir = 'cached_images';

  // Get cache directory
  static Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/$_cacheDir');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  // Download and cache image
  static Future<String?> cacheImage(String url, String filename) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final cacheDir = await _getCacheDirectory();
        final file = File('${cacheDir.path}/$filename');
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e) {
      // Silent error handling
    }
    return null;
  }

  // Get cached image path
  static Future<String?> getCachedImagePath(String filename) async {
    final cacheDir = await _getCacheDirectory();
    final file = File('${cacheDir.path}/$filename');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  // Clear all cached images
  static Future<void> clearCachedImages() async {
    final cacheDir = await _getCacheDirectory();
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  }

  // Check if image is cached
  static Future<bool> isImageCached(String filename) async {
    final cacheDir = await _getCacheDirectory();
    final file = File('${cacheDir.path}/$filename');
    return await file.exists();
  }
}
