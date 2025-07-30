import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../models/license_model.dart';
import '../services/secure_storage_service.dart';
import '../services/image_cache_service.dart';

class BrandingProvider extends ChangeNotifier {
  LicenseData? _organizationData;
  String? _cachedFaviconPath;
  String? _cachedLogoPath;
  bool _isInitialized = false;
  static bool _globalInitialized = false;

  BrandingProvider() {
    // Initialize cached branding synchronously
    _initializeCachedBrandingSync();
  }

  // Initialize cached branding synchronously
  void _initializeCachedBrandingSync() {
    // Load cached branding asynchronously but don't wait
    _loadCachedBrandingAsync();
  }

  // Load cached branding asynchronously
  Future<void> _loadCachedBrandingAsync() async {
    if (_isInitialized || _globalInitialized) {
      return;
    }

    try {
      final cachedData = await SecureStorageService.getOrganizationBranding();
      if (cachedData != null) {
        _organizationData = cachedData;
        await _loadCachedImagePaths();
        notifyListeners();
      }
      _isInitialized = true;
      _globalInitialized = true;
    } catch (e) {
      // Silent error handling
    }
  }

  // Default individual branding (no caching needed)
  static const Map<String, String> _defaultBranding = {
    'appTitle': 'Nav2 Mission Planner',
    'faviconUrl': 'assets/favicon_light.png',
    'themeColor': '#829800',
    'logoUrl': 'assets/sticker.png',
    'tagLine': 'Crafting autonomous solutions with passion and precision.',
    'supportEmail': 'reachus@botforge.in',
    'website': 'https://botforge.in',
    'footerCredits': 'Made with ❤️ for ROS2 developers',
  };

  // Getters for dynamic branding
  String get appTitle =>
      _organizationData?.appTitle ?? _defaultBranding['appTitle']!;

  String get faviconUrl {
    if (_organizationData?.licenseType == 'organization' ||
        _organizationData?.licenseType == 'organisation') {
      // Use cached path if available, otherwise use network URL or default
      return _cachedFaviconPath ??
          _organizationData?.faviconUrl ??
          _defaultBranding['faviconUrl']!;
    }
    return _defaultBranding['faviconUrl']!;
  }

  String get logoUrl {
    if (_organizationData?.licenseType == 'organization' ||
        _organizationData?.licenseType == 'organisation') {
      // Use cached path if available, otherwise use network URL or default
      return _cachedLogoPath ??
          _organizationData?.logoUrl ??
          _defaultBranding['logoUrl']!;
    }
    return _defaultBranding['logoUrl']!;
  }

  Color get themeColor {
    final colorHex =
        _organizationData?.themeColor ?? _defaultBranding['themeColor']!;
    return _parseHexColor(colorHex);
  }

  String get tagLine =>
      _organizationData?.tagLine ?? _defaultBranding['tagLine']!;

  String get supportEmail =>
      _organizationData?.supportEmail ?? _defaultBranding['supportEmail']!;

  String get website =>
      _organizationData?.website ?? _defaultBranding['website']!;

  String get footerCredits =>
      _organizationData?.footerCredits ?? _defaultBranding['footerCredits']!;

  bool get isOrganizationLicense =>
      _organizationData?.licenseType == 'organization' ||
      _organizationData?.licenseType == 'organisation';

  // Check if branding is initialized
  bool get isInitialized => _isInitialized;

  // Update branding when organization data changes
  Future<void> updateOrganizationBranding(LicenseData? data) async {
    _organizationData = data;
    await _loadCachedImagePaths();
    notifyListeners();
  }

  // Load cached organization branding on app start
  Future<void> loadCachedBranding() async {
    final cachedData = await SecureStorageService.getOrganizationBranding();
    if (cachedData != null) {
      _organizationData = cachedData;
      await _loadCachedImagePaths();
      notifyListeners();
    }
  }

