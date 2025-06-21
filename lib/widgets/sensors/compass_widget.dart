import 'package:flutter/material.dart';
import 'dart:math' as math;

class CompassWidget extends StatefulWidget {
  final double heading; // Heading in degrees (0-360)
  final double sizeFactor; // Size factor (0 to 1)
  final Duration animationDuration;

  const CompassWidget({
    super.key,
    required this.heading,
    required this.sizeFactor,
    this.animationDuration = const Duration(milliseconds: 500),
  });

  @override
  State<CompassWidget> createState() => _CompassWidgetState();
}

class _CompassWidgetState extends State<CompassWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late double _previousHeading;

  @override
  void initState() {
    super.initState();
    _previousHeading = widget.heading;
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _animation = Tween<double>(
      begin: _previousHeading,
      end: widget.heading,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(CompassWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heading != widget.heading) {
      _previousHeading = oldWidget.heading;
      _animation = Tween<double>(
        begin: _previousHeading,
        end: widget.heading,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate size based on screen height and size factor
    final screenHeight = MediaQuery.of(context).size.height;
    final size = screenHeight * widget.sizeFactor.clamp(0.1, 1.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating compass dial
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Transform.rotate(
                angle: -_animation.value * (math.pi / 180),
                child: CustomPaint(
                  size: Size(size, size),
                  painter: CompassDialPainter(sizeFactor: widget.sizeFactor),
                ),
              );
            },
          ),
          // Fixed navigation arrow
          Icon(
            Icons.navigation,
            color: Colors.red,
            size: size * 0.3, // Proportional arrow size
          ),
          // Heading indicator at bottom
          Positioned(
            bottom: size * 0.2,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: size * 0.067,
                vertical: size * 0.017,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(size * 0.033),
              ),
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Text(
                    '${_animation.value.round()}°',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.1,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CompassDialPainter extends CustomPainter {
  final double sizeFactor;

  CompassDialPainter({required this.sizeFactor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.0125; // Proportional stroke width

    // Draw the outer circle
    canvas.drawCircle(center, radius * 0.95, paint);

    // Draw the cardinal and intercardinal directions
    final directions = [
      {'text': 'N', 'angle': 0.0, 'isMain': true},
      {'text': 'NE', 'angle': 45.0, 'isMain': false},
      {'text': 'E', 'angle': 90.0, 'isMain': true},
      {'text': 'SE', 'angle': 135.0, 'isMain': false},
      {'text': 'S', 'angle': 180.0, 'isMain': true},
      {'text': 'SW', 'angle': 225.0, 'isMain': false},
      {'text': 'W', 'angle': 270.0, 'isMain': true},
      {'text': 'NW', 'angle': 315.0, 'isMain': false},
    ];

    for (var direction in directions) {
      final angle = direction['angle'] as double;
      final text = direction['text'] as String;
      final isMain = direction['isMain'] as bool;

      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: text == 'N' ? Colors.red : Colors.white,
            fontSize: isMain ? size.width * 0.12 : size.width * 0.1,
            fontWeight: isMain ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      textPainter.layout();

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle * math.pi / 180);

      // Draw the text
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -radius + (radius * 0.15)),
      );

      // Draw tick marks
      if (isMain) {
        canvas.drawLine(
          Offset(0, -radius * 0.95),
          Offset(0, -radius * 0.85),
          paint..strokeWidth = size.width * 0.015,
        );
      } else {
        canvas.drawLine(
          Offset(0, -radius * 0.95),
          Offset(0, -radius * 0.88),
          paint..strokeWidth = size.width * 0.01,
        );
      }

      canvas.restore();
    }

    // Draw minor tick marks every 15 degrees
    for (int i = 0; i < 360; i += 15) {
      if (i % 45 != 0) {
        final angle = i * math.pi / 180;
        final startPoint = Offset(
          center.dx + (radius * 0.95) * math.cos(angle),
          center.dy + (radius * 0.95) * math.sin(angle),
        );
        final endPoint = Offset(
          center.dx + (radius * 0.9) * math.cos(angle),
          center.dy + (radius * 0.9) * math.sin(angle),
        );
        canvas.drawLine(
          startPoint,
          endPoint,
          paint..strokeWidth = size.width * 0.008,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CompassDialPainter oldDelegate) =>
      oldDelegate.sizeFactor != sizeFactor;
}
