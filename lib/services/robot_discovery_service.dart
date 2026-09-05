import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// Discovers all local IPv4 /24 subnet prefixes (e.g. ['192.168.0']).
  /// Uses native NetworkInterface.list() on desktop (Linux/macOS/Windows)
  /// and falls back to NetworkInfo().getWifiIP() on mobile.
  Future<List<String>> allSubnetPrefixes() async {
    final prefixes = <String>{};

    // 1. Native interfaces on desktop (Linux, Windows, macOS) and mobile
    if (!kIsWeb) {
      try {
        final interfaces = await NetworkInterface.list();
        for (final iface in interfaces) {
          final name = iface.name.toLowerCase();
          if (name.startsWith('lo') ||
              name.startsWith('docker') ||
              name.startsWith('veth') ||
              name.startsWith('br-')) {
            continue;
          }
          for (final addr in iface.addresses) {
            if (addr.type == InternetAddressType.IPv4 &&
                !addr.isLoopback &&
                !addr.isLinkLocal) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
              }
            }
          }
        }
      } catch (_) {}
    }

    // 2. Wi-Fi info via network_info_plus (primary path on mobile devices)
    if (prefixes.isEmpty) {
      try {
        await ensureLocationPermission();
        final ip = await _network.getWifiIP();
        if (ip != null && ip.isNotEmpty && ip != '0.0.0.0') {
          final parts = ip.split('.');
          if (parts.length == 4) {
            prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
          }
        }
      } catch (_) {}
    }

    return prefixes.toList();
  }

  /// The device's current Wi-Fi subnet, as "a.b.c" (no trailing octet) —
  /// null if not on Wi-Fi, permission was denied, or the platform won't
  /// report it (some desktop/web contexts don't expose this at all).
  Future<String?> currentSubnetPrefix() async {
    final list = await allSubnetPrefixes();
    return list.isNotEmpty ? list.first : null;
  }

  /// Scans the given subnet (or all local subnets, if omitted) and emits each
  /// robot as it's found — a bounded-concurrency worker pool over the 254
  /// candidate hosts per subnet.
  Stream<DiscoveredRobot> scan({String? subnetPrefix}) {
    final controller = StreamController<DiscoveredRobot>();

    Future<void> run() async {
      final prefixes = subnetPrefix != null
          ? [subnetPrefix]
          : await allSubnetPrefixes();
      if (prefixes.isEmpty) {
        await controller.close();
        return;
      }
      final hosts = <String>[];
      for (final prefix in prefixes) {
        hosts.addAll(List.generate(254, (i) => '$prefix.${i + 1}'));
      }
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
