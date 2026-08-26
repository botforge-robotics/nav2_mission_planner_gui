import 'dart:math';

import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:nav2_msgs/action.dart';
import 'package:ros2_api/ros2_api.dart';

/// A planned route's real distance (walked along the path Nav2's planner
/// actually produces, not a straight line through walls) plus a rough time
/// estimate. Nav2's own `ComputePathToPose` result carries planning_time
/// (how long the planner took to *compute* the path) but not a travel-time
/// estimate, so [etaSeconds] is this app's own estimate — path length
/// divided by an assumed cruise speed — not a value the nav stack reports.
class RouteEstimate {
  const RouteEstimate({required this.distanceMeters, required this.etaSeconds});

  final double distanceMeters;
  final double etaSeconds;
}

/// Calls Nav2's `/compute_path_to_pose` action (the planner_server the
/// robot already runs) to get a real route rather than a straight-line
/// guess — the straight line through a doorway-and-corridor floor plan is
/// often wildly wrong. Plain ROS-native call over rosbridge, same as every
/// other topic/service/action this app uses directly rather than routing
/// through the optional SDK (see navpromini-sdk-is-optional-not-gateway).
class RouteEstimateService {
  RouteEstimateService(this.ros2);

  final Ros2 ros2;

  // A conservative cruise-speed assumption for the ETA estimate — matches
  // DrivePad's own maxLinear, itself already the robot's real teleop speed
  // clamp, so this reads as "about how fast the robot actually drives"
  // rather than an arbitrary guess.
  static const _assumedSpeedMps = 0.3;

  /// Returns null if the planner can't produce a route (goal unreachable,
  /// robot not localized, action timeout, etc.) — callers should fall back
  /// to a straight-line distance rather than showing an error, since this
  /// is enrichment on top of "send the goal", not a precondition for it.
  Future<RouteEstimate?> estimate({
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
  }) async {
    final client = ActionClient<
        ComputePathToPose,
        ComputePathToPoseGoal,
        ComputePathToPoseActionGoal,
        ComputePathToPoseFeedback,
        ComputePathToPoseActionFeedback,
        ComputePathToPoseResult,
        ComputePathToPoseActionResult>(
      ros2: ros2,
      actionName: '/compute_path_to_pose',
      actionType: ComputePathToPose().fullType,
      actionMessage: ComputePathToPose(),
    );
    try {
      final goal = ComputePathToPoseGoal(
        start: geometry_msgs.PoseStamped(
          pose: geometry_msgs.Pose(
            position: geometry_msgs.Point(x: fromX, y: fromY),
            orientation: geometry_msgs.Quaternion(w: 1.0),
          ),
        ),
        goal: geometry_msgs.PoseStamped(
          pose: geometry_msgs.Pose(
            position: geometry_msgs.Point(x: toX, y: toY),
            orientation: geometry_msgs.Quaternion(w: 1.0),
          ),
        ),
        use_start: true,
      );
      final result =
          await client.sendGoal(goal).timeout(const Duration(seconds: 8));
      final poses = result.path.poses;
      if (poses.length < 2) return null;
      var distance = 0.0;
      for (var i = 1; i < poses.length; i++) {
        final a = poses[i - 1].pose.position;
        final b = poses[i].pose.position;
        distance += sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2));
      }
      return RouteEstimate(
        distanceMeters: distance,
        etaSeconds: distance / _assumedSpeedMps,
      );
    } catch (_) {
      return null;
    } finally {
      client.dispose();
    }
  }
}
