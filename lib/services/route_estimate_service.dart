import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:nav2_msgs/action.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_msgs/msg.dart' as std_msgs;

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

  Future<RouteEstimate?> _estimateWithGoal(ComputePathToPoseGoal goal) async {
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
      final result = await client
          .sendGoal(goal)
          .timeout(const Duration(seconds: 4));
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
    } catch (e) {
      debugPrint('ComputePathToPose attempt failed: $e');
      return null;
    } finally {
      client.dispose();
    }
  }

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
    try {
      // 1. Primary path: Use live robot pose (use_start: false) which uses Nav2's
      // actual TF tree and current localized footprint directly.
      final goalLive = ComputePathToPoseGoal(
        goal: geometry_msgs.PoseStamped(
          header: std_msgs.Header(frame_id: 'map'),
          pose: geometry_msgs.Pose(
            position: geometry_msgs.Point(x: toX, y: toY),
            orientation: geometry_msgs.Quaternion(w: 1.0),
          ),
        ),
        planner_id: '',
        use_start: false,
      );
      final liveEst = await _estimateWithGoal(goalLive);
      if (liveEst != null) return liveEst;

      // 2. Fallback path: Explicit start pose (e.g. if planning between remote waypoints).
      final goalWithStart = ComputePathToPoseGoal(
        start: geometry_msgs.PoseStamped(
          header: std_msgs.Header(frame_id: 'map'),
          pose: geometry_msgs.Pose(
            position: geometry_msgs.Point(x: fromX, y: fromY),
            orientation: geometry_msgs.Quaternion(w: 1.0),
          ),
        ),
        goal: geometry_msgs.PoseStamped(
          header: std_msgs.Header(frame_id: 'map'),
          pose: geometry_msgs.Pose(
            position: geometry_msgs.Point(x: toX, y: toY),
            orientation: geometry_msgs.Quaternion(w: 1.0),
          ),
        ),
        planner_id: '',
        use_start: true,
      );
      return await _estimateWithGoal(goalWithStart);
    } catch (e) {
      debugPrint('Route estimate calculation error: $e');
      return null;
    }
  }
}
