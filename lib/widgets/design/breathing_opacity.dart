import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Wraps [child] in a slow opacity breathe while [active] is true — used for
/// small icons that need to say "this is ongoing" without a full
/// [StatusPulseDot] ring (a charging bolt, a recording indicator). Sits
/// perfectly still when [active] is false, same "motion is a state signal"
/// rule as the rest of the design system.
class BreathingOpacity extends StatefulWidget {
  const BreathingOpacity(
      {super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<BreathingOpacity> createState() => _BreathingOpacityState();
}

class _BreathingOpacityState extends State<BreathingOpacity>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: AppMotion.pulseCycle);
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant BreathingOpacity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = widget.active
            ? AppMotion.breathe.transform(_controller.value)
            : 0.0;
        return Opacity(opacity: 1 - t * 0.45, child: child);
      },
      child: widget.child,
    );
  }
}
