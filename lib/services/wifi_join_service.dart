import 'dart:async';
import 'dart:io';

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

/// Joins the robot's `NavPro-Setup-XXXXXX` hotspot, and scans for nearby ones
/// so the UI can offer a select-from-list pick instead of typing the SSID by hand.
///
/// Supported natively on Android (via `wifi_scan` and `wifi_iot`) and Linux desktop
/// (via `nmcli`). On iOS, Apple restricts network scanning, so manual SSID entry
/// or OS Wi-Fi settings is the fallback.
class WifiJoinService {
  bool get isSupported => !kIsWeb;

  final _network = NetworkInfo();

  Future<bool> canScan() async {
    if (kIsWeb) return false;
    if (Platform.isLinux) {
      try {
        final res = await Process.run('which', ['nmcli']);
        return res.exitCode == 0;
      } catch (_) {
        return false;
      }
    }
    if (Platform.isWindows) {
      return true;
    }
    try {
      final can = await WiFiScan.instance.canStartScan(askPermissions: true);
      return can == CanStartScan.yes;
    } catch (_) {
      return false;
    }
  }

  /// Nearby `NavPro-Setup-*` hotspot SSIDs, deduplicated and strongest
  /// signal first. Empty if scanning isn't available or none in range.
  Future<List<String>> scanForSetupHotspots() async {
    if (kIsWeb) return [];
    if (Platform.isLinux) {
      return _scanHotspotsLinux();
    }
    if (Platform.isWindows) {
      return _scanHotspotsWindows();
    }
    return _scanHotspotsMobile();
  }

  List<String> _cachedSiteNetworks = [];
  List<String> get cachedSiteNetworks => List.unmodifiable(_cachedSiteNetworks);

  Future<List<String>> _scanHotspotsLinux() async {
    try {
      var result = await Process.run('nmcli', [
        '-t',
        '-f',
        'SSID,SIGNAL',
        'dev',
        'wifi',
        'list',
        '--rescan',
        'yes',
      ]);
      if (result.exitCode != 0) {
        // Fallback without --rescan yes if rate limited or not allowed
        result = await Process.run('nmcli', [
          '-t',
          '-f',
          'SSID,SIGNAL',
          'dev',
          'wifi',
          'list',
        ]);
      }
      if (result.exitCode != 0) return [];
      final lines = (result.stdout as String).split('\n');
      final Map<String, int> hotspots = {};
      final Map<String, int> siteNetworks = {};
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        final parts = line.split(':');
        if (parts.length < 2) continue;
        final signal = int.tryParse(parts.last) ?? 0;
        final ssid = parts.sublist(0, parts.length - 1).join(':').trim();
        if (ssid.isEmpty) continue;
        if (ssid.startsWith(kSetupHotspotPrefix)) {
          if (!hotspots.containsKey(ssid) || (hotspots[ssid] ?? 0) < signal) {
            hotspots[ssid] = signal;
          }
        } else {
          if (!siteNetworks.containsKey(ssid) || (siteNetworks[ssid] ?? 0) < signal) {
            siteNetworks[ssid] = signal;
          }
        }
      }
      final sortedSite = siteNetworks.keys.toList()
        ..sort((a, b) => (siteNetworks[b] ?? 0).compareTo(siteNetworks[a] ?? 0));
      if (sortedSite.isNotEmpty) {
        _cachedSiteNetworks = sortedSite;
      }
      final sorted = hotspots.keys.toList()
        ..sort((a, b) => (hotspots[b] ?? 0).compareTo(hotspots[a] ?? 0));
      return sorted;
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> _scanHotspotsWindows() async {
    try {
      final result = await Process.run('netsh', ['wlan', 'show', 'networks']);
      if (result.exitCode != 0) return [];
      final lines = (result.stdout as String).split('\n');
      final found = <String>{};
      final site = <String>{};
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.startsWith('SSID ') && line.contains(':')) {
          final ssid = line.split(':').sublist(1).join(':').trim();
          if (ssid.isNotEmpty) {
            if (ssid.startsWith(kSetupHotspotPrefix)) {
              found.add(ssid);
            } else {
              site.add(ssid);
            }
          }
        }
      }
      if (site.isNotEmpty) {
        _cachedSiteNetworks = site.toList();
      }
      return found.toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> _scanHotspotsMobile() async {
    try {
      final canStart =
          await WiFiScan.instance.canStartScan(askPermissions: true);
      if (canStart == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        await Future.delayed(const Duration(seconds: 2));
      }

      final canGet =
          await WiFiScan.instance.canGetScannedResults(askPermissions: true);
      if (canGet != CanGetScannedResults.yes) return [];

      final results = await WiFiScan.instance.getScannedResults();
      final siteList = results
          .where((ap) => !ap.ssid.startsWith(kSetupHotspotPrefix) && ap.ssid.trim().isNotEmpty)
          .toList()
        ..sort((a, b) => b.level.compareTo(a.level));
      final siteSeen = <String>{};
      final siteNets = [
        for (final ap in siteList)
          if (siteSeen.add(ap.ssid.trim())) ap.ssid.trim(),
      ];
      if (siteNets.isNotEmpty) {
        _cachedSiteNetworks = siteNets;
      }

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
    if (kIsWeb) return false;
    if (Platform.isLinux) {
      return _connectHotspotLinux(ssid);
    }
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

  Future<bool> _connectHotspotLinux(String ssid) async {
    try {
      var result = await Process.run('nmcli', [
        '-w',
        '25',
        'dev',
        'wifi',
        'connect',
        ssid,
        'password',
        kSetupHotspotPassword,
      ]);
      if (result.exitCode == 0) return true;

      // If connecting directly failed (e.g. connection profile already configured),
      // try bringing up the connection profile directly.
      result = await Process.run('nmcli', [
        '-w',
        '25',
        'connection',
        'up',
        ssid,
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// True once the device has actually landed on the hotspot's own subnet —
  /// checked rather than trusting connect()'s return value alone, since a
  /// "successful" OS-level join can still leave DHCP not yet settled.
  Future<bool> isOnSetupHotspotSubnet() async {
    if (!kIsWeb) {
      try {
        final interfaces = await NetworkInterface.list();
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (addr.address.startsWith('10.42.0.')) {
              return true;
            }
          }
        }
      } catch (_) {}
    }

    try {
      final ip = await _network.getWifiIP();
      return ip != null && ip.startsWith('10.42.0.');
    } catch (_) {
      return false;
    }
  }

  Future<String?> currentSsid() async {
    if (!kIsWeb && Platform.isLinux) {
      try {
        final res = await Process.run('nmcli', ['-t', '-f', 'ACTIVE,SSID', 'dev', 'wifi']);
        if (res.exitCode == 0) {
          for (final line in (res.stdout as String).split('\n')) {
            if (line.startsWith('yes:')) {
              final active = line.substring(4).trim();
              if (active.isNotEmpty) return active;
            }
          }
        }
      } catch (_) {}
    }

    try {
      return await _network.getWifiName();
    } catch (_) {
      return null;
    }
  }
}
