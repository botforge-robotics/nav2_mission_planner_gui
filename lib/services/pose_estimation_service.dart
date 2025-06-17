import 'package:flutter/material.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:builtin_interfaces/msg.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:provider/provider.dart';

class PoseEstimationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey();
  static Publisher<geometry_msgs.PoseWithCovarianceStamped>? _publisher;
  static bool _isInitialized = false;

  static void initializePublisher(BuildContext context) {
    if (_isInitialized) return;

    final connection = Provider.of<ConnectionProvider>(context, listen: false);
    if (connection.ros2Client == null) return;

    _publisher = Publisher<geometry_msgs.PoseWithCovarianceStamped>(
      name: '/initialpose',
      type: geometry_msgs.PoseWithCovarianceStamped().fullType,
      ros2: connection.ros2Client!,
    );

    _isInitialized = true;
  }

  static void publishPoseEstimate(
      {required BuildContext context,
      required double x,
      required double y,
      required geometry_msgs.Quaternion theta}) {
    // Initialize publisher if not already done
    if (!_isInitialized) {
      initializePublisher(context);
    }

    if (_publisher == null) {
      print('Error: Publisher not initialized');
      return;
    }

    final poseMsg = geometry_msgs.PoseWithCovarianceStamped()
      ..header.stamp = Time(
          sec: DateTime.now().toUtc().second,
          nanosec: DateTime.now().toUtc().millisecond * 1000000)
      ..header.frame_id = 'map'
      ..pose.pose.position.x = x
      ..pose.pose.position.y = y
      ..pose.pose.position.z = 0.0
      ..pose.pose.orientation = theta
      ..pose.covariance = [
        0.25,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.25,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.06853891909122467
      ];

    _publisher!.publish(poseMsg);
  }
}
