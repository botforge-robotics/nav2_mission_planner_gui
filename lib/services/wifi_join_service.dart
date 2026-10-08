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
      try {
        final res = await Process.run('netsh', ['wlan', 'show', 'interfaces']);
        return res.exitCode == 0 &&
            !(res.stdout as String).toLowerCase().contains('no wireless interface');
      } catch (_) {
        return false;
      }
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
    final firstTry = await _doScanHotspotsWindows();
    if (firstTry.isNotEmpty) return firstTry;
    // Brief retry if first scan was during adapter wake-up
    await Future.delayed(const Duration(milliseconds: 1200));
    return _doScanHotspotsWindows();
  }

  Future<List<String>> _doScanHotspotsWindows() async {
    try {
      var result = await Process.run('netsh', [
        'wlan',
        'show',
        'networks',
        'mode=bssid',
      ]);
      if (result.exitCode != 0) {
        result = await Process.run('netsh', [
          'wlan',
          'show',
          'networks',
        ]);
      }
      if (result.exitCode != 0) return [];
      final parsed = parseNetshNetworks(result.stdout as String);
      if (parsed.siteNetworks.isNotEmpty) {
        _cachedSiteNetworks = parsed.siteNetworks;
      }
      return parsed.hotspots;
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
    if (Platform.isWindows) {
      return _connectHotspotWindows(ssid);
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

  Future<bool> _connectHotspotWindows(String ssid) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File(
      '${tempDir.path}${Platform.pathSeparator}navpro_wlan_${DateTime.now().millisecondsSinceEpoch}.xml',
    );
    try {
      final xml = buildWlanProfileXml(ssid);
      await tempFile.writeAsString(xml);
      final absPath = tempFile.absolute.path;

      // 1. Add profile: try user=current first (does not require administrator elevation),
      // fallback to all-user profile.
      var addRes = await Process.run('netsh', [
        'wlan',
        'add',
        'profile',
        'filename=$absPath',
        'user=current',
      ]);
      if (addRes.exitCode != 0) {
        addRes = await Process.run('netsh', [
          'wlan',
          'add',
          'profile',
          'filename=$absPath',
        ]);
      }
      if (addRes.exitCode != 0) {
        return false;
      }

      // 2. Connect to the network profile
      var connRes = await Process.run('netsh', [
        'wlan',
        'connect',
        'name=$ssid',
      ]);
      if (connRes.exitCode != 0) {
        connRes = await Process.run('netsh', [
          'wlan',
          'connect',
          'name=$ssid',
          'ssid=$ssid',
        ]);
      }
      if (connRes.exitCode != 0) {
        return false;
      }

      // 3. Poll briefly to see if connection settles
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (await isOnSetupHotspotSubnet()) {
          return true;
        }
        final current = await currentSsid();
        if (current == ssid) {
          return true;
        }
      }

      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  /// True once the device has actually landed on the hotspot's own subnet —
  /// checked rather than trusting connect()'s return value alone, since a
  /// "successful" OS-level join can still leave DHCP not yet settled.
  Future<bool> isOnSetupHotspotSubnet() async {
    // 1. First probe if the setup portal IP is directly reachable via TCP
    try {
      final sock = await Socket.connect(
        kSetupHotspotGatewayIp,
        80,
        timeout: const Duration(milliseconds: 600),
      );
      sock.destroy();
      return true;
    } catch (_) {}

    // 2. Check local network interfaces for 10.42.0.*
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

    // 3. Fallback to network_info_plus
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

    if (!kIsWeb && Platform.isWindows) {
      try {
        final res = await Process.run('netsh', ['wlan', 'show', 'interfaces']);
        if (res.exitCode == 0) {
          final ssid = parseNetshInterfaceSsid(res.stdout as String);
          if (ssid != null && ssid.isNotEmpty) return ssid;
        }
      } catch (_) {}
    }

    try {
      return await _network.getWifiName();
    } catch (_) {
      return null;
    }
  }

  /// Escapes special XML characters for Windows WLANProfile XML documents.
  static String escapeXml(String string) {
    return string
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Builds a Windows WLANProfile v1 XML document for a WPA2-PSK network.
  static String buildWlanProfileXml(
    String ssid, {
    String password = kSetupHotspotPassword,
  }) {
    final escapedSsid = escapeXml(ssid);
    final ssidHex = ssid.codeUnits
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final escapedPass = escapeXml(password);

    return '''<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$escapedSsid</name>
    <SSIDConfig>
        <SSID>
            <hex>$ssidHex</hex>
            <name>$escapedSsid</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>manual</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$escapedPass</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>''';
  }

  /// Parses `netsh wlan show networks mode=bssid` output, separating
  /// robot setup hotspots from regular site Wi-Fi networks and ordering by
  /// signal strength descending.
  static ({List<String> hotspots, List<String> siteNetworks}) parseNetshNetworks(
    String stdout,
  ) {
    final lines = stdout.split('\n');
    final Map<String, int> hotspots = {};
    final Map<String, int> siteNetworks = {};

    String? activeSsid;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Match "SSID 1 : <name>" or "SSID : <name>"
      // Caret ensures we do NOT match "BSSID 1 : xx:xx:..."
      final ssidMatch = RegExp(
        r'^SSID(?:\s+\d+)?\s*:\s*(.*)$',
        caseSensitive: false,
      ).firstMatch(line);

      if (ssidMatch != null) {
        final ssid = ssidMatch.group(1)?.trim() ?? '';
        if (ssid.isNotEmpty) {
          activeSsid = ssid;
          if (activeSsid.startsWith(kSetupHotspotPrefix)) {
            hotspots.putIfAbsent(activeSsid, () => 0);
          } else {
            siteNetworks.putIfAbsent(activeSsid, () => 0);
          }
        } else {
          activeSsid = null;
        }
        continue;
      }

      // Match signal line e.g. "Signal : 85%" or localized ": 85%"
      if (activeSsid != null) {
        final signalMatch = RegExp(r':\s*(\d+)%').firstMatch(line);
        if (signalMatch != null) {
          final sig = int.tryParse(signalMatch.group(1) ?? '0') ?? 0;
          if (activeSsid.startsWith(kSetupHotspotPrefix)) {
            if ((hotspots[activeSsid] ?? 0) < sig) {
              hotspots[activeSsid] = sig;
            }
          } else {
            if ((siteNetworks[activeSsid] ?? 0) < sig) {
              siteNetworks[activeSsid] = sig;
            }
          }
        }
      }
    }

    final sortedSite = siteNetworks.keys.toList()
      ..sort((a, b) => (siteNetworks[b] ?? 0).compareTo(siteNetworks[a] ?? 0));

    final sortedHotspots = hotspots.keys.toList()
      ..sort((a, b) => (hotspots[b] ?? 0).compareTo(hotspots[a] ?? 0));

    return (hotspots: sortedHotspots, siteNetworks: sortedSite);
  }

  /// Parses `netsh wlan show interfaces` output to find the currently
  /// connected Wi-Fi SSID, if any.
  static String? parseNetshInterfaceSsid(String stdout) {
    final lines = stdout.split('\n');
    bool connected = false;
    String? currentInterfaceSsid;
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.toLowerCase().contains('state') && line.contains(':')) {
        final val = line.split(':').sublist(1).join(':').trim().toLowerCase();
        connected = val == 'connected';
      }
      final ssidMatch = RegExp(
        r'^SSID\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (ssidMatch != null) {
        currentInterfaceSsid = ssidMatch.group(1)?.trim();
        if (connected &&
            currentInterfaceSsid != null &&
            currentInterfaceSsid.isNotEmpty) {
          return currentInterfaceSsid;
        }
      }
    }
    if (currentInterfaceSsid != null && currentInterfaceSsid.isNotEmpty) {
      return currentInterfaceSsid;
    }
    return null;
  }
}
