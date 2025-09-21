import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:tf2_msgs/msg.dart' as tf2_msgs;
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/occupancy_grid_viewer.dart';

class TFService {
  static TFService? _instance;
  static TFService get instance => _instance ??= TFService._();

  TFService._();

  Subscriber<tf2_msgs.TFMessage>? _tfSubscriber;
  final StreamController<Map<String, dynamic>> _robotPositionController =
      StreamController<Map<String, dynamic>>.broadcast();

  // TF buffer for transform caching
  final Map<String, Map<String, geometry_msgs.TransformStamped>> _tfBuffer = {};

  // Status tracking
  bool _isInitialized = false;
  bool _isTfAvailable = false;
  String? _lastError;

  // Cache last position to avoid unnecessary updates
  Map<String, dynamic>? _lastPosition;
  Timer? _positionUpdateTimer;

  Stream<Map<String, dynamic>> get robotPositionStream =>
      _robotPositionController.stream;
  bool get isTfAvailable => _isTfAvailable;
  String? get lastError => _lastError;

  void initialize(BuildContext context) {
    if (_isInitialized) return;

    final connection = Provider.of<ConnectionProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    _subscribeToTF(context, connection, settings);
    _isInitialized = true;
  }

  void _subscribeToTF(BuildContext context, ConnectionProvider connection,
      SettingsProvider settings) {
    try {
      _tfSubscriber = Subscriber<tf2_msgs.TFMessage>(
        name: settings.tfTopic,
        type: tf2_msgs.TFMessage().fullType,
        ros2: connection.ros2Client,
        callback: _processTFMessage,
        prototype: tf2_msgs.TFMessage(),
      );

      _isTfAvailable = true;
      _lastError = null;

      // Start periodic robot position updates
      _startRobotPositionUpdates(settings);
    } catch (e) {
      _isTfAvailable = false;
      _lastError = 'Failed to subscribe to TF: $e';
      debugPrint('TFService Error: $_lastError');
    }
  }

  void _processTFMessage(tf2_msgs.TFMessage message) {
    // Update TF buffer with new transforms
    for (final transform in message.transforms) {
      final parentFrame = transform.header.frame_id;
      final childFrame = transform.child_frame_id;

      if (!_tfBuffer.containsKey(parentFrame)) {
        _tfBuffer[parentFrame] = {};
      }
      _tfBuffer[parentFrame]![childFrame] = transform;
    }

    _isTfAvailable = true;
    _lastError = null;

    // Debug: Log TF message reception (only log when transforms change significantly)
    if (message.transforms.isNotEmpty) {
      final transformPairs = message.transforms
          .map((t) => '${t.header.frame_id}→${t.child_frame_id}')
          .join(', ');
      debugPrint(
          'TFService: Received TF message with ${message.transforms.length} transforms: $transformPairs');
    }
  }

  void _startRobotPositionUpdates(SettingsProvider settings) {
    // Cancel any existing timer
    _positionUpdateTimer?.cancel();

    // Update robot position every 50ms for better responsiveness to high-speed movements
    _positionUpdateTimer =
        Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_isInitialized) {
        timer.cancel();
        return;
      }

