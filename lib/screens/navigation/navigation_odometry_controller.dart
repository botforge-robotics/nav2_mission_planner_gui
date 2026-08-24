import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:nav_msgs/msg.dart' as nav_msgs;
import 'package:ros2_api/ros2_api.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';

/// Owns navigation_screen.dart's odometry/velocity subscriptions and the
/// pose state they feed — extracted from `_NavigationScreenState` verbatim
/// (subsystem (c) in the extraction map): `_odomSubscriber`,
/// `_velocitySubscriber`, `_robotX/_robotY/_robotQ/_poseFrame/
/// _poseReceived/_measuredLinear/_measuredAngular/_currentOdomTopic/
/// _currentOdomType`, and their six methods.
///
/// Velocity is always read from `/odom` directly, independent of whatever
/// `navigationOdomTopic` drives position display. Position defaults to
/// `/amcl_pose` (accurate map-frame pose, no drift) — but amcl_pose carries
/// no twist at all, so when position uses it, velocity has nothing to draw
/// from unless it has its own subscription. Without this, the readout
/// showed "not reported" permanently once localized, not just before.
///
/// Callers (the screen) call [subscribeToOdometry]/[subscribeToVelocity]
/// with the `Ros2` client and topic/type they already resolved from
/// `ConnectionProvider`/`SettingsProvider` — this controller has no
/// `BuildContext` of its own and never reaches for `Provider.of` itself.
///
/// Deliberately does **not** override `dispose()` to shut down its
/// subscribers or close [robotPositionUpdates]'s controller: the original
/// `_NavigationScreenState.dispose()` never called
/// `_unsubscribeFromOdometry()` or closed `_robotPositionController`
/// either — cleanup only ever happened via the explicit stop-navigation
/// flow. That gap is preserved here rather than "fixed" as a side effect
/// of this extraction, since this is a behavior-preserving refactor, not a
/// bug pass — flag separately if it should actually be closed on dispose.
class NavigationOdometryController extends ChangeNotifier {
  Subscriber<dynamic>? _odomSubscriber;
  Subscriber<nav_msgs.Odometry>? _velocitySubscriber;

  double _robotX = 0.0;
  double _robotY = 0.0;
  geometry_msgs.Quaternion _robotQ = geometry_msgs.Quaternion();
  // Frame the pose above is measured in. Reported rather than assumed: an
  // odom pose is relative to wherever the robot last started, so it is not
  // comparable to a stored waypoint, and the readout has to say which it has.
  String _poseFrame = 'odom';
  bool _poseReceived = false;
  // Measured velocity from the odometry message, when the source provides it.
  // amcl_pose carries no twist, so these stay null on that path.
  double? _measuredLinear;
  double? _measuredAngular;
  String? _currentOdomTopic;
  String? _currentOdomType;

  // Written on every pose update (and on resetPose()) but never read
  // anywhere in the app — `_buildMapWidget` wires TFService's own
  // robotPositionStream instead. Kept because this extraction preserves
  // behavior exactly, including vestigial writes, rather than pruning them.
  final _robotPositionController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get robotPositionUpdates =>
      _robotPositionController.stream;

  double get robotX => _robotX;
  double get robotY => _robotY;
  geometry_msgs.Quaternion get robotQ => _robotQ;
  String get poseFrame => _poseFrame;
  bool get poseReceived => _poseReceived;
  double? get measuredLinear => _measuredLinear;
  double? get measuredAngular => _measuredAngular;

  void unsubscribeFromOdometry() {
    _odomSubscriber?.shutdown();
    _odomSubscriber = null;
    _currentOdomTopic = null;
    _currentOdomType = null;
    unsubscribeFromVelocity();
  }

