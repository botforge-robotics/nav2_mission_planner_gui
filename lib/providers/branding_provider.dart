import 'package:flutter/material.dart';

class BrandingProvider extends ChangeNotifier {
  bool _isInitialized = false;

  BrandingProvider() {
    // Initialize immediately
    _isInitialized = true;
  }

  // Default branding
  static const Map<String, String> _defaultBranding = {
    'appTitle': 'Nav2 Mission Planner',
    'faviconUrl': 'assets/favicon_light.png',
    'themeColor': '#f2771a',
    'logoUrl': 'assets/sticker.png',
    'tagLine': 'Crafting autonomous solutions with passion and precision.',
    'supportEmail': 'reachus@botforge.in',
    'website': 'https://botforge.in',
    'footerCredits': 'Made with ❤️ for ROS2 developers',
  };

  // Getters for branding
  String get appTitle => _defaultBranding['appTitle']!;

  String get faviconUrl => _defaultBranding['faviconUrl']!;

  String get logoUrl => _defaultBranding['logoUrl']!;

  Color get themeColor {
    final colorHex = _defaultBranding['themeColor']!;
    return _parseHexColor(colorHex);
  }

  String get tagLine => _defaultBranding['tagLine']!;

  String get supportEmail => _defaultBranding['supportEmail']!;

  String get website => _defaultBranding['website']!;

  String get footerCredits => _defaultBranding['footerCredits']!;

  // Check if branding is initialized
  bool get isInitialized => _isInitialized;

  // Parse hex color string to Color
  Color _parseHexColor(String hexColor) {
    try {
      hexColor = hexColor.replaceAll('#', '');
      if (hexColor.length == 6) {
        hexColor = 'FF$hexColor'; // Add alpha channel
      }
      return Color(int.parse(hexColor, radix: 16));
    } catch (e) {
      // Fallback to a neutral blue color
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
    return Image.asset(
      _defaultBranding['faviconUrl']!,
      height: height,
      width: width,
      fit: fit,
    );
  }

  // Helper method to create logo image widget
  Widget createLogoWidget({
    double? height,
    double? width,
    BoxFit fit = BoxFit.contain,
    Widget? fallback,
  }) {
    return Image.asset(
      _defaultBranding['logoUrl']!,
      height: height,
      width: width,
      fit: fit,
    );
  }
}
