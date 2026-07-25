import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Service to manage first-time user guides and highlights
class GuideService {
  static const String _guideShownKey = 'guide_shown_';

  /// Check if a specific guide has been shown before
  static Future<bool> isGuideShown(String guideId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_guideShownKey$guideId') ?? false;
    } catch (e) {
      debugPrint('❌ Error checking guide status: $e');
      return false;
    }
  }

  /// Mark a specific guide as shown
  static Future<void> markGuideAsShown(String guideId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_guideShownKey$guideId', true);
      debugPrint('✅ Guide marked as shown: $guideId');
    } catch (e) {
      debugPrint('❌ Error marking guide as shown: $e');
    }
  }

  /// Reset a specific guide to show again
  static Future<void> resetGuide(String guideId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_guideShownKey$guideId');
      debugPrint('🔄 Guide reset: $guideId');
    } catch (e) {
      debugPrint('❌ Error resetting guide: $e');
    }
  }

  /// Reset all guides (useful for testing or user preference)
  static Future<void> resetAllGuides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final guideKeys = keys.where((key) => key.startsWith(_guideShownKey));

      for (final key in guideKeys) {
        await prefs.remove(key);
      }
      debugPrint('🔄 All guides reset');
    } catch (e) {
      debugPrint('❌ Error resetting all guides: $e');
    }
  }

  /// Get all guide IDs that have been shown
  static Future<List<String>> getShownGuides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final guideKeys = keys.where((key) => key.startsWith(_guideShownKey));

      return guideKeys
          .map((key) => key.replaceFirst(_guideShownKey, ''))
          .toList();
    } catch (e) {
      debugPrint('❌ Error getting shown guides: $e');
      return [];
    }
  }

  /// Check if any guides have been shown
  static Future<bool> hasAnyGuidesBeenShown() async {
    final shownGuides = await getShownGuides();
    return shownGuides.isNotEmpty;
  }
}

/// Guide IDs for different app features
class GuideIds {
  static const String connectionGuide = 'connection_guide';
  static const String teleopGuide = 'teleop_guide';
  static const String mappingGuide = 'mapping_guide';
  static const String navigationGuide = 'navigation_guide';
  static const String missionGuide = 'mission_guide';
  static const String settingsGuide = 'settings_guide';
}
