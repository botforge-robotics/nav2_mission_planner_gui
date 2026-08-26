import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A small translucent readout pinned over a live map view — position,
/// speed, and similar live values, so an operator can read them without
/// looking away from the map itself. Shared by Teleop and Create Map, both
/// of which overlay the same style of chip on their own live map view.
class HudChip extends StatelessWidget {
  const HudChip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
