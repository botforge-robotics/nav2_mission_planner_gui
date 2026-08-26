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

  /// Submits the site Wi-Fi credentials + robot name — same three fields
  /// provision_portal.py's do_POST /save handler reads via parse_qs.
  Future<void> submit({
    required String wifiSsid,
    required String wifiPassword,
    required String robotName,
  }) async {
    await http.post(
      Uri.parse('$portalBase/save'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'wifi_ssid': wifiSsid,
        'wifi_password': wifiPassword,
        'robot_name': robotName,
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

  /// Polls until success/error. Swallows transient failures rather than
  /// stopping: the portal's own connection legitimately drops mid-transition
  /// while the robot leaves its hotspot to join the real network — that's
  /// the expected 'joining_wifi' phase, not a fatal error.
  Stream<ProvisioningStatus> watchStatus({
    Duration interval = const Duration(milliseconds: 800),
    Duration timeout = const Duration(seconds: 90),
  }) async* {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final status = await fetchStatus();
        yield status;
        if (status.isTerminal) return;
      } catch (_) {
        // portal unreachable mid-transition — keep trying until the deadline
      }
      await Future.delayed(interval);
    }
  }
}
