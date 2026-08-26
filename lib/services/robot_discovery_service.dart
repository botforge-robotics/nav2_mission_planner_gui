import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// A NavProMini found reachable on the current network.
class DiscoveredRobot {
  const DiscoveredRobot({
    required this.name,
    required this.ip,
    required this.serial,
    required this.hostname,
  });

  final String name;
  final String ip;
  final String serial;
  final String hostname;

  String get rosbridgeUrl => 'ws://$ip:9090';
  String get sdkBaseUrl => 'http://$ip:${RobotDiscoveryService.sdkPort}';
}

/// Finds NavProMini robots on the current network by probing
/// navpromini_sdk's `/system/info` across the local /24 — works identically
/// on every platform (mobile, desktop, and web) because that endpoint
/// already sends `Access-Control-Allow-Origin: *`, so a plain HTTP GET is
/// enough; no raw-socket platform channel needed.
class RobotDiscoveryService {
  static const int sdkPort = 8090;
  // Generous relative to a healthy LAN's real round-trip: with `concurrency`
  // requests genuinely in flight at once on a phone's single radio, queueing
  // delay stacks on top of the network's own latency, and a probe timing out
  // under that load reads identically to "nothing there" — a false negative
  // for a robot that's actually up. Observed 400ms as too tight for that on
  // real hardware.
  static const Duration probeTimeout = Duration(milliseconds: 1200);
  static const int concurrency = 16;

  final _network = NetworkInfo();

  /// Android hides the real Wi-Fi IP/SSID behind location permission on most
  /// versions still in the field — without it, getWifiIP() can silently
  /// return null (indistinguishable from "not on Wi-Fi" otherwise), which is
  /// the most likely reason a scan finds nothing on a network that
  /// genuinely has a robot on it. A no-op on platforms that don't gate this.
  Future<bool> ensureLocationPermission() async {
    final status = await Permission.locationWhenInUse.status;
    if (status.isGranted) return true;
    final result = await Permission.locationWhenInUse.request();
    return result.isGranted;
  }

  /// The device's current Wi-Fi subnet, as "a.b.c" (no trailing octet) —
  /// null if not on Wi-Fi, permission was denied, or the platform won't
  /// report it (some desktop/web contexts don't expose this at all).
  Future<String?> currentSubnetPrefix() async {
    try {
      await ensureLocationPermission();
      final ip = await _network.getWifiIP();
      if (ip == null || ip.isEmpty || ip == '0.0.0.0') return null;
      final parts = ip.split('.');
      if (parts.length != 4) return null;
      return '${parts[0]}.${parts[1]}.${parts[2]}';
    } catch (_) {
      return null;
    }
  }

  /// Scans the given subnet (or the current one, if omitted) and emits each
  /// robot as it's found — a bounded-concurrency worker pool over the 254
  /// candidate hosts, same idea as the PC API's own scanNearby() sweep
  /// (server/src/index.js), ported to Dart since that server isn't present
  /// in a pure mobile/desktop build.
  Stream<DiscoveredRobot> scan({String? subnetPrefix}) {
    final controller = StreamController<DiscoveredRobot>();

    Future<void> run() async {
      final prefix = subnetPrefix ?? await currentSubnetPrefix();
      if (prefix == null) {
        await controller.close();
        return;
      }
      final hosts = List.generate(254, (i) => '$prefix.${i + 1}');
      var nextIndex = 0;

      Future<void> worker() async {
        while (true) {
          final i = nextIndex++;
          if (i >= hosts.length) return;
          final robot = await probe(hosts[i]);
          if (robot != null && !controller.isClosed) controller.add(robot);
        }
      }

      await Future.wait(List.generate(concurrency, (_) => worker()));
      await controller.close();
    }

    run();
    return controller.stream;
  }

  /// Checks one specific IP directly — used both by scan()'s workers and to
  /// re-confirm a specific robot (e.g. right after AP-mode provisioning,
  /// before assuming it's back on the site network), and by the "enter IP
  /// manually" fallback when subnet auto-detection doesn't work at all.
  Future<DiscoveredRobot?> probe(String ip) async {
    try {
      final resp = await http
          .get(Uri.parse('http://$ip:$sdkPort/api/v1/system/info'))
          .timeout(probeTimeout);
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['model'] != 'NavProMini') return null;
      final robot =
          (data['robot'] as Map?)?.cast<String, dynamic>() ?? const {};
      return DiscoveredRobot(
        name: (robot['name'] as String?)?.trim().isNotEmpty == true
            ? robot['name'] as String
            : ip,
        ip: ip,
        serial: (robot['serial'] as String?) ?? '',
        hostname: (robot['hostname'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
