import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// A telemetry number that glides between values instead of jump-cutting —
/// battery %, speed, distances. `TweenAnimationBuilder` re-tweens from
/// whatever is currently on screen to the new [value] every time this
/// rebuilds with a different one, so a fast-changing value (speed while
/// driving) still reads smoothly rather than flickering. Falls back to
/// [placeholder] when there's no reading yet — never animates *into* a
/// fabricated number.
class AnimatedMetricText extends StatelessWidget {
  const AnimatedMetricText({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
    this.placeholder = '—',
    this.duration = AppMotion.medium,
  });

  final double? value;
  final String Function(double) formatter;
  final TextStyle? style;
  final String placeholder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null) {
      return Text(placeholder, style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: v, end: v),
      duration: duration,
      curve: AppMotion.settle,
      builder: (context, animated, _) =>
          Text(formatter(animated), style: style),
    );
  }
}

/// A thin progress bar (battery level, mission progress) whose fill glides
/// to a new value rather than snapping — same reasoning as
/// [AnimatedMetricText], applied to the bar every metric card already pairs
/// with a number.
class AnimatedMetricBar extends StatelessWidget {
  const AnimatedMetricBar({
    super.key,
    required this.value,
    this.color,
    this.backgroundColor,
    this.minHeight = 8,
    this.duration = AppMotion.medium,
  });

  /// 0..1, clamped.
  final double value;
  final Color? color;
  final Color? backgroundColor;
  final double minHeight;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: clamped, end: clamped),
      duration: duration,
      curve: AppMotion.settle,
      builder: (context, animated, _) => ClipRRect(
        borderRadius: BorderRadius.circular(minHeight),
        child: LinearProgressIndicator(
          value: animated,
          minHeight: minHeight,
          backgroundColor: backgroundColor,
          color: color,
        ),
      ),
    );
  }
}
