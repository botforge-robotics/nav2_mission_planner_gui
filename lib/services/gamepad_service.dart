import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:gamepads/gamepads.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:ros2_api/ros2_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sdk_api_service.dart';

/// Available actions that can be triggered by a gamepad button.
enum GamepadAction {
  none,
  deadman, // Safety switch: stick teleop only sends velocity while held
  turbo, // Boost max speed while held
  dock, // Navigate to staging & dock
  undock, // Undock from charger
  emergencyStop, // Stop motion & cancel goal
  rotateLeft, // In-place rotation CCW
  rotateRight, // In-place rotation CW
  pauseResumeMission, // Pause/resume active mission
  nextWaypoint, // Cycle next saved waypoint
  prevWaypoint, // Cycle previous saved waypoint
  goToWaypoint, // Dispatch navigation to selected waypoint
}

extension GamepadActionExtension on GamepadAction {
  String get label {
    switch (this) {
      case GamepadAction.none:
        return 'None (Unassigned)';
      case GamepadAction.deadman:
        return 'Deadman Switch (Hold to Drive)';
      case GamepadAction.turbo:
        return 'Turbo Speed (Hold to Boost)';
      case GamepadAction.dock:
        return 'Dock to Charger';
      case GamepadAction.undock:
        return 'Undock from Charger';
      case GamepadAction.emergencyStop:
        return 'Emergency Stop / Cancel';
      case GamepadAction.rotateLeft:
        return 'Rotate Left in Place';
      case GamepadAction.rotateRight:
        return 'Rotate Right in Place';
      case GamepadAction.pauseResumeMission:
        return 'Pause / Resume Mission';
      case GamepadAction.nextWaypoint:
        return 'Select Next Waypoint';
      case GamepadAction.prevWaypoint:
        return 'Select Prev Waypoint';
      case GamepadAction.goToWaypoint:
        return 'Navigate to Selected Waypoint';
    }
  }
}

/// Central service for gamepad hardware polling, mapping, calibration, and teleop control.
class GamepadService extends ChangeNotifier {
  static final GamepadService instance = GamepadService._();
  GamepadService._();

  StreamSubscription<NormalizedGamepadEvent>? _eventSub;
  StreamSubscription<GamepadConnectionEvent>? _connSub;
  Timer? _teleopTimer;
  Timer? _scanTimer;

  bool _isConnected = false;
  String? _controllerName;
  String? _controllerId;

  // Axis values (-1.0 to 1.0)
  double _leftStickX = 0.0;
  double _leftStickY = 0.0;
  double _rightStickX = 0.0;
  double _rightStickY = 0.0;

  // Button state set
  final Set<GamepadButton> _pressedButtons = {};
  GamepadButton? _lastPressedButton;
  final _buttonPressStreamController = StreamController<GamepadButton>.broadcast();
  Stream<GamepadButton> get buttonPressEvents => _buttonPressStreamController.stream;
  GamepadButton? get lastPressedButton => _lastPressedButton;

  // Settings / Calibration
  double _deadzone = 0.10; // 10% deadband
  double _normalLinearSpeed = 0.12; // m/s
  double _turboLinearSpeed = 0.25; // m/s
  double _normalAngularSpeed = 0.45; // rad/s
  double _turboAngularSpeed = 0.75; // rad/s
  bool _invertLinear = false;
  bool _requireDeadman = true;

  // Remapping configuration: GamepadButton -> GamepadAction
  final Map<GamepadButton, GamepadAction> _buttonMapping = {
    GamepadButton.leftBumper: GamepadAction.deadman,
    GamepadButton.rightBumper: GamepadAction.turbo,
    GamepadButton.a: GamepadAction.dock,
    GamepadButton.b: GamepadAction.emergencyStop,
    GamepadButton.y: GamepadAction.undock,
    GamepadButton.x: GamepadAction.goToWaypoint,
    GamepadButton.dpadUp: GamepadAction.nextWaypoint,
    GamepadButton.dpadDown: GamepadAction.prevWaypoint,
    GamepadButton.dpadLeft: GamepadAction.rotateLeft,
    GamepadButton.dpadRight: GamepadAction.rotateRight,
    GamepadButton.start: GamepadAction.pauseResumeMission,
  };

