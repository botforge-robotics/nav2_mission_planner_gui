import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/alerts_controller.dart';
import '../../services/sdk_events_service.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/fade_in.dart';
import '../../widgets/design/status_pulse.dart';

/// Reference §12 (Alerts & Fault Log). navpromini_sdk keeps no event
/// history endpoint — `events` is a live WS stream only (handlers/events.py:
/// "an event is emitted once by definition, so there is nothing to
/// throttle" — and nothing to page back through either). This screen reads
/// AlertsController's shared, app-lifetime history instead of keeping its
/// own private one — a private list here used to mean an alert that arrived
/// while only Dashboard's alerts card was mounted (which stays alive
/// continuously in AppShell) was simply gone by the time this screen was
/// opened afterward, since its own connection only just started. Severity
/// is derived from each event name (see SdkEvent.severity) since the stream
/// itself carries none.
class AlertsLogScreen extends StatefulWidget {
  const AlertsLogScreen({super.key});

  @override
  State<AlertsLogScreen> createState() => _AlertsLogScreenState();
}

class _AlertsLogScreenState extends State<AlertsLogScreen> {
  @override
  void initState() {
    super.initState();
    AlertsController.instance.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AlertsController.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final robotIp = context.watch<ConnectionProvider>().robot?.ip;
    // Shared with Dashboard's alerts card (see AlertsController's own doc)
    // — whichever of the two builds first starts it, both read the same
    // history.
    if (robotIp != null) AlertsController.instance.ensureStarted(robotIp);
    final connected = AlertsController.instance.isConnected;
    final events = AlertsController.instance.events;

    final active = events
        .where((e) => e.severity != SdkEventSeverity.info)
        .take(10)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts & Fault Log'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusPulseDot(
                    color:
                        connected ? AppColors.success : AppColors.textTertiary,
                    live: connected,
                    size: 8,
                  ),
                  const SizedBox(width: 6),
                  AnimatedSwitcher(
                    duration: AppMotion.fast,
                    child: Text(
                      connected ? 'Live' : 'Reconnecting…',
                      key: ValueKey(connected),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: robotIp == null
            ? const Center(child: Text('Not connected.'))
            : CenteredFormColumn(
                maxWidth: 640,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (!connected)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Text(
                          "Live alerts need navpro-sdk.service — trying to reach it…",
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    Text('Active Alerts (${active.length})',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    if (active.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                size: 20, color: AppColors.success),
                            SizedBox(width: AppSpacing.sm),
                            Text('No active alerts',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      )
                    else
                      // Unkeyed on purpose: a new event prepended at index 0
                      // gets a genuinely new Element there (so its
                      // FadeSlideIn plays), while every existing tile just
                      // shifts position and keeps its already-settled state
                      // — only the arriving alert animates, not the whole
                      // list re-playing its entrance.
                      for (final e in active)
                        FadeSlideIn(offset: 8, child: _AlertCard(event: e)),
                    const SizedBox(height: AppSpacing.lg),
                    Text('All Events',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    if (events.isEmpty)
                      const Text('No events yet this session.',
                          style: TextStyle(color: AppColors.textSecondary))
                    else
                      for (final e in events)
                        FadeSlideIn(offset: 6, child: _EventTile(event: e)),
                  ],
                ),
              ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.event});

  final SdkEvent event;

  @override
  Widget build(BuildContext context) {
    final critical = event.severity == SdkEventSeverity.critical;
    final color = critical ? AppColors.danger : AppColors.warning;
    return Card(
      color: color.withValues(alpha: 0.06),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(
            critical ? Icons.error_rounded : Icons.warning_amber_rounded,
            color: color),
        title: Text(_titleCase(event.name)),
        subtitle: Text(_timeAgo(event.receivedAt)),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final SdkEvent event;

  @override
  Widget build(BuildContext context) {
    final icon = switch (event.severity) {
      SdkEventSeverity.critical => Icons.error_rounded,
      SdkEventSeverity.warning => Icons.warning_amber_rounded,
      SdkEventSeverity.info => Icons.info_outline_rounded,
    };
    final color = switch (event.severity) {
      SdkEventSeverity.critical => AppColors.danger,
      SdkEventSeverity.warning => AppColors.warning,
      SdkEventSeverity.info => AppColors.primary,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 18, color: color),
      title: Text(_titleCase(event.name),
          style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(_timeAgo(event.receivedAt),
          style: const TextStyle(fontSize: 12)),
      dense: true,
    );
  }
}

String _titleCase(String eventName) => eventName.replaceAll('.', ' · ');

String _timeAgo(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  return '${diff.inHours}h ago';
}