  // Load cached image paths
  Future<void> _loadCachedImagePaths() async {
    if (_organizationData?.licenseType == 'organization' ||
        _organizationData?.licenseType == 'organisation') {
      _cachedFaviconPath =
          await ImageCacheService.getCachedImagePath('favicon');
      _cachedLogoPath = await ImageCacheService.getCachedImagePath('logo');

      // If cached images don't exist but URLs are available, cache them
      if (_cachedFaviconPath == null && _organizationData?.faviconUrl != null) {
        _cachedFaviconPath = await ImageCacheService.cacheImage(
          _organizationData!.faviconUrl!,
          'favicon',
        );
      }

      if (_cachedLogoPath == null && _organizationData?.logoUrl != null) {
        _cachedLogoPath = await ImageCacheService.cacheImage(
          _organizationData!.logoUrl!,
          'logo',
        );
      }
    } else {
      _cachedFaviconPath = null;
      _cachedLogoPath = null;
    }
  }

  // Clear organization branding (for individual licenses)
  Future<void> clearOrganizationBranding() async {
    _organizationData = null;
    _cachedFaviconPath = null;
    _cachedLogoPath = null;
    await SecureStorageService.clearOrganizationBranding();
    notifyListeners();
  }

  // Parse hex color string to Color
  Color _parseHexColor(String hexColor) {
    try {
      hexColor = hexColor.replaceAll('#', '');
      if (hexColor.length == 6) {
        hexColor = 'FF$hexColor'; // Add alpha channel
      }
      return Color(int.parse(hexColor, radix: 16));
    } catch (e) {
      // Fallback to a neutral blue color instead of hardcoded orange
      return const Color(0xFF2196F3);
    }
  }

  // Helper method to create favicon image widget
  Widget createFaviconWidget({
    double? height,
    double? width,
    BoxFit fit = BoxFit.contain,
    Widget? fallback,
  }) {
    if (_cachedFaviconPath != null) {
      // Use cached file image
      return Image.file(
        File(_cachedFaviconPath!),
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return fallback ??
              _getDefaultFaviconWidget(height: height, width: width, fit: fit);
        },
      );
    } else if (_organizationData?.faviconUrl != null &&
        (_organizationData?.licenseType == 'organization' ||
            _organizationData?.licenseType == 'organisation')) {
      // Use network image for organization
      return Image.network(
        _organizationData!.faviconUrl!,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return fallback ??
              _getDefaultFaviconWidget(height: height, width: width, fit: fit);
        },
      );
    } else {
      // Use default asset image
      return _getDefaultFaviconWidget(height: height, width: width, fit: fit);
    }
  }

  // Helper method to create logo image widget
  Widget createLogoWidget({
    double? height,
    double? width,
    BoxFit fit = BoxFit.contain,
    Widget? fallback,
  }) {
    if (_cachedLogoPath != null) {
      // Use cached file image
      return Image.file(
        File(_cachedLogoPath!),
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return fallback ??
              _getDefaultLogoWidget(height: height, width: width, fit: fit);
        },
      );
    } else if (_organizationData?.logoUrl != null &&
        (_organizationData?.licenseType == 'organization' ||
            _organizationData?.licenseType == 'organisation')) {
      // Use network image for organization
      return Image.network(
        _organizationData!.logoUrl!,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return fallback ??
              _getDefaultLogoWidget(height: height, width: width, fit: fit);
        },
      );
    } else {
      // Use default asset image
      return _getDefaultLogoWidget(height: height, width: width, fit: fit);
    }
  }

  // Default favicon widget
  Widget _getDefaultFaviconWidget({
    double? height,
    double? width,
    BoxFit fit = BoxFit.contain,
  }) {
    return Image.asset(
      _defaultBranding['faviconUrl']!,
      height: height,
      width: width,
      fit: fit,
    );
  }

  // Default logo widget
  Widget _getDefaultLogoWidget({
    double? height,
    double? width,
    BoxFit fit = BoxFit.contain,
  }) {
    return Image.asset(
      _defaultBranding['logoUrl']!,
      height: height,
      width: width,
      fit: fit,
    );
  }
}
