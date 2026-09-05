import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists which robot this device last connected to, so Splash can skip
/// setup entirely on the next launch. Deliberately minimal — one robot, not
/// a multi-robot profile list — matching this pass's scope; a real "switch
/// robots" feature is later work, not blocked by this shape.
class SavedRobot {
  const SavedRobot({required this.name, required this.ip});

  final String name;
  final String ip;

  String get rosbridgeUrl => 'ws://$ip:9090';
}

class RobotConnectionStore {
  static const _keyName = 'robot_name';
  static const _keyIp = 'robot_ip';

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
      if (ip != null && ip.isNotEmpty) {
        final robot = SavedRobot(name: name ?? ip, ip: ip);
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
        if (ip != null && ip.isNotEmpty) {
          final robot = SavedRobot(name: name ?? ip, ip: ip);
          // Restore back to SharedPreferences
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_keyIp, robot.ip);
            await prefs.setString(_keyName, robot.name);
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
      }));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyIp);
      await prefs.remove(_keyName);
    } catch (_) {}

    final file = _desktopStorageFile();
    if (file != null && file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }
}
