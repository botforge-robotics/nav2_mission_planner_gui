import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/skeleton.dart';
import 'schedule_editor_screen.dart';

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Mission alarms — reached from Missions' own AppBar. Runs entirely on the
/// robot (server.py polls handlers/schedules.py every 20s), independent of
/// this app being open; this screen only edits the definitions and reflects
/// what's already there, same "server owns the truth" shape Missions itself
/// uses. Polled every 5s for the same reason missions_list_screen.dart is —
/// a schedule created on one device should show up here on another without
/// needing this screen to be reopened.
class SchedulesListScreen extends StatefulWidget {
  const SchedulesListScreen({super.key});

  @override
  State<SchedulesListScreen> createState() => _SchedulesListScreenState();
}

class _SchedulesListScreenState extends State<SchedulesListScreen> {
  List<Map<String, dynamic>>? _schedules;
  List<Map<String, dynamic>>? _missions;
  SdkApiException? _error;
  bool _requested = false;
  Timer? _poll;

  SdkApiService? _api;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) return;
    try {
      final results =
          await Future.wait([api.listSchedules(), api.listMissions()]);
      if (!mounted) return;
      setState(() {
        _schedules = results[0];
        _missions = results[1];
        _error = null;
      });
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _toggleEnabled(Map<String, dynamic> schedule, bool value) async {
    final api = _api;
    if (api == null) return;
    // Optimistic — flips immediately, corrected by the next poll if the
    // write actually failed.
    setState(() => schedule['enabled'] = value);
    try {
      await api.putSchedule(
        schedule['id'] as String,
        missionId: schedule['mission_id'] as String,
        name: schedule['name'] as String? ?? '',
        hour: schedule['hour'] as int,
        minute: schedule['minute'] as int,
        repeat: schedule['repeat'] as String,
        date: schedule['date'] as String?,
        weekdays: (schedule['weekdays'] as List? ?? const []).cast<int>(),
        enabled: value,
      );
    } on SdkApiException {
      _load();
    }
  }

  Future<void> _delete(String id) async {
    final api = _api;
    if (api == null) return;
    try {
      await api.deleteSchedule(id);
      _load();
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _runNow(String missionId) async {
    final api = _api;
    if (api == null) return;
    try {
      await api.startMission(missionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Started mission "${_missionName(missionId)}"')),
      );
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start mission: ${e.message}')),
      );
    }
  }

  String _missionName(String missionId) {
    final m = (_missions ?? const [])
        .cast<Map<String, dynamic>?>()
        .firstWhere((m) => m?['id'] == missionId, orElse: () => null);
    return m?['name'] as String? ?? missionId;
  }

  String _repeatLabel(Map<String, dynamic> schedule) {
    switch (schedule['repeat']) {
      case 'once':
        return 'Once · ${schedule['date']}';
      case 'weekly':
        final days = (schedule['weekdays'] as List? ?? const [])
            .cast<int>()
            .map((d) => _weekdayShort[d])
            .join(', ');
        return days.isEmpty ? 'Weekly' : 'Weekly: $days';
      default:
        return 'Daily';
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? schedule]) async {
    if (_missions == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScheduleEditorScreen(
          existing: schedule,
          missions: _missions!,
        ),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final robotIp = context.watch<ConnectionProvider>().robot?.ip;
    if (robotIp != null && (_api == null || _api!.robotIp != robotIp)) {
      _api = SdkApiService(robotIp);
    }
    if (!_requested && _api != null) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }

    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;
    final totalCount = _schedules?.length ?? 0;
    final activeCount =
        _schedules?.where((s) => s['enabled'] == true).length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mission Scheduler & Automation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Schedules',
            onPressed: _load,
          ),
          if (robotIp != null && _missions != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_alarm_rounded, size: 18),
                label: const Text('New Schedule'),
              ),
            ),
        ],
      ),
      floatingActionButton: (!isDesktop && robotIp != null && _missions != null)
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_alarm_rounded),
              label: const Text('New Schedule'),
            )
          : null,
      body: SafeArea(
        child: robotIp == null
            ? const Center(child: Text('Not connected.'))
            : _Body(
                isDesktop: isDesktop,
                schedules: _schedules,
                totalCount: totalCount,
                activeCount: activeCount,
                error: _error,
                onRetry: _load,
                missionName: _missionName,
                repeatLabel: _repeatLabel,
                onToggle: _toggleEnabled,
                onEdit: _openEditor,
                onDelete: _delete,
                onRunNow: _runNow,
                onAddNew: () => _openEditor(),
              ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.isDesktop,
    required this.schedules,
    required this.totalCount,
    required this.activeCount,
    required this.error,
    required this.onRetry,
    required this.missionName,
    required this.repeatLabel,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onRunNow,
    required this.onAddNew,
  });

  final bool isDesktop;
  final List<Map<String, dynamic>>? schedules;
  final int totalCount;
  final int activeCount;
  final SdkApiException? error;
  final VoidCallback onRetry;
  final String Function(String missionId) missionName;
  final String Function(Map<String, dynamic>) repeatLabel;
  final void Function(Map<String, dynamic>, bool) onToggle;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(String) onDelete;
  final void Function(String) onRunNow;
  final VoidCallback onAddNew;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      final unreachable = error!.isUnreachable;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              unreachable
                  ? Icons.cloud_off_rounded
                  : Icons.error_outline_rounded,
              size: 48,
              color: unreachable ? AppColors.textSecondary : AppColors.danger,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              unreachable
                  ? "Schedules need navpro-sdk.service running on the robot — it isn't reachable right now."
                  : error!.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (schedules == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: SkeletonList(),
      );
    }

    if (schedules!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.alarm_add_rounded,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'No automated schedules configured',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Schedule missions to run automatically at specific times or recurring weekdays.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAddNew,
              icon: const Icon(Icons.add_alarm_rounded, size: 18),
              label: const Text('Create First Schedule'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(isDesktop ? AppSpacing.xl : AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) ...[
            Row(
              children: [
                _StatCard(
                  title: 'Total Schedules',
                  value: '$totalCount',
                  icon: Icons.calendar_month_rounded,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                _StatCard(
                  title: 'Active / Running',
                  value: '$activeCount',
                  icon: Icons.check_circle_outline_rounded,
                  color: AppColors.success,
                ),
                const SizedBox(width: AppSpacing.md),
                _StatCard(
                  title: 'Scheduler Engine',
                  value: 'Autonomous (Robot)',
                  icon: Icons.memory_rounded,
                  color: AppColors.accent,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          Text(
            'Active Automation Timers ($totalCount)',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: isDesktop
                ? GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 480,
                      mainAxisExtent: 220,
                      crossAxisSpacing: AppSpacing.lg,
                      mainAxisSpacing: AppSpacing.lg,
                    ),
                    itemCount: schedules!.length,
                    itemBuilder: (context, i) => _ScheduleDesktopCard(
                      schedule: schedules![i],
                      missionName:
                          missionName(schedules![i]['mission_id'] as String),
                      repeatLabel: repeatLabel(schedules![i]),
                      onToggle: (v) => onToggle(schedules![i], v),
                      onEdit: () => onEdit(schedules![i]),
                      onDelete: () => onDelete(schedules![i]['id'] as String),
                      onRunNow: () =>
                          onRunNow(schedules![i]['mission_id'] as String),
                    ),
                  )
                : ListView.separated(
                    itemCount: schedules!.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final schedule = schedules![i];
                      final enabled = schedule['enabled'] == true;
                      final hour = (schedule['hour'] as num).toInt();
                      final minute = (schedule['minute'] as num).toInt();
                      final time =
                          TimeOfDay(hour: hour, minute: minute).format(context);
                      final mName =
                          missionName(schedule['mission_id'] as String);
                      return Card(
                        child: ListTile(
                          onTap: () => onEdit(schedule),
                          leading: CircleAvatar(
                            backgroundColor: (enabled
                                    ? AppColors.primary
                                    : AppColors.textTertiary)
                                .withValues(alpha: 0.12),
                            child: Icon(Icons.alarm_rounded,
                                color: enabled
                                    ? AppColors.primary
                                    : AppColors.textTertiary),
                          ),
                          title: Text(schedule['name'] as String? ?? mName),
                          subtitle: Text(
                              '$time · ${repeatLabel(schedule)} · $mName'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: enabled,
                                onChanged: (v) => onToggle(schedule, v),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () =>
                                    onDelete(schedule['id'] as String),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleDesktopCard extends StatelessWidget {
  const _ScheduleDesktopCard({
    required this.schedule,
    required this.missionName,
    required this.repeatLabel,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onRunNow,
  });

  final Map<String, dynamic> schedule;
  final String missionName;
  final String repeatLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRunNow;

  @override
  Widget build(BuildContext context) {
    final enabled = schedule['enabled'] == true;
    final hour = (schedule['hour'] as num).toInt();
    final minute = (schedule['minute'] as num).toInt();
    final timeStr =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    final name = (schedule['name'] as String?)?.isNotEmpty == true
        ? schedule['name'] as String
        : missionName;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: enabled
              ? AppColors.primary.withValues(alpha: 0.25)
              : AppColors.border,
          width: enabled ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (enabled ? AppColors.primary : AppColors.surfaceSunken)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 16,
                        color: enabled ? AppColors.primary : AppColors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: enabled
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: enabled
                        ? AppColors.success.withValues(alpha: 0.12)
                        : AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    enabled ? 'ACTIVE' : 'PAUSED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: enabled ? AppColors.success : AppColors.textTertiary,
                    ),
                  ),
                ),
                const Spacer(),
                Switch(
                  value: enabled,
                  onChanged: onToggle,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.route_rounded,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Mission: $missionName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(Icons.repeat_rounded,
                    size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  repeatLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: onRunNow,
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('Run Now', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: AppSpacing.xs),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.textTertiary),
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
