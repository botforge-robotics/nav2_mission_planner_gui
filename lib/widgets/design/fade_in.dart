import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// A one-shot entrance: fades and settles upward into place. Used for a
/// screen's first content reveal (Dashboard's cards, a list's rows) —
/// [delay] lets a caller stagger a handful of these a beat apart so content
/// arrives as a considered sequence rather than all at once, without needing
/// a full AnimationController/stagger-schedule setup at the call site.
///
/// Runs once per mount, not on every rebuild — this is for "content just
/// arrived", not a decorative loop.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.medium,
    this.offset = 12,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _visible = true;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: widget.duration,
      curve: AppMotion.enter,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : Offset(0, widget.offset / 100),
        duration: widget.duration,
        curve: AppMotion.enter,
        child: widget.child,
      ),
    );
  }
}
