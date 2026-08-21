import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:nav2_mission_planner/modals/robotProfile.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner/services/pc_api_service.dart';
import 'package:nav2_mission_planner/services/tf_service.dart';

class ConnectionProvider extends ChangeNotifier {
  static const String _lastRobotIpKey = 'lastActiveRobotIp';
  static const String _lastRobotPortKey = 'lastActiveRobotPort';
  static const String _lastRobotNameKey = 'lastActiveRobotName';

  List<RobotProfile> _robots = [];
  RobotProfile? _activeRobot;
  String _ip = '';
  String _port = '9090';
  bool _isConnected = false;
  bool _heartbeatOnline = false;
  Ros2? _ros2Client;
  Timer? _heartbeatTimer;

  final StreamController<ConnectionState> _connectionController =
      StreamController<ConnectionState>.broadcast();

  Stream<ConnectionState> get connectionStream => _connectionController.stream;

  String get ip => _ip;
  String get port => _port;
  bool get isConnected => _isConnected;
  bool get heartbeatOnline => _heartbeatOnline;
  List<RobotProfile> get robots => _robots;
  RobotProfile? get activeRobot => _activeRobot;

  // Last robot that was successfully connected to, persisted across page
  // reloads/app restarts (a Flutter Web refresh drops all in-memory state,
  // including the live rosbridge websocket, so this is what lets the app
  // reconnect on its own instead of dumping the user back at a blank
  // connection screen every time). Cleared on an explicit disconnect.
  String? _lastRobotIp;
  String? _lastRobotPort;
  String? _lastRobotName;
  bool _autoReconnectAttempted = false;

  String? get lastRobotIp => _lastRobotIp;
  String? get lastRobotPort => _lastRobotPort;
  String? get lastRobotName => _lastRobotName;
  bool get hasLastRobot => _lastRobotIp != null && _lastRobotIp!.isNotEmpty;
  Ros2 get ros2Client {
    final client = _ros2Client;
    if (client == null || !_isConnected || client.status != Status.connected) {
      throw StateError('ROS not connected — connect to the robot first');
    }
    return client;
  }

  List<Map<String, String>> get recentConnections {
    return _robots
        .map((robot) => {
              'name': robot.name,
              'ip': robot.ip,
              'port': robot.port,
            })
        .toList();
  }

  ConnectionProvider() {
    loadRobots();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _connectionController.close();
    super.dispose();
  }

