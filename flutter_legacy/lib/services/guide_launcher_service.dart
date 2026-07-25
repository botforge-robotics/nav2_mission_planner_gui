import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../providers/branding_provider.dart';

/// Service to handle launching guide URLs and external links
class GuideLauncherService {
  /// Launch a guide URL in the browser
  static Future<bool> launchGuideUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        final launched =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) {
          debugPrint('✅ Guide URL opened in browser: $url');
          return true;
        } else {
          debugPrint('❌ Failed to open guide URL: $url');
          // Fallback to clipboard if browser launch fails
          await Clipboard.setData(ClipboardData(text: url));
          debugPrint('📋 Guide URL copied to clipboard as fallback: $url');
          return true;
        }
      } else {
        debugPrint('❌ Cannot launch guide URL: $url');
        // Fallback to clipboard
        await Clipboard.setData(ClipboardData(text: url));
        debugPrint('📋 Guide URL copied to clipboard as fallback: $url');
        return true;
      }
    } catch (e) {
      debugPrint('❌ Error launching guide URL: $e');
      // Final fallback to clipboard
      try {
        await Clipboard.setData(ClipboardData(text: url));
        debugPrint('📋 Guide URL copied to clipboard as final fallback: $url');
        return true;
      } catch (clipboardError) {
        debugPrint('❌ Error copying to clipboard: $clipboardError');
        return false;
      }
    }
  }

  /// Launch the Nav2 Mission Planner GitHub guide
  static Future<bool> launchNav2Guide() async {
    const guideUrl =
        'https://github.com/botforge-robotics/nav2_mission_planner';
    return await launchGuideUrl(guideUrl);
  }

  /// Launch a specific section of the guide
  static Future<bool> launchGuideSection(String section) async {
    const baseUrl = 'https://github.com/botforge-robotics/nav2_mission_planner';
    final sectionUrl = '$baseUrl#$section';
    return await launchGuideUrl(sectionUrl);
  }

  /// Show a snackbar with guide information
  static void showGuideInfo(BuildContext context, String message) {
    final brandingProvider =
        Provider.of<BrandingProvider>(context, listen: false);
    final themeColor = brandingProvider.themeColor;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        backgroundColor: themeColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Open Guide',
          textColor: Colors.white,
          onPressed: () => launchNav2Guide(),
        ),
      ),
    );
  }

  /// Show a dialog with guide information
  static Future<void> showGuideDialog(
    BuildContext context, {
    required String title,
    required String content,
    String? actionLabel,
    VoidCallback? onAction,
  }) async {
    final brandingProvider =
        Provider.of<BrandingProvider>(context, listen: false);
    final themeColor = brandingProvider.themeColor;

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: Row(
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: themeColor,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          content,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          if (actionLabel != null && onAction != null)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                onAction();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
              ),
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}