  // Robot connection handles
  Ros2? _ros2;
  Publisher<geometry_msgs.Twist>? _cmdVelPub;
  SdkApiService? _sdkApi;

  // Waypoints management
  List<Map<String, dynamic>> _waypoints = [];
  int _selectedWaypointIndex = 0;

  // Toast / HUD action feedback stream
  final _hudStreamController = StreamController<String>.broadcast();
  Stream<String> get hudEvents => _hudStreamController.stream;

  // Getters
  bool get isConnected => _isConnected;
  String get controllerName => _controllerName ?? 'Gamepad';
  double get deadzone => _deadzone;
  double get normalLinearSpeed => _normalLinearSpeed;
  double get turboLinearSpeed => _turboLinearSpeed;
  double get normalAngularSpeed => _normalAngularSpeed;
  double get turboAngularSpeed => _turboAngularSpeed;
  bool get invertLinear => _invertLinear;
  bool get requireDeadman => _requireDeadman;
  Map<GamepadButton, GamepadAction> get buttonMapping => Map.unmodifiable(_buttonMapping);
  Set<GamepadButton> get pressedButtons => Set.unmodifiable(_pressedButtons);
  List<Map<String, dynamic>> get waypoints => List.unmodifiable(_waypoints);
  int get selectedWaypointIndex => _selectedWaypointIndex;

  double get leftStickX => _leftStickX;
  double get leftStickY => _leftStickY;
  double get rightStickX => _rightStickX;
  double get rightStickY => _rightStickY;

  /// Initialize gamepad listeners and load persisted button bindings
  Future<void> init() async {
    await _loadPreferences();
    _startListening();
    _startTeleopLoop();
  }

  void updateConnection({Ros2? ros2, SdkApiService? sdkApi}) {
    if (_ros2 != ros2) {
      _cmdVelPub?.shutdown();
      _cmdVelPub = null;
      _ros2 = ros2;
      if (ros2 != null && ros2.status == Status.connected) {
        _cmdVelPub = Publisher<geometry_msgs.Twist>(
          name: '/cmd_vel_teleop',
          type: geometry_msgs.Twist().fullType,
          ros2: ros2,
        );
      }
    }
    _sdkApi = sdkApi;
    _refreshWaypoints();
  }

