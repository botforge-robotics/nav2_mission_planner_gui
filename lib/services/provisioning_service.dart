import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Mirrors provision_portal.py's PortalState.status_dict() exactly — same
/// field names, so no translation layer between the robot's JSON and this
/// app's model.
class ProvisioningStatus {
  const ProvisioningStatus({
    required this.phase,
    required this.message,
    required this.wifiSsid,
    required this.robotName,
    required this.wifiOk,
    required this.busy,
    required this.done,
  });

  /// idle | submitted | joining_wifi | saving | success | error
  final String phase;
  final String message;
  final String wifiSsid;
  final String robotName;
  final bool wifiOk;
  final bool busy;
  final bool done;

  bool get isTerminal => phase == 'success' || phase == 'error';

  factory ProvisioningStatus.fromJson(Map<String, dynamic> json) =>
      ProvisioningStatus(
        phase: json['phase'] as String? ?? 'idle',
        message: json['message'] as String? ?? '',
        wifiSsid: json['wifi_ssid'] as String? ?? '',
        robotName: json['robot_name'] as String? ?? '',
        wifiOk: json['wifi_ok'] as bool? ?? false,
        busy: json['busy'] as bool? ?? false,
        done: json['done'] as bool? ?? false,
      );
}

/// Talks directly to the robot's captive-portal backend (provision_portal.py)
/// while the phone is joined to its `NavPro-Setup-XXXXXX` hotspot — plain
/// form-POST + JSON status poll, the exact contract that HTML page already
/// speaks. No WebView, no HTML ever rendered; this app is just another form
/// submitter against the same /save and /api/status endpoints.
class ProvisioningService {
  ProvisioningService({this.portalBase = 'http://10.42.0.1'});

  final String portalBase;

  /// Submits the site Wi-Fi credentials + robot name (+ optional time
  /// zone) — the same fields provision_portal.py's do_POST /save handler
  /// reads via parse_qs. [timezone] is an IANA zone (e.g. "Asia/Kolkata");
  /// omitted or empty just leaves the robot's system timezone as-is,
  /// matching what submitting the portal's own HTML form with that field
  /// blank does.
  Future<void> submit({
    required String wifiSsid,
    required String wifiPassword,
    required String robotName,
    String? timezone,
    String? countryCode,
  }) async {
    await http.post(
      Uri.parse('$portalBase/save'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'wifi_ssid': wifiSsid,
        'wifi_password': wifiPassword,
        'robot_name': robotName,
        if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
        if (countryCode != null && countryCode.isNotEmpty)
          'country_code': countryCode,
      },
    );
  }

  Future<ProvisioningStatus> fetchStatus() async {
    final resp = await http
        .get(Uri.parse('$portalBase/api/status'))
        .timeout(const Duration(seconds: 5));
    return ProvisioningStatus.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Fetches available Wi-Fi networks from the robot's provisioning portal
  /// (scanned by the robot before bringing up its AP).
  Future<List<String>> fetchRobotVisibleNetworks() async {
    // 1. Try /api/networks
    try {
      final resp = await http
          .get(Uri.parse('$portalBase/api/networks'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['networks'] is List) {
          final list = data['networks'] as List;
          final result = <String>[];
          for (final item in list) {
            if (item is Map && item['ssid'] is String) {
              final ssid = (item['ssid'] as String).trim();
              if (ssid.isNotEmpty && !result.contains(ssid)) {
                result.add(ssid);
              }
            }
          }
          if (result.isNotEmpty) return result;
        }
      }
    } catch (_) {}

    // 2. Try /api/status if it contains 'networks'
    try {
      final resp = await http
          .get(Uri.parse('$portalBase/api/status'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['networks'] is List) {
          final list = data['networks'] as List;
          final result = <String>[];
          for (final item in list) {
            if (item is Map && item['ssid'] is String) {
              final ssid = (item['ssid'] as String).trim();
              if (ssid.isNotEmpty && !result.contains(ssid)) {
                result.add(ssid);
              }
            }
          }
          if (result.isNotEmpty) return result;
        }
      }
    } catch (_) {}

    // 3. Fallback: Parse <select id="wifi_ssid_select"> from the portal's HTML form at /
    try {
      final resp = await http
          .get(Uri.parse('$portalBase/'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final selectMatch = RegExp(
          r'<select[^>]*id="wifi_ssid_select"[^>]*>([\s\S]*?)<\/select>',
          caseSensitive: false,
        ).firstMatch(resp.body);

        if (selectMatch != null) {
          final selectBody = selectMatch.group(1) ?? '';
          final exp = RegExp(r'<option\s+value="([^"]+)">');
          final matches = exp.allMatches(selectBody);
          final found = <String>[];
          for (final m in matches) {
            final val = m.group(1)?.trim();
            if (val != null &&
                val.isNotEmpty &&
                val != '__other__' &&
                !val.toLowerCase().contains('select network') &&
                !val.contains('/') &&
                !val.startsWith('http') &&
                !found.contains(val)) {
              found.add(val);
            }
          }
          if (found.isNotEmpty) return found;
        }
      }
    } catch (_) {}

    return [];
  }

  /// Fetches the list of timezones/countries from the robot's portal form.
  Future<List<String>> fetchAvailableTimezones() async {
    try {
      final resp = await http
          .get(Uri.parse('$portalBase/'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final selectMatch = RegExp(
          r'<select[^>]*id="wifi_timezone"[^>]*>([\s\S]*?)<\/select>',
          caseSensitive: false,
        ).firstMatch(resp.body);

        if (selectMatch != null) {
          final exp = RegExp(r'<option\s+value="([^"]+)">');
          final matches = exp.allMatches(selectMatch.group(1)!);
          final zones = <String>[];
          for (final m in matches) {
            final val = m.group(1)?.trim();
            if (val != null && val.isNotEmpty && !zones.contains(val)) {
              zones.add(val);
            }
          }
          if (zones.isNotEmpty) return zones;
        }
      }
    } catch (_) {}

    return const [
      'Asia/Kolkata',
      'America/New_York',
      'America/Los_Angeles',
      'America/Chicago',
      'Europe/London',
      'Europe/Paris',
      'Europe/Berlin',
      'Asia/Tokyo',
      'Asia/Singapore',
      'Asia/Dubai',
      'Australia/Sydney',
      'UTC',
    ];
  }

  /// Polls until success/error. When the robot turns off its AP to join site Wi-Fi,
  /// the portal becomes unreachable; consecutive connection errors signal that
  /// the AP is down and control should switch to LAN discovery.
  Stream<ProvisioningStatus> watchStatus({
    Duration interval = const Duration(milliseconds: 800),
    Duration timeout = const Duration(seconds: 45),
  }) async* {
    final deadline = DateTime.now().add(timeout);
    var consecutiveErrors = 0;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final status = await fetchStatus();
        consecutiveErrors = 0;
        yield status;
        if (status.isTerminal) return;
      } catch (_) {
        consecutiveErrors++;
        // If the portal was reached initially or at least 3 errors occurred in a row,
        // the AP is down because the robot is connecting to site Wi-Fi.
        if (consecutiveErrors >= 3) {
          return;
        }
      }
      await Future.delayed(interval);
    }
  }
}
