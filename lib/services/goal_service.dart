import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:nav2_msgs/action.dart';
import 'package:rosapi_msgs/srv.dart';
import '../providers/connection_provider.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:std_msgs/msg.dart' as std_msgs;
import 'package:builtin_interfaces/msg.dart' as builtin_interfaces;

typedef _NavClient = ActionClient<
    NavigateToPose,
    NavigateToPoseGoal,
    NavigateToPoseActionGoal,
    NavigateToPoseFeedback,
    NavigateToPoseActionFeedback,
    NavigateToPoseResult,
    NavigateToPoseActionResult>;

class GoalService {
  // Robot-side contract point (navpromini_controller's dock_manager_node):
  // undocks first if currently docked, then relays to bt_navigator's
  // navigate_to_pose — same message type, different action server name.
  // Any client (this app, a future web API) should send goals here so the
  // undock-before-goal guard applies uniformly. Falls back to calling
  // /navigate_to_pose directly if /undock isn't advertised (older robot
  // image without the docking feature) rather than hanging forever.
  static const String _undockActionName = '/undock';
  static const String _navigateActionName = '/navigate_to_pose';

  late _NavClient _undockClient;
  late _NavClient _navigateClient;
  late Ros2 _ros2;

  void initialize({
    required BuildContext context,
  }) {
    _ros2 = Provider.of<ConnectionProvider>(context, listen: false).ros2Client;
    _undockClient = ActionClient(
      ros2: _ros2,
      actionName: _undockActionName,
      actionType: NavigateToPose().fullType,
      actionMessage: NavigateToPose(),
    );
    _navigateClient = ActionClient(
      ros2: _ros2,
      actionName: _navigateActionName,
      actionType: NavigateToPose().fullType,
      actionMessage: NavigateToPose(),
    );
  }

  /// Whether dock_manager_node's /undock is currently advertised. Checked
  /// per-call (not cached) since it can appear/disappear as robot launch
  /// files change — cheap rosapi round trip, not perf-sensitive.
  Future<bool> _isUndockAvailable() async {
    try {
      final client = ServiceClient<GetActionServers, GetActionServersRequest,
          GetActionServersResponse>(
        ros2: _ros2,
        name: '/rosapi/action_servers',
        type: GetActionServers().fullType,
        serviceType: GetActionServers(),
        timeout: 3.0,
      );
      final response = await client.call(GetActionServersRequest())
          .timeout(const Duration(seconds: 4));
      return response.action_servers.contains(_undockActionName);
    } catch (e) {
      debugPrint('GoalService._isUndockAvailable: $e');
      return false;
    }
  }

  /// True when bt_navigator lifecycle state is active (goals can run).
  Future<bool> isNav2Active(
      {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final client = DynamicServiceClient(
        ros2: _ros2,
        serviceName: '/bt_navigator/get_state',
        serviceType: 'lifecycle_msgs/srv/GetState',
      );
      final values = await client.call(requestArgs: {}, timeout: timeout);
      client.dispose();
      final label = values?['current_state']?['label']?.toString();
      return label == 'active';
    } catch (e) {
      debugPrint('GoalService.isNav2Active: $e');
      return false;
    }
  }

  /// Poll until Nav2 is active or timeout (after Start Navigation).
  Future<bool> waitUntilNav2Active({
    Duration timeout = const Duration(seconds: 45),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await isNav2Active()) return true;
      await Future.delayed(pollInterval);
    }
    return false;
  }

  _NavClient? _lastUsedClient;

  Future<NavigateToPoseResult?> sendGoal({
    required double x,
    required double y,
    required geometry_msgs.Quaternion orientation,
    required String frameId,
    Function(NavigateToPoseFeedback)? feedbackHandler,
  }) async {
    if (!await isNav2Active()) {
      throw Exception(
        'Nav2 is inactive (bt_navigator not ready). '
        'Stop Navigation, Start again, wait for map, set initial pose, then retry.',
      );
    }

    final goal = NavigateToPoseGoal()
      ..pose = geometry_msgs.PoseStamped(
        header: std_msgs.Header(
          stamp: builtin_interfaces.Time(
            sec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
          frame_id: frameId,
        ),
        pose: geometry_msgs.Pose(
          position: geometry_msgs.Point(x: x, y: y, z: 0.0),
          orientation: orientation,
        ),
      );

    final client =
        await _isUndockAvailable() ? _undockClient : _navigateClient;
    _lastUsedClient = client;

    try {
      final result = await client.sendGoal(
        goal,
        onFeedback: (feedback) {
          feedbackHandler?.call(feedback);
        },
      );
      return result;
    } catch (e) {
      debugPrint('GoalService.sendGoal error: $e');
      rethrow;
    }
  }

  void cancelCurrentGoal() {
    try {
      _lastUsedClient?.cancelGoal();
    } catch (e) {
      // Silent error handling
    }
  }
}
