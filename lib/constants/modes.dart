import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/branding_provider.dart';

enum AppModes {
  teleop,
  mapping,
  navigation,
  settings,
  dashboard,
  dock,
  robotStatus,
  alerts,
  tools,
}

class ModeColors {
  // Static method to get mode colors with dynamic branding
  static Map<AppModes, Color> getModeColorMap(BuildContext context) {
    // Import BrandingProvider dynamically to avoid circular dependencies
    final brandingProvider =
        Provider.of<BrandingProvider>(context, listen: false);
    final themeColor = brandingProvider.themeColor;

    return {
      AppModes.teleop: themeColor,
      AppModes.mapping: themeColor,
      AppModes.navigation: themeColor,
      AppModes.settings: themeColor,
      AppModes.dashboard: themeColor,
      AppModes.dock: themeColor,
      AppModes.robotStatus: themeColor,
      AppModes.alerts: themeColor,
      AppModes.tools: themeColor,
    };
  }

  // Fallback static map for cases where context is not available
  static const Map<AppModes, Color> fallbackModeColorMap = {
    AppModes.teleop: Colors.orange,
    AppModes.mapping: Colors.orange,
    AppModes.navigation: Colors.orange,
    AppModes.settings: Colors.orange,
    AppModes.dashboard: Colors.orange,
    AppModes.dock: Colors.orange,
    AppModes.robotStatus: Colors.orange,
    AppModes.alerts: Colors.orange,
    AppModes.tools: Colors.orange,
  };
}