  Future<void> _saveRobots() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'robots', json.encode(_robots.map((r) => r.toJson()).toList()));
  }

  /// Reachability check — uses PC API on web (no dart:io sockets).
  Future<bool> _isRobotAvailable(String ip, String port) async {
    try {
      if (kIsWeb) {
        return PcApiService.isRosbridgeReachable(ip, port);
      }
      // Non-web: still prefer PC API when available; fall back to true and
      // let rosbridge connect fail if offline.
      final ok = await PcApiService.isRosbridgeReachable(ip, port);
      return ok;
    } catch (_) {
      // If PC API is down, allow connect attempt anyway.
      return true;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final hb = await PcApiService.heartbeat();
      final online = hb != null && hb['online'] == true;
      if (online != _heartbeatOnline) {
        _heartbeatOnline = online;
        notifyListeners();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatOnline = false;
  }

  Future<void> _claimOnPc(String name, String ip, String port) async {
    final result = await PcApiService.claim(
      ip: ip,
      port: port,
      name: name.trim().isEmpty ? 'NavProMini $ip' : name.trim(),
    );
    _heartbeatOnline = result != null && result['online'] == true;
  }

  Future<bool> connect(String ip, String port,
      {String name = '', bool createNew = false}) async {
    try {
      _connectionController.add(ConnectionState.connecting);
      if (!await _isRobotAvailable(ip, port)) {
        _connectionController.add(ConnectionState.disconnected);
        return false;
      }

      // Close any previous client first
      try {
        await _ros2Client?.close();
      } catch (_) {}

      _ros2Client = Ros2(url: 'ws://$ip:$port');
      _ros2Client!.connect();

      // Give the websocket a moment to open before marking connected
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (_ros2Client!.status != Status.connected) {
        _connectionController.add(ConnectionState.disconnected);
        return false;
      }

      _isConnected = true;
      _ip = ip;
      _port = port;

      TFService.resetAllServices();

      if (createNew) {
        final robotName = name.trim().isEmpty ? 'Robot $ip' : name.trim();
        final settingsId = Uuid().v4();

        final connection = RobotProfile(
          id: Uuid().v4(),
          name: robotName,
          ip: ip,
          port: port,
          settingsId: settingsId,
          isConfigured: false,
        );

        _activeRobot = connection;
        _robots.insert(0, connection);

        if (_robots.length > 10) {
          _robots.removeLast();
        }
      } else {
        final existingIndex =
            _robots.indexWhere((robot) => robot.ip == ip && robot.port == port);

        if (existingIndex != -1) {
          _robots[existingIndex].name =
              name.trim().isEmpty ? _robots[existingIndex].name : name.trim();
          final existingRobot = _robots.removeAt(existingIndex);
          _robots.insert(0, existingRobot);
          _activeRobot = _robots[0];
        } else {
          final robotName = name.trim().isEmpty ? 'Robot $ip' : name.trim();
          final settingsId = Uuid().v4();

          final connection = RobotProfile(
            id: Uuid().v4(),
            name: robotName,
            ip: ip,
            port: port,
            settingsId: settingsId,
            isConfigured: false,
          );

          _activeRobot = connection;
          _robots.insert(0, connection);

          if (_robots.length > 10) {
            _robots.removeLast();
          }
        }
      }

      // Under-the-hood: claim on PC API + heartbeat (ConnectionScreen unchanged)
      await _claimOnPc(_activeRobot?.name ?? name, ip, port);
      _startHeartbeat();

      // NavProMini deployment: treat as configured (no setup wizard)
      if (_activeRobot != null && !_activeRobot!.isConfigured) {
        _activeRobot!.isConfigured = true;
        await _saveRobots();
      }

      await _saveLastRobot(ip, port, _activeRobot?.name ?? name);

      notifyListeners();
      _connectionController.add(ConnectionState.connected);
      return true;
    } catch (e) {
      _stopHeartbeat();
      _connectionController.add(ConnectionState.disconnected);
      return false;
    }
  }

  Future<bool> connectWithoutName(String ip, String port) async {
    return connect(ip, port);
  }

  Future<void> disconnect() async {
    _connectionController.add(ConnectionState.disconnecting);
    try {
      await _ros2Client?.close();
      _isConnected = false;
      _activeRobot = null;
      _stopHeartbeat();
      // Explicit disconnect — don't auto-reconnect to this robot on the
      // next launch/refresh, only on connect()'s own success.
      await _clearLastRobot();
      // Keep claim so heartbeat can still track robot online status
      TFService.resetAllServices();
      notifyListeners();
    } catch (e) {
      rethrow;
    } finally {
      _connectionController.add(ConnectionState.disconnected);
    }
  }

  void addRobot(RobotProfile robot) {
    _robots.add(robot);
    _saveRobots();
    notifyListeners();
  }

  void updateRobot(String id, String newName, String newIp, String newPort) {
    final robotIndex = _robots.indexWhere((r) => r.id == id);
    if (robotIndex != -1) {
      _robots[robotIndex].name = newName;
      _robots[robotIndex].ip = newIp;
      _robots[robotIndex].port = newPort;
      _saveRobots();
      notifyListeners();
    }
  }

  void deleteRobot(String id) async {
    final robotToDelete = _robots.firstWhere((r) => r.id == id);
    _robots.removeWhere((r) => r.id == id);

    if (_activeRobot?.id == id) {
      _activeRobot = null;
    }

    _saveRobots();
    notifyListeners();

    await SettingsProvider.deleteRobotSettings(robotToDelete.settingsId);
  }

  Future<void> loadRobots() async {
    final prefs = await SharedPreferences.getInstance();
    final String? robotsJson = prefs.getString('robots');
    if (robotsJson != null) {
      _robots = List<RobotProfile>.from(
          json.decode(robotsJson).map((x) => RobotProfile.fromJson(x)));
    }
    _lastRobotIp = prefs.getString(_lastRobotIpKey);
    _lastRobotPort = prefs.getString(_lastRobotPortKey);
    _lastRobotName = prefs.getString(_lastRobotNameKey);
    notifyListeners();
  }

  Future<void> _saveLastRobot(String ip, String port, String name) async {
    _lastRobotIp = ip;
    _lastRobotPort = port;
    _lastRobotName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRobotIpKey, ip);
    await prefs.setString(_lastRobotPortKey, port);
    await prefs.setString(_lastRobotNameKey, name);
  }

  Future<void> _clearLastRobot() async {
    _lastRobotIp = null;
    _lastRobotPort = null;
    _lastRobotName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastRobotIpKey);
    await prefs.remove(_lastRobotPortKey);
    await prefs.remove(_lastRobotNameKey);
  }

  /// Attempts to reconnect to the last robot that was successfully connected
  /// (see _saveLastRobot), so a page refresh doesn't force the user back
  /// through manual robot selection every time. Safe to call once at
  /// startup; a no-op if already connected/connecting, already attempted
  /// this app session, or no robot was ever saved. Returns whether it
  /// (eventually) connected.
  Future<bool> autoReconnect() async {
    if (_autoReconnectAttempted || _isConnected || !hasLastRobot) {
      return _isConnected;
    }
    _autoReconnectAttempted = true;
    return connect(_lastRobotIp!, _lastRobotPort ?? '9090',
        name: _lastRobotName ?? '');
  }

  void markRobotConfigured(String robotId) {
    final robotIndex = _robots.indexWhere((r) => r.id == robotId);
    if (robotIndex != -1) {
      _robots[robotIndex].isConfigured = true;
      _saveRobots();
      notifyListeners();
    }
  }

  bool get activeRobotNeedsSetup => _activeRobot?.isConfigured == false;
}

enum ConnectionState { connecting, connected, disconnecting, disconnected }