      _updateRobotPosition(settings);
    });
  }

  void _updateRobotPosition(SettingsProvider settings) {
    try {
      // Debug: Log available frames in TF buffer
      final availableFrames = <String>{};
      for (final parentFrame in _tfBuffer.keys) {
        availableFrames.add(parentFrame);
        for (final childFrame in _tfBuffer[parentFrame]!.keys) {
          availableFrames.add(childFrame);
        }
      }

      debugPrint('=== TF ROBOT POSITION DEBUG ===');
      debugPrint(
          'Available frames (${availableFrames.length}): ${availableFrames.join(', ')}');
      debugPrint(
          'Target chain: ${settings.mapFrame} → ${settings.odomFrame} → ${settings.baseLinkFrame}');
      debugPrint(
          'Direct fallback: ${settings.mapFrame} → ${settings.baseLinkFrame}');

      // Try full chain: map → odom → base_link
      final robotTransform = _getTransformChain(
        settings.mapFrame,
        settings.odomFrame,
        settings.baseLinkFrame,
      );

      if (robotTransform != null) {
        final position = robotTransform.transform.translation;
        final orientation = robotTransform.transform.rotation;

        debugPrint(
            '✓ Found full chain transform: x=${position.x.toStringAsFixed(3)}, y=${position.y.toStringAsFixed(3)}');

        final newPosition = {
          'x': position.x,
          'y': position.y,
          'q': orientation,
        };

        // Only send update if position has changed significantly
        if (_lastPosition == null ||
            _hasPositionChanged(_lastPosition!, newPosition)) {
          _robotPositionController.add(newPosition);
          _lastPosition = newPosition;
        }
        debugPrint('=============================');
        return;
      }

      debugPrint('✗ Full chain failed, trying direct transform...');

      // Fallback: try direct map → base_link
      final directTransform = _getDirectTransform(
        settings.mapFrame,
        settings.baseLinkFrame,
      );

      if (directTransform != null) {
        final position = directTransform.transform.translation;
        final orientation = directTransform.transform.rotation;

        debugPrint(
            '✓ Found direct transform: x=${position.x.toStringAsFixed(3)}, y=${position.y.toStringAsFixed(3)}');

        final newPosition = {
          'x': position.x,
          'y': position.y,
          'q': orientation,
        };

        // Only send update if position has changed significantly
        if (_lastPosition == null ||
            _hasPositionChanged(_lastPosition!, newPosition)) {
          _robotPositionController.add(newPosition);
          _lastPosition = newPosition;
        }
        debugPrint('=============================');
        return;
      }

      // No transform available - log detailed debug info
      debugPrint('✗ No transform available!');
      debugPrint('Missing frames:');
      if (!availableFrames.contains(settings.mapFrame)) {
        debugPrint('  - Missing map frame: ${settings.mapFrame}');
      }
      if (!availableFrames.contains(settings.odomFrame)) {
        debugPrint('  - Missing odom frame: ${settings.odomFrame}');
      }
      if (!availableFrames.contains(settings.baseLinkFrame)) {
        debugPrint('  - Missing base_link frame: ${settings.baseLinkFrame}');
      }

      // Check for similar frame names
      final similarFrames = availableFrames
          .where((frame) =>
              frame.toLowerCase().contains('base') ||
              frame.toLowerCase().contains('odom') ||
              frame.toLowerCase().contains('map'))
          .toList();
      if (similarFrames.isNotEmpty) {
        debugPrint('Similar frames found: ${similarFrames.join(', ')}');
      }

      debugPrint('=============================');

      // No transform available
      _isTfAvailable = false;
      _lastError =
          'Transform not available: ${settings.mapFrame} → ${settings.baseLinkFrame}';
    } catch (e) {
      _isTfAvailable = false;
      _lastError = 'Error updating robot position: $e';
      debugPrint('TFService Error: $_lastError');
    }
  }

  geometry_msgs.TransformStamped? _getTransformChain(
    String targetFrame,
    String intermediateFrame,
    String sourceFrame,
  ) {
    // Get target → intermediate transform
    final targetToIntermediate =
        _getDirectTransform(targetFrame, intermediateFrame);
    if (targetToIntermediate == null) return null;

    // Get intermediate → source transform
    final intermediateToSource =
        _getDirectTransform(intermediateFrame, sourceFrame);
    if (intermediateToSource == null) return null;

    // Compose transforms
    return _composeTransforms(targetToIntermediate, intermediateToSource);
  }

  geometry_msgs.TransformStamped? _getDirectTransform(
      String targetFrame, String sourceFrame) {
    if (_tfBuffer.containsKey(targetFrame) &&
        _tfBuffer[targetFrame]!.containsKey(sourceFrame)) {
      return _tfBuffer[targetFrame]![sourceFrame];
    }
    return null;
  }

  geometry_msgs.TransformStamped _composeTransforms(
    geometry_msgs.TransformStamped parentTransform,
    geometry_msgs.TransformStamped childTransform,
  ) {
    // Proper transform composition: T_composed = T_parent * T_child
    final parentTrans = parentTransform.transform.translation;
    final parentRot = parentTransform.transform.rotation;
    final childTrans = childTransform.transform.translation;
    final childRot = childTransform.transform.rotation;

    // Compose rotation: q_composed = q_parent * q_child
    final composedRot = _multiplyQuaternions(parentRot, childRot);

    // Compose translation: t_composed = t_parent + R_parent * t_child
    final rotatedChildTrans = _rotateVector(childTrans, parentRot);
    final composedTrans = geometry_msgs.Vector3(
      x: parentTrans.x + rotatedChildTrans.x,
      y: parentTrans.y + rotatedChildTrans.y,
      z: parentTrans.z + rotatedChildTrans.z,
    );

    return geometry_msgs.TransformStamped(
      header: parentTransform.header,
      child_frame_id: childTransform.child_frame_id,
      transform: geometry_msgs.Transform(
        translation: composedTrans,
        rotation: composedRot,
      ),
    );
  }

  // Multiply two quaternions: q1 * q2
  geometry_msgs.Quaternion _multiplyQuaternions(
    geometry_msgs.Quaternion q1,
    geometry_msgs.Quaternion q2,
  ) {
    return geometry_msgs.Quaternion(
      x: q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
      y: q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
      z: q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w,
      w: q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z,
    );
  }

  // Rotate a vector by a quaternion: R * v
  geometry_msgs.Vector3 _rotateVector(
    geometry_msgs.Vector3 vector,
    geometry_msgs.Quaternion quaternion,
  ) {
    // Convert quaternion to rotation matrix (simplified for 2D)
    final qx = quaternion.x;
    final qy = quaternion.y;
    final qz = quaternion.z;
    final qw = quaternion.w;

    // For 2D rotation (assuming z-axis rotation only)
    final cosTheta = 1 - 2 * (qy * qy + qz * qz);
    final sinTheta = 2 * (qw * qz + qx * qy);

    return geometry_msgs.Vector3(
      x: vector.x * cosTheta - vector.y * sinTheta,
      y: vector.x * sinTheta + vector.y * cosTheta,
      z: vector.z, // Keep z unchanged for 2D
    );
  }

  // Check if position has changed significantly (threshold: 1cm for position, 0.01 rad for orientation)
  bool _hasPositionChanged(
      Map<String, dynamic> lastPos, Map<String, dynamic> newPos) {
    const double positionThreshold = 0.01; // 1cm
    const double orientationThreshold = 0.01; // ~0.57 degrees

    final lastX = lastPos['x'] as double;
    final lastY = lastPos['y'] as double;
    final newX = newPos['x'] as double;
    final newY = newPos['y'] as double;

    // Check position change
    final positionChange = math.sqrt(
        (newX - lastX) * (newX - lastX) + (newY - lastY) * (newY - lastY));
    if (positionChange > positionThreshold) {
      return true;
    }

    // Check orientation change (simplified - compare quaternion components)
    final lastQ = lastPos['q'] as geometry_msgs.Quaternion;
    final newQ = newPos['q'] as geometry_msgs.Quaternion;

    final orientationChange = math.sqrt(
        (newQ.x - lastQ.x) * (newQ.x - lastQ.x) +
            (newQ.y - lastQ.y) * (newQ.y - lastQ.y) +
            (newQ.z - lastQ.z) * (newQ.z - lastQ.z) +
            (newQ.w - lastQ.w) * (newQ.w - lastQ.w));

    return orientationChange > orientationThreshold;
  }

  void clearCache() {
    debugPrint('TFService: Clearing TF cache and resetting all state');

    // Cancel position update timer
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = null;

    // Shutdown existing TF subscriber
    _tfSubscriber?.shutdown();
    _tfSubscriber = null;

    // Clear all TF data
    _tfBuffer.clear();
    _lastPosition = null;

    // Reset all state flags
    _isInitialized = false;
    _isTfAvailable = false;
    _lastError = null;

    debugPrint('TFService: All state cleared - ready for new robot connection');
  }

  // Comprehensive reset for robot switching - clears everything
  static void resetAllServices() {
    debugPrint('=== RESETTING ALL SERVICES FOR ROBOT SWITCH ===');

    // Reset TF Service
    TFService.instance.clearCache();

    // Clear map cache in OccupancyGridViewer
    try {
      OccupancyGridViewer.clearMapCache();
      debugPrint('Map cache cleared successfully');
    } catch (e) {
      debugPrint('Error clearing map cache: $e');
    }

    debugPrint('=== ALL SERVICES RESET COMPLETE ===');
  }

  void shutdown() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = null;
    _tfSubscriber?.shutdown();
    _tfSubscriber = null;
    _robotPositionController.close();
    _tfBuffer.clear();
    _isInitialized = false;
    _isTfAvailable = false;
    _lastError = null;
    _lastPosition = null;
  }
}
