import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../services/provisioning_service.dart';
import '../services/robot_discovery_service.dart';
import '../services/wifi_join_service.dart';

/// State for the initial setup flow only (discovery, AP-mode join,
/// provisioning progress) — not a general connection/app-state provider.
/// Once Dashboard and live screens exist, the robot the user picks here
/// hands off to that separate, longer-lived connection layer; this
/// controller's job ends at Setup: Complete.
class SetupFlowController extends ChangeNotifier {
  SetupFlowController({
    RobotDiscoveryService? discovery,
    ProvisioningService? provisioning,
    WifiJoinService? wifiJoin,
  })  : discovery = discovery ?? RobotDiscoveryService(),
        provisioning = provisioning ?? ProvisioningService(),
        wifiJoin = wifiJoin ?? WifiJoinService();

  final RobotDiscoveryService discovery;
  final ProvisioningService provisioning;
  final WifiJoinService wifiJoin;

  bool isScanning = false;
  String? scanError;
  final List<DiscoveredRobot> foundRobots = [];

  DiscoveredRobot? selectedRobot;

  bool manualLookupInProgress = false;
  String? manualLookupError;

  /// Probes one specific IP directly — the fallback when subnet
  /// auto-detection isn't reliable enough on a given device/platform (Wi-Fi
  /// IP lookup is permission-gated on Android, unavailable on most desktop/
  /// web contexts). Selects the robot on success, same as tapping it in the
  /// scanned list.
  Future<bool> connectByIp(String ip) async {
    manualLookupInProgress = true;
    manualLookupError = null;
    notifyListeners();

    final robot = await discovery.probe(ip.trim());
    manualLookupInProgress = false;
    if (robot == null) {
      manualLookupError = 'No NavProMini found at $ip.';
      notifyListeners();
      return false;
    }
    selectedRobot = robot;
    if (!foundRobots.any((r) => r.ip == robot.ip)) foundRobots.add(robot);
    notifyListeners();
    return true;
  }

  bool apJoining = false;
  String? apJoinError;
  ProvisioningStatus? provisioningStatus;

  Future<void> scanForRobots() async {
    isScanning = true;
    scanError = null;
    foundRobots.clear();
    notifyListeners();

    final subnets = await discovery.allSubnetPrefixes();
    if (subnets.isEmpty) {
      isScanning = false;
      scanError = 'Could not determine your network — make sure Wi-Fi is on.';
      notifyListeners();
      return;
    }

    await for (final robot in discovery.scan()) {
      if (foundRobots.any((r) => r.ip == robot.ip)) continue;
      foundRobots.add(robot);
      notifyListeners();
    }
    isScanning = false;
    notifyListeners();
  }

  void selectRobot(DiscoveredRobot robot) {
    selectedRobot = robot;
    notifyListeners();
  }