  void _startListening() {
    try {
      _connSub = Gamepads.connectionEvents.listen((event) {
        if (event.type == GamepadConnectionEventType.connected) {
          _checkConnectedGamepads();
        } else if (event.type == GamepadConnectionEventType.disconnected) {
          if (event.gamepadId == _controllerId) {
            _handleDisconnected();
          }
        }
      }, onError: (e) {
        debugPrint('[GamepadService] Connection stream error: $e');
      });

      _eventSub = Gamepads.normalizedEvents.listen((event) {
        if (!_isConnected) {
          _isConnected = true;
          _controllerId = event.gamepadId;
          _controllerName ??= 'Gamepad';
          notifyListeners();
        }
        _handleNormalizedEvent(event);
      }, onError: (e) {
        debugPrint('[GamepadService] Normalized events error: $e');
      });

      _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _checkConnectedGamepads();
      });
      _checkConnectedGamepads();
    } catch (e) {
      debugPrint('[GamepadService] Gamepads not supported on this platform: $e');
    }
  }

  Future<void> _checkConnectedGamepads() async {
    try {
      final list = await Gamepads.list();
      if (list.isNotEmpty) {
        final first = list.first;
        if (!_isConnected || _controllerId != first.id) {
          _isConnected = true;
          _controllerId = first.id;
          _controllerName = first.name.isNotEmpty ? first.name : 'Gamepad';
          notifyListeners();
          _hudStreamController.add('🎮 Connected: $_controllerName');
        }
      } else if (_isConnected) {
        _handleDisconnected();
      }
    } catch (e) {
      // Platform may not support Gamepads.list()
    }
  }

  void _handleDisconnected() {
    _isConnected = false;
    _controllerId = null;
    _pressedButtons.clear();
    _leftStickX = 0.0;
    _leftStickY = 0.0;
    _rightStickX = 0.0;
    _rightStickY = 0.0;
    _publishZeroTwist();
    notifyListeners();
    _hudStreamController.add('🎮 Gamepad Disconnected');
  }

  void _handleNormalizedEvent(NormalizedGamepadEvent event) {
    if (event.button != null) {
      final btn = event.button!;
      final isPressed = event.value > 0.5;
      if (isPressed) {
        if (!_pressedButtons.contains(btn)) {
          _pressedButtons.add(btn);
          _lastPressedButton = btn;
          _buttonPressStreamController.add(btn);
          _onButtonPressed(btn);
          notifyListeners();
        }
      } else {
        if (_pressedButtons.contains(btn)) {
          _pressedButtons.remove(btn);
          _onButtonReleased(btn);
          notifyListeners();
        }
      }
    } else if (event.axis != null) {
      final axis = event.axis!;
      final val = event.value;
      switch (axis) {
        case GamepadAxis.leftStickX:
          _leftStickX = val;
          break;
        case GamepadAxis.leftStickY:
          _leftStickY = val;
          break;
        case GamepadAxis.rightStickX:
          _rightStickX = val;
          break;
        case GamepadAxis.rightStickY:
          _rightStickY = val;
          break;
        case GamepadAxis.leftTrigger:
        case GamepadAxis.rightTrigger:
          break;
      }
      notifyListeners();
    }
  }

  void _onButtonPressed(GamepadButton button) {
    final action = _buttonMapping[button] ?? GamepadAction.none;
    switch (action) {
      case GamepadAction.dock:
        _triggerDock();
        break;
      case GamepadAction.undock:
        _triggerUndock();
        break;
      case GamepadAction.emergencyStop:
        _triggerEmergencyStop();
        break;
      case GamepadAction.pauseResumeMission:
        _triggerPauseResumeMission();
        break;
      case GamepadAction.nextWaypoint:
        _cycleWaypoint(1);
        break;
      case GamepadAction.prevWaypoint:
        _cycleWaypoint(-1);
        break;
      case GamepadAction.goToWaypoint:
        _triggerGoToWaypoint();
        break;
      case GamepadAction.rotateLeft:
      case GamepadAction.rotateRight:
      case GamepadAction.deadman:
      case GamepadAction.turbo:
      case GamepadAction.none:
        break;
    }
  }

  void _onButtonReleased(GamepadButton button) {
    final action = _buttonMapping[button] ?? GamepadAction.none;
    if (action == GamepadAction.deadman) {
      _publishZeroTwist();
    }
  }

  // Teleop 20Hz Tick Loop
  void _startTeleopLoop() {
    _teleopTimer?.cancel();
    _teleopTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _processTeleopTick();
    });
  }

  void _processTeleopTick() {
    if (!_isConnected) return;

    // Check deadman switch if enabled
    bool deadmanSatisfied = !_requireDeadman;
    if (_requireDeadman) {
      for (final entry in _buttonMapping.entries) {
        if (entry.value == GamepadAction.deadman && _pressedButtons.contains(entry.key)) {
          deadmanSatisfied = true;
          break;
        }
      }
    }

    if (!deadmanSatisfied) return;

    // Check turbo switch
    bool isTurbo = false;
    for (final entry in _buttonMapping.entries) {
      if (entry.value == GamepadAction.turbo && _pressedButtons.contains(entry.key)) {
        isTurbo = true;
        break;
      }
    }

    // Deadzone application
    double rawX = _leftStickX;
    double rawY = _leftStickY;
    if (_invertLinear) rawY = -rawY;

    // In gamepad convention: +1 is Up, -1 is Down.
    // In ROS Twist: +linear.x is Forward, -linear.x is Backward.
    // Left stick X: -1 is Left, +1 is Right.
    // In ROS Twist: +angular.z is CCW (turn Left), -angular.z is CW (turn Right).
    double linMag = rawY.abs();
    double angMag = rawX.abs();

    double lin = 0.0;
    if (linMag > _deadzone) {
      double scale = (linMag - _deadzone) / (1.0 - _deadzone);
      lin = rawY.sign * (scale * scale); // Quadratic curve for smooth low-speed
    }

    double ang = 0.0;
    if (angMag > _deadzone) {
      double scale = (angMag - _deadzone) / (1.0 - _deadzone);
      ang = -rawX.sign * (scale * scale); // Invert X for ROS CCW convention
    }

    // Check in-place rotation buttons
    for (final entry in _buttonMapping.entries) {
      if (_pressedButtons.contains(entry.key)) {
        if (entry.value == GamepadAction.rotateLeft) ang = 1.0;
        if (entry.value == GamepadAction.rotateRight) ang = -1.0;
      }
    }

    // Apply speed caps
    final maxLin = isTurbo ? _turboLinearSpeed : _normalLinearSpeed;
    final maxAng = isTurbo ? _turboAngularSpeed : _normalAngularSpeed;

    final linCmd = lin * maxLin;
    final angCmd = ang * maxAng;

    if (linCmd.abs() > 0.001 || angCmd.abs() > 0.001) {
      _publishTwist(linCmd, angCmd);
    }
  }

  void _publishTwist(double linear, double angular) {
    final pub = _cmdVelPub;
    if (pub == null || _ros2 == null || _ros2!.status != Status.connected) return;
    final twist = geometry_msgs.Twist();
    twist.linear.x = linear;
    twist.angular.z = angular;
    pub.publish(twist);
  }

  void _publishZeroTwist() {
    final pub = _cmdVelPub;
    if (pub == null || _ros2 == null || _ros2!.status != Status.connected) return;
    final twist = geometry_msgs.Twist();
    for (int i = 0; i < 2; i++) {
      pub.publish(twist);
    }
  }

  // Action Triggers
  Future<void> _triggerDock() async {
    _hudStreamController.add('🔌 Docking Initiated');
    final api = _sdkApi;
    if (api != null) {
      try {
        await api.dock();
      } catch (e) {
        debugPrint('[GamepadService] Dock failed: $e');
      }
    }
  }

  Future<void> _triggerUndock() async {
    _hudStreamController.add('🚀 Undocking Initiated');
    final api = _sdkApi;
    if (api != null) {
      try {
        await api.undock();
      } catch (e) {
        debugPrint('[GamepadService] Undock failed: $e');
      }
    }
  }

  Future<void> _triggerEmergencyStop() async {
    _hudStreamController.add('🛑 EMERGENCY STOP');
    _publishZeroTwist();
    final api = _sdkApi;
    if (api != null) {
      try {
        await api.cancelNavigation();
      } catch (e) {
        debugPrint('[GamepadService] Cancel failed: $e');
      }
    }
  }

  Future<void> _triggerPauseResumeMission() async {
    _hudStreamController.add('⏯️ Mission Toggle');
  }

  Future<void> _refreshWaypoints() async {
    final api = _sdkApi;
    if (api == null) return;
    try {
      final res = await api.listWaypoints();
      _waypoints = List<Map<String, dynamic>>.from(res);
      if (_selectedWaypointIndex >= _waypoints.length) {
        _selectedWaypointIndex = max(0, _waypoints.length - 1);
      }
      notifyListeners();
    } catch (e) {
      // Ignored
    }
  }

  void _cycleWaypoint(int delta) {
    if (_waypoints.isEmpty) {
      _refreshWaypoints();
      return;
    }
    _selectedWaypointIndex = (_selectedWaypointIndex + delta) % _waypoints.length;
    if (_selectedWaypointIndex < 0) _selectedWaypointIndex += _waypoints.length;
    final name = _waypoints[_selectedWaypointIndex]['name'] ?? 'Waypoint';
    _hudStreamController.add('📍 Selected: $name');
    notifyListeners();
  }

  Future<void> _triggerGoToWaypoint() async {
    if (_waypoints.isEmpty) {
      _hudStreamController.add('⚠️ No Waypoints Saved');
      return;
    }
    final wp = _waypoints[_selectedWaypointIndex];
    final name = wp['name'] as String? ?? '';
    if (name.isEmpty) return;
    _hudStreamController.add('🎯 Navigating to $name');
    final api = _sdkApi;
    if (api != null) {
      try {
        await api.goToWaypoint(name);
      } catch (e) {
        debugPrint('[GamepadService] Navigate to waypoint failed: $e');
      }
    }
  }

  // Remapping & Settings Mutators
  void remapButton(GamepadButton button, GamepadAction action) {
    _buttonMapping[button] = action;
    _savePreferences();
    notifyListeners();
  }

  void setDeadzone(double val) {
    _deadzone = val.clamp(0.02, 0.40);
    _savePreferences();
    notifyListeners();
  }

  void setNormalLinearSpeed(double val) {
    _normalLinearSpeed = val.clamp(0.05, 0.40);
    _savePreferences();
    notifyListeners();
  }

  void setTurboLinearSpeed(double val) {
    _turboLinearSpeed = val.clamp(0.10, 0.60);
    _savePreferences();
    notifyListeners();
  }

  void setNormalAngularSpeed(double val) {
    _normalAngularSpeed = val.clamp(0.15, 1.20);
    _savePreferences();
    notifyListeners();
  }

  void setTurboAngularSpeed(double val) {
    _turboAngularSpeed = val.clamp(0.30, 2.00);
    _savePreferences();
    notifyListeners();
  }

  void setInvertLinear(bool val) {
    _invertLinear = val;
    _savePreferences();
    notifyListeners();
  }

  void setRequireDeadman(bool val) {
    _requireDeadman = val;
    _savePreferences();
    notifyListeners();
  }

  void resetToDefaults() {
    _deadzone = 0.10;
    _normalLinearSpeed = 0.12;
    _turboLinearSpeed = 0.25;
    _normalAngularSpeed = 0.45;
    _turboAngularSpeed = 0.75;
    _invertLinear = false;
    _requireDeadman = true;

    _buttonMapping.clear();
    _buttonMapping.addAll({
      GamepadButton.leftBumper: GamepadAction.deadman,
      GamepadButton.rightBumper: GamepadAction.turbo,
      GamepadButton.a: GamepadAction.dock,
      GamepadButton.b: GamepadAction.emergencyStop,
      GamepadButton.y: GamepadAction.undock,
      GamepadButton.x: GamepadAction.goToWaypoint,
      GamepadButton.dpadUp: GamepadAction.nextWaypoint,
      GamepadButton.dpadDown: GamepadAction.prevWaypoint,
      GamepadButton.dpadLeft: GamepadAction.rotateLeft,
      GamepadButton.dpadRight: GamepadAction.rotateRight,
      GamepadButton.start: GamepadAction.pauseResumeMission,
    });
    _savePreferences();
    notifyListeners();
  }

  // Persistence
  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('gamepad_deadzone', _deadzone);
    await prefs.setDouble('gamepad_normal_lin', _normalLinearSpeed);
    await prefs.setDouble('gamepad_turbo_lin', _turboLinearSpeed);
    await prefs.setDouble('gamepad_normal_ang', _normalAngularSpeed);
    await prefs.setDouble('gamepad_turbo_ang', _turboAngularSpeed);
    await prefs.setBool('gamepad_invert_lin', _invertLinear);
    await prefs.setBool('gamepad_require_deadman', _requireDeadman);

    for (final btn in GamepadButton.values) {
      final act = _buttonMapping[btn] ?? GamepadAction.none;
      await prefs.setString('gamepad_btn_${btn.name}', act.name);
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _deadzone = prefs.getDouble('gamepad_deadzone') ?? 0.10;
    _normalLinearSpeed = prefs.getDouble('gamepad_normal_lin') ?? 0.12;
    _turboLinearSpeed = prefs.getDouble('gamepad_turbo_lin') ?? 0.25;
    _normalAngularSpeed = prefs.getDouble('gamepad_normal_ang') ?? 0.45;
    _turboAngularSpeed = prefs.getDouble('gamepad_turbo_ang') ?? 0.75;
    _invertLinear = prefs.getBool('gamepad_invert_lin') ?? false;
    _requireDeadman = prefs.getBool('gamepad_require_deadman') ?? true;

    for (final btn in GamepadButton.values) {
      final savedAct = prefs.getString('gamepad_btn_${btn.name}');
      if (savedAct != null) {
        final match = GamepadAction.values.firstWhere(
          (a) => a.name == savedAct,
          orElse: () => GamepadAction.none,
        );
        _buttonMapping[btn] = match;
      }
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _connSub?.cancel();
    _teleopTimer?.cancel();
    _scanTimer?.cancel();
    _cmdVelPub?.shutdown();
    _hudStreamController.close();
    _buttonPressStreamController.close();
    super.dispose();
  }
}
