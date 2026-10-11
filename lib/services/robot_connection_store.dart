import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists which robot this device last connected to, so Splash can skip
/// setup entirely on the next launch. Deliberately minimal — one robot, not
/// a multi-robot profile list — matching this pass's scope; a real "switch
/// robots" feature is later work, not blocked by this shape.
class SavedRobot {
  const SavedRobot({
    required this.name,
    required this.ip,
    this.fleetServerHost,
    this.fleetServerPort = 3000,
    this.isFleetMode = false,
  });

  final String name;
  final String ip;
  final String? fleetServerHost;
  final int fleetServerPort;
  final bool isFleetMode;

  String get rosbridgeUrl => 'ws://$ip:9090';
  String? get fleetApiUrl => fleetServerHost != null ? 'http://$fleetServerHost:$fleetServerPort' : null;
}

class RobotConnectionStore {
  static const _keyName = 'robot_name';
  static const _keyIp = 'robot_ip';
  static const _keyFleetHost = 'fleet_host';
  static const _keyFleetPort = 'fleet_port';
  static const _keyIsFleetMode = 'is_fleet_mode';

  File? _desktopStorageFile() {
    if (kIsWeb) return null;
    try {
      String? home;
      if (Platform.isWindows) {
        home = Platform.environment['APPDATA'] ??
            Platform.environment['USERPROFILE'];
      } else {
        home = Platform.environment['HOME'];
      }
      if (home == null || home.isEmpty) return null;
      return File('$home/.nav2_mission_planner_robot.json');
    } catch (_) {
      return null;
    }
  }

  Future<SavedRobot?> load() async {
    // 1. Try SharedPreferences first
    try {
      final prefs = await SharedPreferences.getInstance();
      final ip = prefs.getString(_keyIp);
      final name = prefs.getString(_keyName);
      final fleetHost = prefs.getString(_keyFleetHost);
      final fleetPort = prefs.getInt(_keyFleetPort) ?? 3000;
      final isFleetMode = prefs.getBool(_keyIsFleetMode) ?? false;
      if (ip != null && ip.isNotEmpty) {
        final robot = SavedRobot(
          name: name ?? ip,
          ip: ip,
          fleetServerHost: fleetHost,
          fleetServerPort: fleetPort,
          isFleetMode: isFleetMode,
        );
        // Ensure desktop backup file is in sync
        _saveToDesktopFile(robot);
        return robot;
      }
    } catch (_) {}

    // 2. Fallback to desktop storage file (survives PC reboot, browser profile wipe, etc.)
    final file = _desktopStorageFile();
    if (file != null && file.existsSync()) {
      try {
        final raw = file.readAsStringSync();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final ip = data['ip'] as String?;
        final name = data['name'] as String?;
        final fleetHost = data['fleetServerHost'] as String?;
        final fleetPort = data['fleetServerPort'] as int? ?? 3000;
        final isFleetMode = data['isFleetMode'] as bool? ?? false;
        if (ip != null && ip.isNotEmpty) {
          final robot = SavedRobot(
            name: name ?? ip,
            ip: ip,
            fleetServerHost: fleetHost,
            fleetServerPort: fleetPort,
            isFleetMode: isFleetMode,
          );
          // Restore back to SharedPreferences
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_keyIp, robot.ip);
            await prefs.setString(_keyName, robot.name);
            if (fleetHost != null) await prefs.setString(_keyFleetHost, fleetHost);
            await prefs.setInt(_keyFleetPort, fleetPort);
            await prefs.setBool(_keyIsFleetMode, isFleetMode);
          } catch (_) {}
          return robot;
        }
      } catch (_) {}
    }

    return null;
  }

  Future<void> save(SavedRobot robot) async {
    // 1. Save to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyIp, robot.ip);
      await prefs.setString(_keyName, robot.name);
      if (robot.fleetServerHost != null) {
        await prefs.setString(_keyFleetHost, robot.fleetServerHost!);
      } else {
        await prefs.remove(_keyFleetHost);
      }
      await prefs.setInt(_keyFleetPort, robot.fleetServerPort);
      await prefs.setBool(_keyIsFleetMode, robot.isFleetMode);
    } catch (_) {}

    // 2. Persist to desktop file
    _saveToDesktopFile(robot);
  }

  void _saveToDesktopFile(SavedRobot robot) {
    final file = _desktopStorageFile();
    if (file == null) return;
    try {
      file.writeAsStringSync(jsonEncode({
        'name': robot.name,
        'ip': robot.ip,
        'fleetServerHost': robot.fleetServerHost,
        'fleetServerPort': robot.fleetServerPort,
        'isFleetMode': robot.isFleetMode,
      }));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyIp);
      await prefs.remove(_keyName);
      await prefs.remove(_keyFleetHost);
      await prefs.remove(_keyFleetPort);
      await prefs.remove(_keyIsFleetMode);
    } catch (_) {}

    final file = _desktopStorageFile();
    if (file != null && file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }
}
