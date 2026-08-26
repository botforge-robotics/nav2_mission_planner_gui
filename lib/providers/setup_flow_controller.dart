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

    final subnet = await discovery.currentSubnetPrefix();
    if (subnet == null) {
      isScanning = false;
      scanError = 'Could not determine your network — make sure Wi-Fi is on.';
      notifyListeners();
      return;
    }

    await for (final robot in discovery.scan(subnetPrefix: subnet)) {
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

    for (var attempt = 0; attempt < 10; attempt++) {
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
  }) async* {
    provisioningStatus = null;
    notifyListeners();
    // Best-effort: the phone/tablet's own IANA zone, so the robot's clock
    // reads correctly for wherever it's actually being set up — without
    // this, schedules fire by whatever timezone the robot's OS image
    // shipped with, not the site it's deployed at. Never blocks setup: if
    // the platform call fails for any reason, submit proceeds without a
    // timezone, same as leaving that field blank in the portal's own form.
    String? timezone;
    try {
      timezone = await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      timezone = null;
    }
    await provisioning.submit(
      wifiSsid: wifiSsid,
      wifiPassword: wifiPassword,
      robotName: robotName,
      timezone: timezone,
    );
    await for (final status in provisioning.watchStatus()) {
      provisioningStatus = status;
      notifyListeners();
      yield status;
      if (status.isTerminal) return;
    }
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
