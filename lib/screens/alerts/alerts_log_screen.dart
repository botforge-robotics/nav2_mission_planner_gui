import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/alerts_controller.dart';
import '../../services/sdk_events_service.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/fade_in.dart';
import '../../widgets/design/status_pulse.dart';

enum AlertSeverityFilter {
  all,
  critical,
  warning,
  info,
}

/// Reference §12 (Alerts & Fault Log). High-density industrial cockpit
/// event stream with severity filtering, tactical hazard cards, and
/// detailed telemetry event inspection.
class AlertsLogScreen extends StatefulWidget {
  const AlertsLogScreen({super.key});

  @override
  State<AlertsLogScreen> createState() => _AlertsLogScreenState();
}

class _AlertsLogScreenState extends State<AlertsLogScreen> {
  AlertSeverityFilter _selectedFilter = AlertSeverityFilter.all;

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

  void _clearLogs() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: AppColors.warning),
            SizedBox(width: AppSpacing.sm),
            Text('Clear Event Log?'),
          ],
        ),
        content: const Text(
          'This clears the local session alert history. New live events will continue to stream from the robot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () {
              Navigator.pop(ctx);
              AlertsController.instance.clear();
            },
            child: const Text('Clear Log'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final robotIp = context.watch<ConnectionProvider>().robot?.ip;
    if (robotIp != null) AlertsController.instance.ensureStarted(robotIp);
    final connected = AlertsController.instance.isConnected;
    final events = AlertsController.instance.events;

    final activeAlerts = events
        .where((e) => e.severity != SdkEventSeverity.info)
        .take(15)
        .toList();

    final filteredEvents = switch (_selectedFilter) {
      AlertSeverityFilter.all => events,
      AlertSeverityFilter.critical =>
        events.where((e) => e.severity == SdkEventSeverity.critical).toList(),
      AlertSeverityFilter.warning =>
        events.where((e) => e.severity == SdkEventSeverity.warning).toList(),
      AlertSeverityFilter.info =>
        events.where((e) => e.severity == SdkEventSeverity.info).toList(),
    };

    final criticalCount =
        events.where((e) => e.severity == SdkEventSeverity.critical).length;
    final warningCount =
        events.where((e) => e.severity == SdkEventSeverity.warning).length;
    final infoCount =
        events.where((e) => e.severity == SdkEventSeverity.info).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts & Fault Log'),
        actions: [
          if (events.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear session log',
              onPressed: _clearLogs,
            ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md, left: AppSpacing.xs),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (connected ? AppColors.success : AppColors.of(context).textSecondary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (connected ? AppColors.success : AppColors.of(context).border)
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusPulseDot(
                      color: connected ? AppColors.success : AppColors.textTertiary,
                      live: connected,
                      size: 8,
                    ),
                    const SizedBox(width: 6),
                    AnimatedSwitcher(
                      duration: AppMotion.resolveDuration(context, AppMotion.fast),
                      child: Text(
                        connected ? 'LIVE WS' : 'RECONNECTING',
                        key: ValueKey(connected),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: connected ? AppColors.success : AppColors.of(context).textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: robotIp == null
            ? const Center(child: Text('Not connected.'))
            : CenteredFormColumn(
                maxWidth: 720,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (!connected)
                      Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.wifi_tethering_error_rounded, color: AppColors.warning, size: 20),
                            SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Connecting to robot WebSocket event bus (navpro-sdk.service)…',
                                style: TextStyle(fontSize: 13, color: AppColors.warning),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Active Alerts Section
                    Row(
                      children: [
                        Text(
                          'Active Safety Interlocks',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: activeAlerts.isEmpty
                                ? AppColors.success.withValues(alpha: 0.15)
                                : AppColors.danger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${activeAlerts.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: activeAlerts.isEmpty ? AppColors.success : AppColors.danger,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    if (activeAlerts.isEmpty)
                      FadeSlideIn(
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                            side: BorderSide(
                              color: AppColors.success.withValues(alpha: 0.3),
                            ),
                          ),
                          color: AppColors.success.withValues(alpha: 0.05),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.verified_user_rounded,
                                    color: AppColors.success,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'All Systems Nominal',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: AppColors.success,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'No active collisions, emergency stops, or safety faults detected.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.of(context).textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      for (final e in activeAlerts)
                        FadeSlideIn(
                          offset: 8,
                          child: _AlertCard(event: e),
                        ),

                    const SizedBox(height: AppSpacing.xl),

                    // Filter Chips Bar
                    Row(
                      children: [
                        Text(
                          'Telemetry Event Log',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          '${events.length} total',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.of(context).textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _filterChip(
                            label: 'All (${events.length})',
                            filter: AlertSeverityFilter.all,
                            color: AppColors.of(context).primary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _filterChip(
                            label: 'Critical ($criticalCount)',
                            filter: AlertSeverityFilter.critical,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _filterChip(
                            label: 'Warnings ($warningCount)',
                            filter: AlertSeverityFilter.warning,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _filterChip(
                            label: 'Info ($infoCount)',
                            filter: AlertSeverityFilter.info,
                            color: AppColors.of(context).primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    if (filteredEvents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.inbox_rounded,
                                size: 40,
                                color: AppColors.of(context).textSecondary.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                events.isEmpty
                                    ? 'No telemetry events recorded this session.'
                                    : 'No events match the selected severity filter.',
                                style: TextStyle(
                                  color: AppColors.of(context).textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      for (final e in filteredEvents)
                        FadeSlideIn(
                          offset: 6,
                          child: _EventTile(event: e),
                        ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required AlertSeverityFilter filter,
    required Color color,
  }) {
    final isSelected = _selectedFilter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = filter),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
      ),
      selectedColor: color,
      backgroundColor: AppColors.of(context).surfaceSunken,
      side: BorderSide(
        color: isSelected ? color : AppColors.of(context).border,
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
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEventDetails(context, event),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.12),
                color.withValues(alpha: 0.02),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  critical ? Icons.error_rounded : Icons.warning_amber_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            critical ? 'CRITICAL FAULT' : 'HAZARD WARNING',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _timeAgo(event.receivedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.of(context).textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _titleCase(event.name),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
      SdkEventSeverity.info => AppColors.of(context).primary,
    };
    final tagLabel = switch (event.severity) {
      SdkEventSeverity.critical => 'CRIT',
      SdkEventSeverity.warning => 'WARN',
      SdkEventSeverity.info => 'INFO',
    };

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.of(context).border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showEventDetails(context, event),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tagLabel,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _titleCase(event.name),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _timeAgo(event.receivedAt),
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.of(context).textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showEventDetails(BuildContext context, SdkEvent event) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  event.severity == SdkEventSeverity.critical
                      ? Icons.error_rounded
                      : (event.severity == SdkEventSeverity.warning
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline_rounded),
                  color: event.severity == SdkEventSeverity.critical
                      ? AppColors.danger
                      : (event.severity == SdkEventSeverity.warning
                          ? AppColors.warning
                          : AppColors.of(context).primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _titleCase(event.name),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            _detailRow(context, 'Raw Event Identifier', event.name),
            _detailRow(context, 'Severity Level', event.severity.name.toUpperCase()),
            _detailRow(context, 'Timestamp', event.receivedAt.toIso8601String()),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: event.name));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Event name copied to clipboard')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy Event Key'),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _detailRow(BuildContext context, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.of(context).textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    ),
  );
}

String _titleCase(String eventName) => eventName.replaceAll('.', ' · ');

String _timeAgo(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  return '${diff.inHours}h ago';
}
