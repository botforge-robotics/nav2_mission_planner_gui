import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/license_model.dart';
import '../services/secure_storage_service.dart';
import '../services/image_cache_service.dart';

class BrandingProvider extends ChangeNotifier {
  LicenseData? _organizationData;
  String? _cachedFaviconPath;
  String? _cachedLogoPath;

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
    if (_organizationData?.licenseType == 'organization') {
      // Use cached path if available, otherwise use network URL or default
      return _cachedFaviconPath ??
          _organizationData?.faviconUrl ??
          _defaultBranding['faviconUrl']!;
    }
    return _defaultBranding['faviconUrl']!;
  }

  String get logoUrl {
    if (_organizationData?.licenseType == 'organization') {
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
      _organizationData?.licenseType == 'organization';

  // Update branding when organization data changes
  void updateOrganizationBranding(LicenseData? data) {
    _organizationData = data;
    _loadCachedImagePaths();
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
    if (_organizationData?.licenseType == 'organization') {
      _cachedFaviconPath =
          await ImageCacheService.getCachedImagePath('favicon');
      _cachedLogoPath = await ImageCacheService.getCachedImagePath('logo');
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
      // Fallback to default orange
      return const Color(0xFFFF9800);
    }
  }
}
