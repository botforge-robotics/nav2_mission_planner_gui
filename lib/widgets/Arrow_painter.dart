import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class ArrowPainter extends CustomPainter {
  final Color color;
  final String? number;
  final double angle;

  ArrowPainter({required this.color, this.number, required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05;

    final double width = size.width;
    final double height = size.height;
    final double centerX = width / 2;
    final double shaftLength = height * 0.3;
    final double arrowHeadSize = width * 0.15;

    // Draw pivot dot at bottom center
    final Paint dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final double dotRadius = size.width * 0.2;
    canvas.drawCircle(
        Offset(centerX, height), // Bottom center position
        dotRadius, // Dot radius
        dotPaint);

    // Draw shaft
    canvas.drawLine(
        Offset(centerX, height), Offset(centerX, height - shaftLength), paint);

    // Draw arrowhead
    final ui.Path arrowHead = ui.Path();
    final Offset tipPoint =
        Offset(centerX, height - shaftLength - arrowHeadSize);
    final Offset leftCorner =
        Offset(centerX - arrowHeadSize, height - shaftLength);
    final Offset rightCorner =
        Offset(centerX + arrowHeadSize, height - shaftLength);

    arrowHead.moveTo(tipPoint.dx, tipPoint.dy);
    arrowHead.lineTo(leftCorner.dx, leftCorner.dy);
    arrowHead.lineTo(rightCorner.dx, rightCorner.dy);
    arrowHead.lineTo(tipPoint.dx, tipPoint.dy);

    final Paint headPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(arrowHead, headPaint);

    // Draw number inside circle if provided
    if (number != null) {
      // Save the current canvas state
      canvas.save();

      // Translate to the center of the circle
      canvas.translate(centerX, height);

      // Rotate by negative angle to counter-rotate the text
      canvas.rotate(-angle);

      final textStyle = TextStyle(
        color: Colors.white,
        fontSize: dotRadius * 1.2,
        fontWeight: FontWeight.bold,
      );
      final textSpan = TextSpan(
        text: number,
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(
        minWidth: 0,
        maxWidth: dotRadius * 2,
      );

      // Draw text centered at origin (after translation)
      textPainter.paint(
        canvas,
        Offset(
          -textPainter.width / 2,
          -textPainter.height / 2,
        ),
      );

      // Restore the canvas state
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ArrowPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.number != number ||
        oldDelegate.angle != angle;
  }
}
