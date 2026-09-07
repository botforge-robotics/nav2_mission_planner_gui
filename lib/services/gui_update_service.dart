import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class GuiReleaseInfo {
  const GuiReleaseInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    required this.releaseName,
    required this.releaseNotes,
    required this.publishedAt,
    required this.releaseUrl,
    this.apkUrl,
    this.linuxUrl,
    this.windowsUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String releaseName;
  final String releaseNotes;
  final DateTime? publishedAt;
  final String releaseUrl;
  final String? apkUrl;
  final String? linuxUrl;
  final String? windowsUrl;
}

class GuiUpdateService {
  static const String repoOwner = 'botforge-robotics';
  static const String repoName = 'nav2_mission_planner_gui';
  static const String releasesApiUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// Fetch the latest GUI release info from GitHub.
  Future<GuiReleaseInfo> checkLatestRelease() async {
    String currentVer = '1.0.0';
    try {
      final info = await PackageInfo.fromPlatform();
      currentVer = info.version;
    } catch (_) {
      // Fallback
    }

    try {
      final response = await http.get(
        Uri.parse(releasesApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final tagName = (data['tag_name'] as String? ?? 'v1.0.0')
            .replaceFirst(RegExp(r'^[vV]'), '');
        final releaseName = data['name'] as String? ?? 'NavPro Mini $tagName';
        final releaseNotes = data['body'] as String? ?? 'No release notes provided.';
        final releaseUrl = data['html_url'] as String? ??
            'https://github.com/$repoOwner/$repoName/releases';
        final publishedStr = data['published_at'] as String?;
        final publishedAt = publishedStr != null ? DateTime.tryParse(publishedStr) : null;

        String? apk;
        String? linux;
        String? windows;

        final assets = data['assets'] as List<dynamic>? ?? [];
        for (final asset in assets) {
          if (asset is Map<String, dynamic>) {
            final name = (asset['name'] as String? ?? '').toLowerCase();
            final downloadUrl = asset['browser_download_url'] as String?;
            if (downloadUrl != null) {
              if (name.endsWith('.apk')) {
                apk = downloadUrl;
              } else if (name.contains('linux') || name.endsWith('.tar.gz') || name.endsWith('.appimage')) {
                linux = downloadUrl;
              } else if (name.contains('windows') || (name.endsWith('.zip') && !name.contains('linux')) || name.endsWith('.exe')) {
                windows = downloadUrl;
              }
            }
          }
        }

        final hasUpdate = _compareVersions(tagName, currentVer) > 0;

        return GuiReleaseInfo(
          currentVersion: currentVer,
          latestVersion: tagName,
          hasUpdate: hasUpdate,
          releaseName: releaseName,
          releaseNotes: releaseNotes,
          publishedAt: publishedAt,
          releaseUrl: releaseUrl,
          apkUrl: apk,
          linuxUrl: linux,
          windowsUrl: windows,
        );
      }
    } catch (_) {
      // Network or parsing failure
    }

    return GuiReleaseInfo(
      currentVersion: currentVer,
      latestVersion: currentVer,
      hasUpdate: false,
      releaseName: 'NavPro Mini v$currentVer',
      releaseNotes: 'Up to date with the current release.',
      publishedAt: null,
      releaseUrl: 'https://github.com/$repoOwner/$repoName/releases',
    );
  }

  /// Compare two semver strings: returns 1 if v1 > v2, -1 if v1 < v2, 0 if equal.
  int _compareVersions(String v1, String v2) {
    final clean1 = v1.split('+').first.split('-').first;
    final clean2 = v2.split('+').first.split('-').first;
    final parts1 = clean1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = clean2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    while (parts1.length < 3) {
      parts1.add(0);
    }
    while (parts2.length < 3) {
      parts2.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (parts1[i] > parts2[i]) return 1;
      if (parts1[i] < parts2[i]) return -1;
    }
    return 0;
  }

  /// Open a download URL or web release URL.
  Future<bool> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Get active platform description.
  String get activePlatformName {
    if (kIsWeb) return 'Web (PWA)';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    return 'Desktop';
  }
}