  /// Joins the robot's setup hotspot and confirms the device actually
  /// landed on its subnet (a "successful" OS-level join can still leave
  /// DHCP not yet settled) before the caller tries talking to the portal.
  Future<bool> joinSetupHotspot(String ssid) async {
    apJoining = true;
    apJoinError = null;
    notifyListeners();

    final connected = await wifiJoin.connectToHotspot(ssid);
    if (!connected) {
      apJoining = false;
      apJoinError = 'Could not join "$ssid". Check the password, or join it '
          'manually from Wi-Fi settings and come back.';
      notifyListeners();
      return false;
    }

    for (var attempt = 0; attempt < 20; attempt++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await wifiJoin.isOnSetupHotspotSubnet()) {
        apJoining = false;
        notifyListeners();
        return true;
      }
    }
    apJoining = false;
    apJoinError =
        'Joined "$ssid" but could not reach the robot yet. Try again.';
    notifyListeners();
    return false;
  }

  Stream<ProvisioningStatus> submitProvisioning({
    required String wifiSsid,
    required String wifiPassword,
    required String robotName,
    String? timezone,
    String? countryCode,
  }) async* {
    provisioningStatus = null;
    notifyListeners();

    // Use passed timezone or best-effort platform timezone
    String? effectiveTimezone = timezone;
    if (effectiveTimezone == null || effectiveTimezone.isEmpty) {
      try {
        effectiveTimezone = await FlutterTimezone.getLocalTimezone();
      } catch (_) {
        effectiveTimezone = null;
      }
    }

    await provisioning.submit(
      wifiSsid: wifiSsid,
      wifiPassword: wifiPassword,
      robotName: robotName,
      timezone: effectiveTimezone,
      countryCode: countryCode,
    );

    // Watch status stream from portal, and in parallel look for the robot on the site LAN.
    bool foundOnLan = false;
    DiscoveredRobot? discoveredRobot;

    // Start background LAN discovery immediately
    Future<void> runLanDiscovery() async {
      for (var attempt = 0; attempt < 30; attempt++) {
        if (foundOnLan) return;
        await Future.delayed(const Duration(milliseconds: 1500));
        try {
          final prefixes = await discovery.allSubnetPrefixes();
          for (final prefix in prefixes) {
            if (prefix == '10.42.0') continue; // Skip AP subnet
            await for (final robot in discovery.scan(subnetPrefix: prefix)) {
              if (robot.name == robotName ||
                  robot.name.toLowerCase() == robotName.toLowerCase() ||
                  robot.serial.isNotEmpty) {
                discoveredRobot = robot;
                foundOnLan = true;
                selectRobot(robot);
                return;
              }
            }
          }
        } catch (_) {}
      }
    }

    // Launch LAN discovery concurrently
    runLanDiscovery();

    await for (final status in provisioning.watchStatus()) {
      if (foundOnLan) break;
      provisioningStatus = status;
      notifyListeners();
      yield status;
      if (status.isTerminal) {
        if (status.phase == 'success') {
          return;
        }
      }
    }

    // If portal stream ended (AP dropped because robot connected to site Wi-Fi),
    // poll LAN until the robot is found on the site network or timeout.
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (!foundOnLan && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (foundOnLan) break;
      yield ProvisioningStatus(
        phase: 'joining_wifi',
        message: 'Robot joined Wi-Fi! Locating "$robotName" on your network…',
        wifiSsid: wifiSsid,
        robotName: robotName,
        wifiOk: true,
        busy: true,
        done: false,
      );
    }

    if (foundOnLan && discoveredRobot != null) {
      selectRobot(discoveredRobot!);
      final successStatus = ProvisioningStatus(
        phase: 'success',
        message: 'Connected to $robotName on Wi-Fi!',
        wifiSsid: wifiSsid,
        robotName: robotName,
        wifiOk: true,
        busy: false,
        done: true,
      );
      provisioningStatus = successStatus;
      notifyListeners();
      yield successStatus;
      return;
    }
  }

  /// Retrieves available site Wi-Fi networks by combining the robot's portal
  /// scan results (networks the robot sees) and the client device's Wi-Fi scan results.
  Future<List<String>> getAvailableSiteNetworks() async {
    final seen = <String>{};
    final networks = <String>[];

    // 1. Robot visible networks from portal
    try {
      final robotNets = await provisioning.fetchRobotVisibleNetworks();
      for (final s in robotNets) {
        final trimmed = s.trim();
        if (trimmed.isNotEmpty &&
            !trimmed.startsWith(kSetupHotspotPrefix) &&
            !trimmed.contains('/') &&
            seen.add(trimmed)) {
          networks.add(trimmed);
        }
      }
    } catch (_) {}

    // 2. Client device detected networks
    try {
      for (final s in wifiJoin.cachedSiteNetworks) {
        final trimmed = s.trim();
        if (trimmed.isNotEmpty &&
            !trimmed.startsWith(kSetupHotspotPrefix) &&
            !trimmed.contains('/') &&
            seen.add(trimmed)) {
          networks.add(trimmed);
        }
      }
    } catch (_) {}

    return networks;
  }

  Future<List<String>> getAvailableTimezones() async {
    return provisioning.fetchAvailableTimezones();
  }

  void reset() {
    isScanning = false;
    scanError = null;
    foundRobots.clear();
    selectedRobot = null;
    manualLookupInProgress = false;
    manualLookupError = null;
    apJoining = false;
    apJoinError = null;
    provisioningStatus = null;
    notifyListeners();
  }
}
