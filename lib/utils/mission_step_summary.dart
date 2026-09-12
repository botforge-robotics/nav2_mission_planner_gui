/// Human-readable summary + icon (+ tint) for a mission step, shared between
/// the editor (while building a mission) and the detail screen (while
/// showing its waypoint list) so both describe the same real step shapes the
/// server's mission runner actually understands — `navigate` (by
/// saved-location name or raw x/y), `wait`, `dock`, `undock`, and the two
/// generic escape hatches `call_service`/`call_action` (see
/// handlers/missions.py's own VALID_STEP_TYPES on the robot).
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

String missionStepSummary(Map<String, dynamic> step) {
  switch (step['type']) {
    case 'navigate':
      final target = step['target'];
      if (target is String) return 'Go to "$target"';
      final x = (step['x'] as num?)?.toStringAsFixed(2);
      final y = (step['y'] as num?)?.toStringAsFixed(2);
      return 'Go to ($x, $y)';
    case 'wait':
      final duration = step['duration'];
      return 'Wait ${duration}s';
    case 'dock':
      return step['navigate_to_staging'] == false ? 'Dock (from here)' : 'Dock';
    case 'undock':
      return 'Undock';
    case 'call_service':
      return 'Call "${step['service'] ?? ''}"';
    case 'call_action':
      return 'Call action "${step['action'] ?? ''}"';
    case 'call_api':
      final method = (step['method'] as String? ?? 'POST').toUpperCase();
      final url = step['url'] as String? ?? '';
      try {
        final uri = Uri.parse(url);
        final path = uri.path.isNotEmpty ? uri.path : uri.host;
        return 'HTTP $method $path';
      } catch (_) {
        return 'HTTP $method';
      }
    default:
      return step['type']?.toString() ?? 'Step';
  }
}

IconData missionStepIcon(Map<String, dynamic> step) => switch (step['type']) {
      'navigate' => Icons.place_rounded,
      'wait' => Icons.hourglass_bottom_rounded,
      'dock' => Icons.ev_station_rounded,
      'undock' => Icons.logout_rounded,
      'call_service' => Icons.settings_ethernet_rounded,
      'call_action' => Icons.bolt_rounded,
      'call_api' => Icons.http_rounded,
      _ => Icons.circle_rounded,
    };

/// Per-type tint for the step's icon chip — reused by both the editor's step
/// list and the list screen's per-mission step-preview row so a step type
/// reads as the same color everywhere.
Color missionStepColor(Map<String, dynamic> step) => switch (step['type']) {
      'navigate' => AppColors.primary,
      'wait' => AppColors.stateLocalizing,
      'dock' => AppColors.stateDocking,
      'undock' => AppColors.textSecondary,
      'call_service' || 'call_action' || 'call_api' => AppColors.accent,
      _ => AppColors.textSecondary,
    };

/// A step type's icon in a small tinted circle — the one visual language for
/// "what kind of step is this" shared across the editor's step list, the
/// list screen's per-mission preview row, and anywhere else a step needs a
/// compact glyph.
class StepIconChip extends StatelessWidget {
  const StepIconChip({super.key, required this.step, this.radius = 18});

  final Map<String, dynamic> step;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = missionStepColor(step);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(missionStepIcon(step), color: color, size: radius),
    );
  }
}
