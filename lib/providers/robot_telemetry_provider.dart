import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:nav_msgs/msg.dart' as nav_msgs;
import 'package:ros2_api/ros2_api.dart';
import 'package:sensor_msgs/msg.dart' as sensor_msgs;
import 'package:std_msgs/msg.dart' as std_msgs;

/// power_supply_status values, straight off the ROS2 sensor_msgs/BatteryState
/// standard — same mapping navpromini_sdk's ros_bridge.py._CHARGE already
/// uses on the robot side, mirrored here rather than reinvented.
enum ChargeStatus { unknown, charging, discharging, notCharging, full }

ChargeStatus _chargeStatusOf(int value) => switch (value) {
      1 => ChargeStatus.charging,
      2 => ChargeStatus.discharging,
      3 => ChargeStatus.notCharging,
      4 => ChargeStatus.full,
      _ => ChargeStatus.unknown,
    };

/// Live telemetry via direct rosbridge topic subscriptions — the app's
/// primary data path, independent of navpromini_sdk (see ConnectionProvider
/// and navpromini-sdk-is-optional-not-gateway in project memory). Every
/// field starts null and stays null until its topic actually publishes —
/// "no data yet" is a real, distinct state from a zero/default that could be
/// mistaken for a real reading, the same convention RosBridge's own cache
/// uses on the robot side.
class RobotTelemetryProvider extends ChangeNotifier {
  RobotTelemetryProvider(this._ros2) {
    _subscribe();
  }

  final Ros2 _ros2;
  final List<Subscriber> _subscribers = [];

  double? batteryPercentage;
  ChargeStatus? chargeStatus;
  double? linearSpeedMps;
  bool localized = false;
  String? dockStatus;
  double? poseX;
  double? poseY;

  /// Yaw, radians, derived from `/amcl_pose`'s quaternion — same formula
  /// `occupancy_grid_view.dart`'s painter already uses for the robot marker,
  /// mirrored here rather than shared, since one is ROS-message-shaped math
  /// and the other is a provider field with no natural common module yet.
  double? poseTheta;

  void _subscribe() {
    _subscribers.addAll([
      Subscriber<sensor_msgs.BatteryState>(
        name: '/battery/state',
        type: sensor_msgs.BatteryState().fullType,
        ros2: _ros2,
        prototype: sensor_msgs.BatteryState(),
        callback: (msg) {
          // sensor_msgs/BatteryState.percentage is conventionally a 0-1
          // fraction; some stacks report 0-100 directly. Same normalization
          // navpromini_sdk's own ros_bridge.py._on_battery already applies
          // on the robot side, mirrored here rather than assuming one
          // convention.
          final pct = msg.percentage;
          batteryPercentage = pct <= 1.0 ? pct * 100.0 : pct;
          chargeStatus = _chargeStatusOf(msg.power_supply_status);
          notifyListeners();
        },
      ),
      Subscriber<nav_msgs.Odometry>(
        name: '/odom',
        type: nav_msgs.Odometry().fullType,
        ros2: _ros2,
        prototype: nav_msgs.Odometry(),
        callback: (msg) {
          linearSpeedMps = msg.twist.twist.linear.x;
          notifyListeners();
        },
      ),
      Subscriber<geometry_msgs.PoseWithCovarianceStamped>(
        name: '/amcl_pose',
        type: geometry_msgs.PoseWithCovarianceStamped().fullType,
        ros2: _ros2,
        prototype: geometry_msgs.PoseWithCovarianceStamped(),
        callback: (msg) {
          localized = true;
          poseX = msg.pose.pose.position.x;
          poseY = msg.pose.pose.position.y;
          final q = msg.pose.pose.orientation;
          poseTheta = atan2(
              2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z));
          notifyListeners();
        },
      ),
      Subscriber<std_msgs.StringMessage>(
        name: '/dock_status',
        type: std_msgs.StringMessage().fullType,
        ros2: _ros2,
        prototype: std_msgs.StringMessage(),
        callback: (msg) {
          dockStatus = msg.data;
          notifyListeners();
        },
      ),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subscribers) {
      s.unsubscribe();
    }
    super.dispose();
  }
}
