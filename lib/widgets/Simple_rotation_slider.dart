import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;

class SimpleRotationSliderPainter extends CustomPainter {
  final double angle;
  final Color color;

  SimpleRotationSliderPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;

    // Draw directional indicators around track
    _drawDirectionalMarkers(canvas, center, radius);

    // Draw track with arrow pattern
    final trackPaint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, trackPaint);

    // Draw filled angle arc from 0 degrees (right/east)
    final arcPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    // Use counterclockwise direction consistently
    final arcPath = ui.Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        0, // Start at 0 degrees (x-axis right)
        angle, // Positive angle for counterclockwise direction
        false,
      )
      ..lineTo(center.dx, center.dy);

    canvas.drawPath(arcPath, arcPaint);

    // Calculate handle position using counterclockwise convention
    final handleX = center.dx + radius * math.cos(angle);
    final handleY = center.dy + radius * math.sin(angle);

    // Draw arrow-shaped handle pointing outward
    final handlePaint = Paint()..color = Colors.greenAccent;

    // Pass the positive angle for counterclockwise direction
    _drawDirectionalHandle(
        canvas, Offset(handleX, handleY), angle, handlePaint, radius);

    // Draw connecting line with gradient
    final linePaint = Paint()
      ..shader = ui.Gradient.linear(
        center,
        Offset(handleX, handleY),
        [Colors.white30, Colors.greenAccent],
      )
      ..strokeWidth = 2;
    canvas.drawLine(center, Offset(handleX, handleY), linePaint);

    // Add angle text
    _drawAngleText(canvas, center, angle);
  }

  void _drawDirectionalMarkers(Canvas canvas, Offset center, double radius) {
    final markerPaint = Paint()
      ..color = Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw tick marks
    for (int i = 0; i < 12; i++) {
      final tickAngle = i * math.pi / 6;
      final isMainDirection = i % 3 == 0;
      final tickLength = isMainDirection ? 8.0 : 4.0;

      final outerX = center.dx + (radius + 2) * math.cos(tickAngle);
      final outerY = center.dy + (radius + 2) * math.sin(tickAngle);
      final innerX = center.dx + (radius - tickLength) * math.cos(tickAngle);
      final innerY = center.dy + (radius - tickLength) * math.sin(tickAngle);

      canvas.drawLine(
          Offset(innerX, innerY), Offset(outerX, outerY), markerPaint);
    }
  }

  void _drawDirectionalHandle(Canvas canvas, Offset position, double angle,
      Paint paint, double radius) {
    // Draw a solid dot as the handle
    final dotPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;

    // Draw larger shadow dot
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawCircle(position, 10, shadowPaint); // Shadow

    // Draw rim around dot
    final rimPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(position, 8, dotPaint); // Main dot
    canvas.drawCircle(position, 8, rimPaint); // White outline
  }

  void _drawAngleText(Canvas canvas, Offset center, double angle) {
    // Convert to degrees (0-360) in counterclockwise direction
    int angleInDegrees = ((angle * 180 / math.pi) % 360).toInt();

    // Handle negative angles (make them positive 0-360)
    if (angleInDegrees < 0) {
      angleInDegrees += 360;
    }

    final textSpan = TextSpan(
      text: '$angleInDegrees°',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant SimpleRotationSliderPainter oldDelegate) {
    return oldDelegate.angle != angle || oldDelegate.color != color;
  }
}
