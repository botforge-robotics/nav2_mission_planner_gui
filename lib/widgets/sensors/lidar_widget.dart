import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:sensor_msgs/msg.dart';
import '../../providers/connection_provider.dart';

class LidarWidget extends StatefulWidget {
  final String scanTopic;
  final double robotX;
  final double robotY;
  final double robotTheta;
  final double scale;
  final double resolution;
  final Color modeColor;

  const LidarWidget({
    super.key,
    required this.scanTopic,
    required this.robotX,
    required this.robotY,
    required this.robotTheta,
    required this.scale,
    required this.resolution,
    required this.modeColor,
  });

  @override
  State<LidarWidget> createState() => _LidarWidgetState();
}

class _LidarWidgetState extends State<LidarWidget> {
  Subscriber<LaserScan>? _scanSubscriber;
  List<Offset> _scanPoints = [];

  @override
  void initState() {
    super.initState();
    _subscribeToLidar();
  }

  @override
  void dispose() {
    _scanSubscriber?.shutdown();
    super.dispose();
  }

  @override
  void didUpdateWidget(LidarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scanTopic != widget.scanTopic) {
      _scanSubscriber?.shutdown();
      _subscribeToLidar();
    }
  }

  void _subscribeToLidar() {
    final connection = Provider.of<ConnectionProvider>(context, listen: false);
    if (connection.ros2Client == null || widget.scanTopic.isEmpty) return;

    try {
      _scanSubscriber = Subscriber<LaserScan>(
        name: widget.scanTopic,
        type: LaserScan().fullType,
        ros2: connection.ros2Client!,
        callback: _processScan,
        prototype: LaserScan(),
      );
    } catch (e) {
      debugPrint('Error subscribing to lidar: $e');
    }
  }

  void _processScan(LaserScan scan) {
    try {
      if (scan.ranges.isEmpty || widget.resolution <= 0) {
        setState(() {
          _scanPoints = [];
        });
        return;
      }

      final points = <Offset>[];
      final angleIncrement = scan.angle_increment;
      double currentAngle = scan.angle_min;

      for (int i = 0; i < scan.ranges.length; i++) {
        final element = scan.ranges[i];
        final double range = element.toDouble();
        if (!range.isFinite ||
            range < scan.range_min ||
            range > scan.range_max) {
          currentAngle += angleIncrement;
          continue;
        }

        // Calculate point in robot frame
        final worldAngle = currentAngle + widget.robotTheta;
        final x = range * math.cos(worldAngle);
        final y = range * math.sin(worldAngle);

        // Convert to map frame
        final mapX = widget.robotX + (x / widget.resolution);
        final mapY = widget.robotY - (y / widget.resolution);

        points.add(Offset(mapX, mapY));
        currentAngle += angleIncrement;
      }

      if (mounted) {
        setState(() {
          _scanPoints = points;
        });
      }
    } catch (e) {
      debugPrint('Lidar error: $e');
      if (mounted) {
        setState(() {
          _scanPoints = [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LidarPainter(
        points: _scanPoints,
        scale: widget.scale,
        color: widget.modeColor,
      ),
      size: Size.zero,
      willChange: true,
    );
  }
}

class _LidarPainter extends CustomPainter {
  final List<Offset> points;
  final double scale;
  final Color color;

  _LidarPainter({
    required this.points,
    required this.scale,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Draw all points scaled according to current zoom
    for (final point in points) {
      final scaledPoint = Offset(
        point.dx * scale,
        point.dy * scale,
      );
      canvas.drawCircle(scaledPoint, 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(_LidarPainter old) =>
      old.points != points || old.scale != scale || old.color != color;
}