  void subscribeToVelocity({
    required bool isNavigationActive,
    required ConnectionProvider connection,
  }) {
    if (!isNavigationActive || _velocitySubscriber != null) return;
    try {
      // connection.ros2Client throws if not connected — deliberately
      // accessed inside this try, matching the original inline code, so
      // that case is caught silently below rather than propagating.
      _velocitySubscriber = Subscriber<nav_msgs.Odometry>(
        name: '/odom',
        type: nav_msgs.Odometry().fullType,
        ros2: connection.ros2Client,
        callback: (message) {
          _measuredLinear = message.twist.twist.linear.x;
          _measuredAngular = message.twist.twist.angular.z;
          notifyListeners();
        },
        prototype: nav_msgs.Odometry(),
      );
    } catch (e) {
      // Silent error handling, matches subscribeToOdometry below.
    }
  }

  void unsubscribeFromVelocity() {
    _velocitySubscriber?.shutdown();
    _velocitySubscriber = null;
  }

  void subscribeToOdometry({
    required bool isNavigationActive,
    required ConnectionProvider connection,
    required String topic,
    required String type,
  }) {
    if (!isNavigationActive) return;

    if (topic == _currentOdomTopic && type == _currentOdomType) return;
    _currentOdomTopic = topic;
    _currentOdomType = type;
    // Unsubscribe from old topic
    if (_odomSubscriber != null) {
      _odomSubscriber?.shutdown();
      _odomSubscriber = null;
    }
    try {
      // Create subscriber based on message type. connection.ros2Client
      // throws if not connected — deliberately accessed inside this try,
      // matching the original inline code.
      if (type == 'nav_msgs/msg/Odometry') {
        _odomSubscriber = Subscriber<nav_msgs.Odometry>(
          name: topic,
          type: nav_msgs.Odometry().fullType,
          ros2: connection.ros2Client,
          callback: _processNavOdomMessage,
          prototype: nav_msgs.Odometry(),
        );
      } else if (type == 'geometry_msgs/msg/PoseWithCovarianceStamped') {
        _odomSubscriber = Subscriber<geometry_msgs.PoseWithCovarianceStamped>(
          name: topic,
          type: geometry_msgs.PoseWithCovarianceStamped().fullType,
          ros2: connection.ros2Client,
          callback: _processPoseMessage,
          prototype: geometry_msgs.PoseWithCovarianceStamped(),
        );
      }
    } catch (e) {
      // Silent error handling
    }
  }

  void _processNavOdomMessage(nav_msgs.Odometry message) {
    _robotX = message.pose.pose.position.x;
    _robotY = message.pose.pose.position.y;
    _robotQ = message.pose.pose.orientation;
    _poseFrame =
        message.header.frame_id.isNotEmpty ? message.header.frame_id : 'odom';
    _poseReceived = true;
    _measuredLinear = message.twist.twist.linear.x;
    _measuredAngular = message.twist.twist.angular.z;

    // Send position update through stream
    _robotPositionController.add({
      'x': _robotX,
      'y': _robotY,
      'q': _robotQ,
    });
    notifyListeners();
  }

  void _processPoseMessage(geometry_msgs.PoseWithCovarianceStamped message) {
    _robotX = message.pose.pose.position.x;
    _robotY = message.pose.pose.position.y;
    _robotQ = message.pose.pose.orientation;
    _poseFrame =
        message.header.frame_id.isNotEmpty ? message.header.frame_id : 'map';
    _poseReceived = true;
    // PoseWithCovarianceStamped carries no twist — don't touch
    // _measuredLinear/_measuredAngular here. They're kept up to date by
    // their own dedicated /odom subscription (subscribeToVelocity),
    // independent of whichever topic drives position display.

    // Send position update through stream
    _robotPositionController.add({
      'x': _robotX,
      'y': _robotY,
      'q': _robotQ,
    });
    notifyListeners();
  }

  /// Resets pose to the origin — mirrors what `_stopNavigation` used to do
  /// directly to its own `_robotX`/`_robotY`/`_robotQ` fields and the
  /// stream push that followed.
  void resetPose() {
    _robotX = 0.0;
    _robotY = 0.0;
    _robotQ = geometry_msgs.Quaternion();
    _robotPositionController.add({
      'x': _robotX,
      'y': _robotY,
      'q': _robotQ,
    });
    notifyListeners();
  }
}
