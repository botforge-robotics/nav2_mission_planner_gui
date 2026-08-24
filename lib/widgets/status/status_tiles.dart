import 'package:flutter/material.dart';
import '../../theme/app_spacing.dart';

/// Small colored dot + label pill — used for the robot-state indicator on
/// both Dashboard and Robot Status.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const StatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps [tiles] into a responsive grid — [columns] per row, matching the
/// screen's window-size class (see `WindowSizeClass`).
class StatTileGrid extends StatelessWidget {
  final List<Widget> tiles;
  final int columns;
  final double childAspectRatio;

  const StatTileGrid({
    super.key,
    required this.tiles,
    required this.columns,
    this.childAspectRatio = 1.6,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: childAspectRatio,
      children: tiles,
    );
  }
}

/// A single stat card: icon, value, label. Used across Dashboard and Robot
/// Status for battery/temperature/session/etc. readouts.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accentColor ?? theme.colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const Spacer(),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(color: color),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class BatteryTile extends StatelessWidget {
  final double? percent;

  const BatteryTile({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    final p = percent;
    final color = p == null
        ? null
        : (p <= 15 ? Colors.red : (p <= 30 ? Colors.orange : Colors.green));
    return StatTile(
      label: 'Battery',
      value: p == null ? '—' : '${p.round()}%',
      icon: p == null
          ? Icons.battery_unknown
          : (p <= 15 ? Icons.battery_alert : Icons.battery_full),
      accentColor: color,
    );
  }
}

class TemperatureTile extends StatelessWidget {
  final String label;
  final double? celsius;

  const TemperatureTile(
      {super.key, required this.label, required this.celsius});

  @override
  Widget build(BuildContext context) {
    return StatTile(
      label: label,
      value: celsius == null ? '—' : '${celsius!.round()}°C',
      icon: Icons.thermostat,
    );
  }
}
