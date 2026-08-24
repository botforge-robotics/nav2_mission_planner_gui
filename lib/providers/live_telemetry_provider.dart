import 'package:flutter/foundation.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:sensor_msgs/msg.dart' as sensor_msgs;
import 'package:std_msgs/msg.dart' as std_msgs;
import 'package:nav2_mission_planner/providers/connection_provider.dart';

/// Connection-scoped, shared readout of the robot's battery/temperature and
/// current teleop command — the pieces of "live state" that were previously
/// fetched independently in more than one widget.
///
/// Today this centralizes exactly two subscriptions that were duplicated:
/// `TopStatusBattery` and `TopStatusTemperature` each opened their own
/// `/battery/state` subscription for the same message; both now read from
/// here instead. It also gives screens that own a joystick
/// (`navigation_screen.dart`, `mapping_screen.dart`, `teleop_screen.dart`) a
/// shared place to *report* the current teleop command
/// ([reportTeleopCommand]) so screens without a joystick (Dashboard, Robot
/// Status) can read "is teleop active right now" from one place instead of
/// each owning a private `_teleopActive` bool.
///
/// Deliberately narrower than the full "live telemetry" scope discussed in
/// the redesign plan: robot **pose** and **measured velocity** are left out
/// of this pass. Those are entangled with `TFService`'s existing
/// map/odom/base_link transform chain and `navigation_screen.dart`'s
/// settings-driven odom-topic/type switching (`SettingsProvider
/// .navigationOdomTopic` / `.navigationOdomTopicType`), which already has
/// two overlapping pose sources (TFService's stream and a local
/// `_robotPositionController`). Centralizing that safely needs
/// hardware-verified testing against real robot traffic, not a blind
/// refactor bundled into a broader visual-redesign pass — tracked as
/// follow-up work rather than done here.
class LiveTelemetryProvider extends ChangeNotifier {
  ConnectionProvider? _connection;
  bool _subscribed = false;

  Subscriber<sensor_msgs.BatteryState>? _batterySub;
  Subscriber<std_msgs.Float32>? _cpuTempSub;

  double? _batteryPercent; // 0-100
  double? _batteryTempC;
  double? _cpuTempC;

  double? _commandedLinear;
  double? _commandedAngular;
  bool _teleopActive = false;

  double? get batteryPercent => _batteryPercent;
  double? get batteryTempC => _batteryTempC;
  double? get cpuTempC => _cpuTempC;

  double? get commandedLinear => _commandedLinear;
  double? get commandedAngular => _commandedAngular;
  bool get teleopActive => _teleopActive;

  /// Called from `main.dart`'s `ChangeNotifierProxyProvider` whenever
  /// [ConnectionProvider] changes, mirroring the subscribe/unsubscribe-on-
  /// connect pattern already used by `TopStatusBattery`/`TopStatusTemperature`.
  void updateConnection(ConnectionProvider connection) {
    _connection = connection;
    if (connection.isConnected && !_subscribed) {
      _subscribe();
    } else if (!connection.isConnected && _subscribed) {
      _unsubscribe();
    }
  }

  void _subscribe() {
    final conn = _connection;
    if (conn == null) return;
    try {
      _batterySub?.shutdown();
      _batterySub = Subscriber<sensor_msgs.BatteryState>(
        name: '/battery/state',
        type: sensor_msgs.BatteryState().fullType,
        ros2: conn.ros2Client,
        prototype: sensor_msgs.BatteryState(),
        callback: _onBattery,
      );
      _cpuTempSub?.shutdown();
      _cpuTempSub = Subscriber<std_msgs.Float32>(
        name: '/system/cpu_temperature',
        type: std_msgs.Float32().fullType,
        ros2: conn.ros2Client,
        prototype: std_msgs.Float32(),
        callback: _onCpuTemp,
      );
      _subscribed = true;
    } catch (_) {
      _subscribed = false;
    }
  }

  void _onBattery(sensor_msgs.BatteryState msg) {
    // ROS BatteryState.percentage is usually 0.0-1.0; some stacks use 0-100.
    var p = msg.percentage;
    if (!p.isNaN && p >= 0) {
      if (p <= 1.0) p *= 100.0;
      if (p > 100.0) p = 100.0;
      _batteryPercent = p;
    }
    // Packs that don't report temperature leave this 0.0/NaN — don't surface
    // a bogus 0degC reading in that case (mirrors the prior per-widget check).
    final t = msg.temperature;
    if (!t.isNaN && t != 0.0) {
      _batteryTempC = t;
    }
    notifyListeners();
  }

  void _onCpuTemp(std_msgs.Float32 msg) {
    final v = msg.data;
    if (v.isNaN) return;
    _cpuTempC = v;
    notifyListeners();
  }

  void _unsubscribe() {
    _batterySub?.shutdown();
    _batterySub = null;
    _cpuTempSub?.shutdown();
    _cpuTempSub = null;
    _subscribed = false;
    _batteryPercent = null;
    _batteryTempC = null;
    _cpuTempC = null;
    _commandedLinear = null;
    _commandedAngular = null;
    _teleopActive = false;
    notifyListeners();
  }

  /// Screens that own a joystick call this on every teleop command they
  /// publish (whether or not it changed), so [teleopActive] reflects reality
  /// even for callers that only poll rather than listen.
  void reportTeleopCommand(double linear, double angular) {
    _commandedLinear = linear;
    _commandedAngular = angular;
    _teleopActive = linear != 0.0 || angular != 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }
}
