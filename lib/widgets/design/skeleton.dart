import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';

/// A loading placeholder that breathes gently in place — deliberately *not*
/// a shimmer sweep. A moving highlight reads as flashy/gaming; a slow, even
/// opacity pulse reads as "the system is working on this" without asking
/// for attention, which fits an operator tool better.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: AppMotion.pulseCycle)
          ..repeat(reverse: true);
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
      builder: (context, _) {
        final t = AppMotion.breathe.transform(_controller.value);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(AppColors.surfaceSunken, AppColors.border, t),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// The common "list row while loading" shape — a circular avatar skeleton
/// plus two lines of text — used by Locations/Missions/etc. instead of a
/// bare centered spinner, so the loading state previews the layout that's
/// about to arrive.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        child: Row(
          children: [
            const SkeletonBox(width: 40, height: 40, radius: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 140, height: 15),
                  const SizedBox(height: 8),
                  SkeletonBox(width: 90, height: 12, radius: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short column of [SkeletonListTile]s, for list screens' first load.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [for (var i = 0; i < count; i++) const SkeletonListTile()]);
  }
}
