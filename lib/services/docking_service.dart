import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_msgs/msg.dart' as std_msgs;
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import '../helpers/conversions.dart';
import '../providers/connection_provider.dart';
import 'tf_service.dart';

/// Thin client for navpromini_controller's dock_manager_node — the robot-side
/// contract point every client (this app, a future web API) should use for
/// docking instead of touching docking_server/bt_navigator directly. All the
/// actual orchestration (staging, detection, approach, seat-nudge,
/// undock-before-goal) lives on the robot; this service just calls the two
/// actions it exposes and mirrors its /dock_status.
///
/// Singleton, same pattern as TFService — shared across the status bar,
/// the Dock UI, and mission execution.
class DockingService extends ChangeNotifier {
  static DockingService? _instance;
  static DockingService get instance => _instance ??= DockingService._();
  DockingService._();

  static const String dockActionName = '/dock';
  static const String undockActionName = '/undock';
  static const String dockActionType = 'nav2_msgs/action/DockRobot';
  static const String undockActionType = 'nav2_msgs/action/NavigateToPose';
  static const String dockPoseTopic = '/dock_pose';

  Ros2? _ros2;
  Subscriber<std_msgs.StringMessage>? _statusSub;
  DynamicActionClient? _dockClient;
  DynamicActionClient? _undockClient;
  Publisher<geometry_msgs.PoseStamped>? _dockPosePub;

  String _status = 'undocked';
  String get status => _status;

  /// dock_manager_node only reports 'charging'/'full' once actually docked
  /// (post seat-nudge) — every other status means not-yet-docked or
  /// mid-transition. See dock_manager_node.py's _execute_dock/_on_battery.
  bool get isDocked => _status == 'charging' || _status == 'full';
  bool get isBusy => const {
        'staging',
        'detecting',
        'docking',
        'waiting_for_charge',
        'undocking',
      }.contains(_status);

  void initialize(BuildContext context) {
    final ros2 =
        Provider.of<ConnectionProvider>(context, listen: false).ros2Client;
    if (identical(_ros2, ros2)) return; // already wired to this connection
    _teardown();
    _ros2 = ros2;

    try {
      _statusSub = Subscriber<std_msgs.StringMessage>(
        name: '/dock_status',
        type: std_msgs.StringMessage().fullType,
        ros2: ros2,
        prototype: std_msgs.StringMessage(),
        callback: (msg) {
          if (msg.data.isEmpty || msg.data == _status) return;
          _status = msg.data;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('DockingService: /dock_status subscribe failed: $e');
    }

    _dockClient = DynamicActionClient(
      ros2: ros2,
      actionName: dockActionName,
      actionType: dockActionType,
    );
    _undockClient = DynamicActionClient(
      ros2: ros2,
      actionName: undockActionName,
      actionType: undockActionType,
    );
    _dockPosePub = Publisher<geometry_msgs.PoseStamped>(
      name: dockPoseTopic,
      type: geometry_msgs.PoseStamped().fullType,
      ros2: ros2,
    );
  }

  /// Tells the robot where the dock is, independent of actually docking —
  /// dock_manager_node persists this (survives a node/robot restart) so a
  /// future web API client or a plain `ros2 action send_goal` from a
  /// terminal can dock without needing this app's bookmark data. Call this
  /// whenever the dock bookmark is created, edited, or repositioned.
  void publishDockPose(double x, double y, double theta,
      {String frameId = 'map'}) {
    final pub = _dockPosePub;
    if (pub == null) return;
    final q = eulerToQuaternion(0, 0, theta);
    pub.publish(geometry_msgs.PoseStamped(
      header: std_msgs.Header(frame_id: frameId),
      pose: geometry_msgs.Pose(
        position: geometry_msgs.Point(x: x, y: y, z: 0.0),
        orientation:
            geometry_msgs.Quaternion(x: q.x, y: q.y, z: q.z, w: q.w),
      ),
    ));
  }

  Map<String, dynamic> _poseStampedArgs(
      double x, double y, double theta, String frameId) {
    final q = eulerToQuaternion(0, 0, theta);
    return {
      'header': {
        'frame_id': frameId,
        'stamp': {'sec': 0, 'nanosec': 0},
      },
      'pose': {
        'position': {'x': x, 'y': y, 'z': 0.0},
        'orientation': {'x': q.x, 'y': q.y, 'z': q.z, 'w': q.w},
      },
    };
  }

  /// Docks at (x, y, theta) — dock_manager_node handles staging nav,
  /// detection-assisted approach/centering, waiting for confirmed charging,
  /// and the final seat-nudge. [theta] should point the dock's connector
  /// face outward (same convention as the dock bookmark placement).
  Future<Map<String, dynamic>?> dock({
    required double x,
    required double y,
    required double theta,
    String frameId = 'map',
    String dockType = 'simple_charging_dock',
    Duration timeout = const Duration(minutes: 3),
    void Function(Map<String, dynamic> feedback)? onFeedback,
  }) async {
    final client = _dockClient;
    if (client == null) {
      throw StateError('DockingService not initialized — call initialize(context) first');
    }
    final goalArgs = {
      'use_dock_id': false,
      'dock_id': '',
      'dock_pose': _poseStampedArgs(x, y, theta, frameId),
      'dock_type': dockType,
      'max_staging_time': 1000.0,
      'navigate_to_staging_pose': true,
    };
    return client.send(goalArgs: goalArgs, timeout: timeout, onFeedback: onFeedback);
  }

  /// The entry point for sending ANY nav goal on this robot: undocks first
  /// if currently docked, then navigates to (x, y, theta).
  Future<Map<String, dynamic>?> undock({
    required double x,
    required double y,
    required double theta,
    String frameId = 'map',
    Duration timeout = const Duration(minutes: 10),
    void Function(Map<String, dynamic> feedback)? onFeedback,
  }) async {
    final client = _undockClient;
    if (client == null) {
      throw StateError('DockingService not initialized — call initialize(context) first');
    }
    final goalArgs = {'pose': _poseStampedArgs(x, y, theta, frameId)};
    return client.send(goalArgs: goalArgs, timeout: timeout, onFeedback: onFeedback);
  }

  /// Undocks without traveling elsewhere — targets the robot's own
  /// last-known pose. Used by the "Undock" mission item.
  Future<Map<String, dynamic>?> undockInPlace({
    Duration timeout = const Duration(minutes: 1),
  }) async {
    final pos = TFService.instance.lastKnownPosition;
    if (pos == null) {
      throw StateError('Robot pose unknown — cannot undock in place');
    }
    final euler = quaternionToEuler(pos['q']);
    return undock(
      x: pos['x'] as double,
      y: pos['y'] as double,
      theta: euler[2],
      timeout: timeout,
    );
  }

  void cancelCurrent() {
    try {
      _dockClient?.cancelGoal();
      _undockClient?.cancelGoal();
    } catch (_) {}
  }

  void _teardown() {
    _statusSub?.shutdown();
    _statusSub = null;
    _dockClient?.dispose();
    _dockClient = null;
    _undockClient?.dispose();
    _undockClient = null;
    _dockPosePub?.shutdown();
    _dockPosePub = null;
  }

  void shutdown() {
    _teardown();
    _ros2 = null;
    _status = 'undocked';
  }
}
