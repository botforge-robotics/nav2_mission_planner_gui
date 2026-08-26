import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:wifi_scan/wifi_scan.dart';

/// The setup hotspot's fixed password — matches
/// navpromini_setup/robot_config.py's DEFAULT_AP_PASSWORD exactly.
const String kSetupHotspotPassword = 'navprosetup';

/// The IP the provisioning portal listens on while the phone is joined to
/// the robot's hotspot — matches provision_portal.py's AP_ADDR.
const String kSetupHotspotGatewayIp = '10.42.0.1';

/// The SSID prefix every NavProMini setup hotspot uses — matches
/// robot_config.py's ap_ssid_from_mac().
const String kSetupHotspotPrefix = 'NavPro-Setup-';

/// Joins the robot's `NavPro-Setup-XXXXXX` hotspot, and — where the platform
/// allows it — scans for nearby ones so the UI can offer a select-from-list
/// pick instead of typing the SSID by hand.
///
/// Real scanning is Android-only: `wifi_scan` returns a stub with no real
/// results on iOS (Apple does not expose an API for apps to list nearby
/// networks, full stop), and neither `wifi_scan` nor `wifi_iot` has a web or
/// desktop implementation — browsers have no Wi-Fi API at all. Callers
/// should treat `canScan()` as the source of truth and fall back to manual
/// SSID entry when it's false, same as `isSupported` already gates the join
/// step itself.
class WifiJoinService {
  bool get isSupported => !kIsWeb;

  final _network = NetworkInfo();

  Future<bool> canScan() async {
    if (!isSupported) return false;
    try {
      final can = await WiFiScan.instance.canStartScan(askPermissions: true);
      return can == CanStartScan.yes;
    } catch (_) {
      return false;
    }
  }

  /// Nearby `NavPro-Setup-*` hotspot SSIDs, deduplicated and strongest
  /// signal first. Empty (not an error) if scanning isn't available on this
  /// platform/device — callers show manual entry either way.
  Future<List<String>> scanForSetupHotspots() async {
    if (!await canScan()) return [];
    try {
      final started = await WiFiScan.instance.startScan();
      if (!started) return [];
      // Scan results arrive asynchronously; a short settle window is the
      // same tradeoff every "scan then read results" Wi-Fi API forces —
      // there is no started-scan completion callback to await instead.
      await Future.delayed(const Duration(seconds: 2));
      final results = await WiFiScan.instance.getScannedResults();
      final byStrength = results
          .where((ap) => ap.ssid.startsWith(kSetupHotspotPrefix))
          .toList()
        ..sort((a, b) => b.level.compareTo(a.level));
      final seen = <String>{};
      return [
        for (final ap in byStrength)
          if (seen.add(ap.ssid)) ap.ssid,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<bool> connectToHotspot(String ssid) async {
    if (!isSupported) return false;
    try {
      return await WiFiForIoTPlugin.connect(
        ssid,
        password: kSetupHotspotPassword,
        security: NetworkSecurity.WPA,
        joinOnce: true,
        withInternet: false,
        timeoutInSeconds: 20,
      );
    } catch (_) {
      return false;
    }
  }

  /// True once the device has actually landed on the hotspot's own subnet —
  /// checked rather than trusting connect()'s return value alone, since a
  /// "successful" OS-level join can still leave DHCP not yet settled.
  Future<bool> isOnSetupHotspotSubnet() async {
    try {
      final ip = await _network.getWifiIP();
      return ip != null && ip.startsWith('10.42.0.');
    } catch (_) {
      return false;
    }
  }

  Future<String?> currentSsid() async {
    try {
      return await _network.getWifiName();
    } catch (_) {
      return null;
    }
  }
}
