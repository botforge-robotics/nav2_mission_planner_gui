import 'package:flutter/material.dart';
import '../../services/alert_log_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Alerts & Log screen — the redesign's "12. Alerts & Fault Log" section,
/// deliberately scoped to what [AlertLogService] can actually observe:
/// connection drops/restores, mission failures, and dock/undock faults.
///
/// What the reference design shows that this screen does NOT (and can't,
/// without new ROS wiring) — flagged rather than faked, same convention as
/// Dashboard/RobotStatus/Dock:
///  - No hardware fault/diagnostics feed — no such topic is subscribed
///    anywhere in the app.
///  - No obstacle-detected events — no obstacle signal exists.
///  - No E-STOP events — no E-STOP topic/service exists.
/// All three need real topic names from the robot stack before they can be
/// added here; the event model (`AlertEvent`/`AlertSeverity`) is already
/// shaped to take them once that's known.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme,
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        return Container(
          color: AppColors.lightBackground,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Alerts & Log', style: theme.textTheme.headlineSmall),
                      const Spacer(),
                      AnimatedBuilder(
                        animation: AlertLogService.instance,
                        builder: (context, _) {
                          final hasEvents =
                              AlertLogService.instance.events.isNotEmpty;
                          return TextButton.icon(
                            onPressed: hasEvents
                                ? () => AlertLogService.instance.clear()
                                : null,
                            icon: const Icon(Icons.clear_all, size: 18),
                            label: const Text('Clear'),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Connection, mission, and dock events observed this session. '
                    'Hardware fault, obstacle, and E-STOP alerts aren\'t shown — '
                    'no signal for those exists in the app yet.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: AlertLogService.instance,
                      builder: (context, _) {
                        final events = AlertLogService.instance.events;
                        if (events.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.notifications_none,
                                    size: 40,
                                    color: theme.colorScheme.outline),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'No alerts yet',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: events.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) =>
                              _AlertTile(event: events[index]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final AlertEvent event;

  const _AlertTile({required this.event});

  Color _color(BuildContext context) {
    final theme = Theme.of(context);
    switch (event.severity) {
      case AlertSeverity.error:
        return theme.colorScheme.error;
      case AlertSeverity.warning:
        return const Color(0xFFE8A93A); // matches AppColors.stateLocalizing
      case AlertSeverity.info:
        return theme.colorScheme.primary;
    }
  }

  String _timeLabel() {
    final t = event.time;
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _color(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(event.icon, color: color, size: 20),
        ),
        title: Text(event.title),
        subtitle: event.detail != null ? Text(event.detail!) : null,
        trailing: Text(
          _timeLabel(),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
