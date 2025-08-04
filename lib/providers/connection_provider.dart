import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:nav2_mission_planner/modals/robotProfile.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';

class ConnectionProvider extends ChangeNotifier {
  List<RobotProfile> _robots = [];
  RobotProfile? _activeRobot;
  String _ip = '';
  String _port = '9090';
  bool _isConnected = false;
  Ros2? _ros2Client;

  // Add this stream controller
  final StreamController<ConnectionState> _connectionController =
      StreamController<ConnectionState>.broadcast();

  Stream<ConnectionState> get connectionStream => _connectionController.stream;

  // Getters
  String get ip => _ip;
  String get port => _port;
  bool get isConnected => _isConnected;
  List<RobotProfile> get robots => _robots;
  RobotProfile? get activeRobot => _activeRobot;
  Ros2? get ros2Client => _ros2Client;

  // Add this getter for compatibility with connection_screen.dart
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

  // Save robots to shared preferences
  Future<void> _saveRobots() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'robots', json.encode(_robots.map((r) => r.toJson()).toList()));
  }

  // Add this helper method to check IP availability
  Future<bool> _isRobotAvailable(String ip) async {
    try {
      final socket =
          await Socket.connect(ip, 9090, timeout: Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  // Modified connect method with name parameter
  Future<bool> connect(String ip, String port,
      {String name = '', bool createNew = false}) async {
    try {
      _connectionController.add(ConnectionState.connecting);
      if (!await _isRobotAvailable(ip)) {
        throw Exception('Robot not available at $ip');
      }

      _ros2Client = Ros2(url: 'ws://$ip:$port');
      _ros2Client!.connect();
      _isConnected = true;
      _ip = ip;
      _port = port;

      // If createNew is true, always create a new robot regardless of existing IP
      if (createNew) {
        // Create new robot - will need setup
        final robotName = name.trim().isEmpty ? 'Robot $ip' : name.trim();
        final settingsId = Uuid().v4();

        final connection = RobotProfile(
          id: Uuid().v4(),
          name: robotName,
          ip: ip,
          port: port,
          settingsId: settingsId,
          isConfigured: false, // New robots need setup
        );

        // Set as active robot but don't save yet - only save after setup completion
        _activeRobot = connection;
        _robots.insert(0, connection);

        // Limit to last 10 connections
        if (_robots.length > 10) {
          _robots.removeLast();
        }
      } else {
        // Check if robot already exists (for existing robot connections)
        final existingIndex =
            _robots.indexWhere((robot) => robot.ip == ip && robot.port == port);

        if (existingIndex != -1) {
          // Update existing robot with new name and move to top
          _robots[existingIndex].name =
              name.trim().isEmpty ? _robots[existingIndex].name : name.trim();
          final existingRobot = _robots.removeAt(existingIndex);
          _robots.insert(0, existingRobot);
          _activeRobot = _robots[0];
        } else {
          // Create new robot - will need setup
          final robotName = name.trim().isEmpty ? 'Robot $ip' : name.trim();
          final settingsId = Uuid().v4();

          final connection = RobotProfile(
            id: Uuid().v4(),
            name: robotName,
            ip: ip,
            port: port,
            settingsId: settingsId,
            isConfigured: false, // New robots need setup
          );

          // Set as active robot but don't save yet - only save after setup completion
          _activeRobot = connection;
          _robots.insert(0, connection);

          // Limit to last 10 connections
          if (_robots.length > 10) {
            _robots.removeLast();
          }
        }
      }

      notifyListeners();
      _connectionController.add(ConnectionState.connected);
      return true;
    } catch (e) {
      _connectionController.add(ConnectionState.disconnected);
      rethrow;
    }
  }

  // Overloaded connect method for backward compatibility
  Future<bool> connectWithoutName(String ip, String port) async {
    return connect(ip, port);
  }

  // Disconnect from ROS2
  Future<void> disconnect() async {
    _connectionController.add(ConnectionState.disconnecting);
    try {
      await _ros2Client?.close();
      _isConnected = false;
      _activeRobot = null;
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

    // If this was the active robot, clear it
    if (_activeRobot?.id == id) {
      _activeRobot = null;
    }

    _saveRobots();
    notifyListeners();

    // Delete robot-specific settings from SharedPreferences
    await SettingsProvider.deleteRobotSettings(robotToDelete.settingsId);
  }

  Future<void> loadRobots() async {
    final prefs = await SharedPreferences.getInstance();
    final String? robotsJson = prefs.getString('robots');
    if (robotsJson != null) {
      _robots = List<RobotProfile>.from(
          json.decode(robotsJson).map((x) => RobotProfile.fromJson(x)));
      notifyListeners();
    }
  }

  // Add method to mark robot as configured and save permanently
  void markRobotConfigured(String robotId) {
    final robotIndex = _robots.indexWhere((r) => r.id == robotId);
    if (robotIndex != -1) {
      _robots[robotIndex].isConfigured = true;
      _saveRobots(); // Now save to permanent storage
      notifyListeners();
    }
  }

  // Add method to check if robot needs setup
  bool get activeRobotNeedsSetup => _activeRobot?.isConfigured == false;
}

enum ConnectionState { connecting, connected, disconnecting, disconnected }
