import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// The app's one animated "is this robot doing something right now"
/// indicator — a solid dot with a soft breathing ring around it while
/// [live] is true, a plain steady dot when it isn't. Used anywhere a robot
/// state is shown as a colored dot (Dashboard's robot card, Robot Status,
/// Alerts' connection indicator) so the same motion means the same thing
/// everywhere: motion = "live and active", stillness = "settled".
///
/// The pulse never runs when [live] is false — an idle/offline robot gets a
/// still dot, not a pulse that quietly lied about activity. That's the
/// "purposeful, not decorative" rule this whole design pass is built around.
class StatusPulseDot extends StatefulWidget {
  const StatusPulseDot(
      {super.key, required this.color, this.live = false, this.size = 8});

  final Color color;
  final bool live;
  final double size;

  @override
  State<StatusPulseDot> createState() => _StatusPulseDotState();
}

class _StatusPulseDotState extends State<StatusPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: AppMotion.pulseCycle);
    if (widget.live) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant StatusPulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.live && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.live && _controller.isAnimating) {
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
    final ringExtent = widget.size * 1.8;
    return SizedBox(
      width: ringExtent,
      height: ringExtent,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = widget.live
              ? AppMotion.breathe.transform(_controller.value)
              : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.live)
                Opacity(
                  opacity: (1 - t) * 0.35,
                  child: Container(
                    width: widget.size + (ringExtent - widget.size) * t,
                    height: widget.size + (ringExtent - widget.size) * t,
                    decoration: BoxDecoration(
                        color: widget.color, shape: BoxShape.circle),
                  ),
                ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }
}
