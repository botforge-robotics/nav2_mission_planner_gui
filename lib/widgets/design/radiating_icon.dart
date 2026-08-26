import 'package:flutter/material.dart';

/// A static icon in a filled circle, with 2-3 rings expanding and fading
/// outward from it on a loop — the app's one visual for "reaching out over
/// the network" (Splash's silent-reconnect check, AppShell's connecting
/// gate). Rings are phase-offset so one is always mid-expansion: a
/// continuous, unhurried pulse rather than a single repeating burst.
/// Reused in both places rather than each screen inventing its own
/// "connecting" motion, so the same animation always means the same thing.
class RadiatingIcon extends StatefulWidget {
  const RadiatingIcon({
    super.key,
    this.icon,
    required this.iconBackground,
    required this.iconColor,
    this.ringColor,
    this.size = 120,
    this.coreSize = 64,
    this.child,
  }) : assert(icon != null || child != null,
            'RadiatingIcon needs either an icon or a child.');

  final IconData? icon;
  final Color iconBackground;
  final Color iconColor;
  final Color? ringColor;
  final double size;
  final double coreSize;

  /// Overrides the glyph with any widget (e.g. a real product photo) — the
  /// core circle and its radiating rings stay exactly the same either way,
  /// so it's still recognizably the same "reaching out" motion.
  final Widget? child;

  @override
  State<RadiatingIcon> createState() => _RadiatingIconState();
}

class _RadiatingIconState extends State<RadiatingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringColor = widget.ringColor ?? widget.iconBackground;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _RingsPainter(
            progress: _controller.value,
            color: ringColor,
            baseRadius: widget.coreSize / 2,
            maxRadius: widget.size / 2,
          ),
          child: Center(
            child: Container(
              width: widget.coreSize,
              height: widget.coreSize,
              decoration: BoxDecoration(
                  color: widget.iconBackground, shape: BoxShape.circle),
              child: widget.child ??
                  Icon(widget.icon,
                      color: widget.iconColor, size: widget.coreSize * 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({
    required this.progress,
    required this.color,
    required this.baseRadius,
    required this.maxRadius,
  });

  final double progress;
  final Color color;
  final double baseRadius;
  final double maxRadius;
  static const _ringCount = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < _ringCount; i++) {
      final phase = (progress + i / _ringCount) % 1.0;
      final radius = baseRadius + (maxRadius - baseRadius) * phase;
      final opacity = (1 - phase) * 0.35;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
