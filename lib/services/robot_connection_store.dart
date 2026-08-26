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

  Future<SavedRobot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString(_keyIp);
    final name = prefs.getString(_keyName);
    if (ip == null || ip.isEmpty) return null;
    return SavedRobot(name: name ?? ip, ip: ip);
  }

  Future<void> save(SavedRobot robot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyIp, robot.ip);
    await prefs.setString(_keyName, robot.name);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIp);
    await prefs.remove(_keyName);
  }
}
