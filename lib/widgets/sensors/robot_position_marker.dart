import 'package:flutter/material.dart';
import 'dart:math' as math;

class RobotPositionMarker extends StatefulWidget {
  final double x;
  final double y;
  final double theta;
  final Color color;
  final double size;

  const RobotPositionMarker({
    super.key,
    required this.x,
    required this.y,
    required this.theta,
    required this.color,
    this.size = 24.0,
  });

  @override
  State<RobotPositionMarker> createState() => _RobotPositionMarkerState();
}

class _RobotPositionMarkerState extends State<RobotPositionMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: widget.theta + math.pi / 2,
          child: Icon(
            Icons.navigation,
            color: widget.color.withOpacity(0.9 * _opacityAnimation.value),
            size: widget.size,
          ),
        );
      },
    );
  }
}
