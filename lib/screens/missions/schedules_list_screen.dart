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

/// Autonomous Mission Scheduler & Recurrence Automation Center.
/// Displays programmed mission alarms, daily routines, and weekly recurring
/// AMR operations with digital HUD clock typography and active-day indicators.
class SchedulesListScreen extends StatefulWidget {
  const SchedulesListScreen({super.key});

  @override
  State<SchedulesListScreen> createState() => _SchedulesListScreenState();
}

class _SchedulesListScreenState extends State<SchedulesListScreen> {
  List<Map<String, dynamic>>? _schedules;
  List<Map<String, dynamic>>? _missions;
  String? _currentMap;
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
      final results = await Future.wait([
        api.listSchedules(),
        api.listMissions(),
        api.getCurrentMap(),
      ]);
      if (!mounted) return;
      setState(() {
        _schedules = results[0] as List<Map<String, dynamic>>?;
        _missions = results[1] as List<Map<String, dynamic>>?;
        _currentMap = results[2] as String?;
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
    final mapName = _missionMap(missionId);
    final colors = AppColors.of(context);

    if (mapName != null && _currentMap != null && mapName != _currentMap) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.warning),
              const SizedBox(width: 8),
              const Text('Map Mismatch Alert'),
            ],
          ),
          content: Text(
            'This mission was planned for map "$mapName", but the active map on the robot is "$_currentMap".\n\n'
            'Starting it now may cause navigation errors or emergency stops. Do you want to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors.warning),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Run Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    try {
      await api.startMission(missionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Started mission "${_missionName(missionId)}"'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start mission: ${e.message}'),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _missionName(String missionId) {
    final m = (_missions ?? const [])
        .cast<Map<String, dynamic>?>()
        .firstWhere((m) => m?['id'] == missionId, orElse: () => null);
    return m?['name'] as String? ?? missionId;
  }

  String? _missionMap(String missionId) {
    final m = (_missions ?? const [])
        .cast<Map<String, dynamic>?>()
        .firstWhere((m) => m?['id'] == missionId, orElse: () => null);
    return m?['map'] as String?;
  }

  String _repeatLabel(Map<String, dynamic> schedule) {
    switch (schedule['repeat']) {
      case 'once':
        return 'One-time · ${schedule['date']}';
      case 'weekly':
        final days = (schedule['weekdays'] as List? ?? const [])
            .cast<int>()
            .map((d) => _weekdayShort[d])
            .join(', ');
        return days.isEmpty ? 'Weekly' : 'Weekly: $days';
      case 'interval':
        final mins = (schedule['interval_minutes'] as num?)?.toInt() ?? (schedule['minute'] as num?)?.toInt() ?? 30;
        final h = mins ~/ 60;
        final m = mins % 60;
        final dStr = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
        return 'Every $dStr';
      default:
        return 'Daily Routine';
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
    final colors = AppColors.of(context);
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
      backgroundColor: colors.background,
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
                  backgroundColor: colors.primary,
                  foregroundColor: colors.textOnPrimary,
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
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 48, color: colors.textTertiary),
                    const SizedBox(height: 12),
                    Text('Robot Not Connected', style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Connect to your AMR to view and manage recurring schedules.', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                  ],
                ),
              )
            : _Body(
                isDesktop: isDesktop,
                schedules: _schedules,
                totalCount: totalCount,
                activeCount: activeCount,
                currentMap: _currentMap,
                error: _error,
                onRetry: _load,
                missionName: _missionName,
                missionMap: _missionMap,
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
    required this.currentMap,
    required this.error,
    required this.onRetry,
    required this.missionName,
    required this.missionMap,
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
  final String? currentMap;
  final SdkApiException? error;
  final VoidCallback onRetry;
  final String Function(String missionId) missionName;
  final String? Function(String missionId) missionMap;
  final String Function(Map<String, dynamic>) repeatLabel;
  final void Function(Map<String, dynamic>, bool) onToggle;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(String) onDelete;
  final void Function(String) onRunNow;
  final VoidCallback onAddNew;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    if (error != null) {
      final unreachable = error!.isUnreachable;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              unreachable ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
              size: 48,
              color: unreachable ? colors.textSecondary : colors.danger,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              unreachable
                  ? "Schedules need navpro-sdk.service running on the robot — it isn't reachable right now."
                  : error!.message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.alarm_add_rounded, size: 36, color: colors.primary),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No Automated Schedules Active',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  'Automate autonomous delivery, security patrols, or sanitization at specific times or recurring weekdays.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onAddNew,
                icon: const Icon(Icons.add_alarm_rounded, size: 18),
                label: const Text('Create First Schedule'),
              ),
            ],
          ),
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
                  title: 'Total Programs',
                  value: '$totalCount',
                  icon: Icons.calendar_month_rounded,
                  color: colors.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                _StatCard(
                  title: 'Active Alarms',
                  value: '$activeCount',
                  icon: Icons.check_circle_outline_rounded,
                  color: colors.stateIdle,
                ),
                const SizedBox(width: AppSpacing.md),
                _StatCard(
                  title: 'Execution Engine',
                  value: 'Autonomous AMR Daemon',
                  icon: Icons.memory_rounded,
                  color: const Color(0xFF00E5FF),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text(
            'Scheduled Timers ($totalCount)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: isDesktop
                ? GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 480,
                      mainAxisExtent: 238,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: AppSpacing.md,
                    ),
                    itemCount: schedules!.length,
                    itemBuilder: (context, i) => _ScheduleDesktopCard(
                      schedule: schedules![i],
                      missionName: missionName(schedules![i]['mission_id'] as String),
                      missionMap: missionMap(schedules![i]['mission_id'] as String),
                      currentMap: currentMap,
                      repeatLabel: repeatLabel(schedules![i]),
                      onToggle: (v) => onToggle(schedules![i], v),
                      onEdit: () => onEdit(schedules![i]),
                      onDelete: () => onDelete(schedules![i]['id'] as String),
                      onRunNow: () => onRunNow(schedules![i]['mission_id'] as String),
                    ),
                  )
                : ListView.separated(
                    itemCount: schedules!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final schedule = schedules![i];
                      final enabled = schedule['enabled'] == true;
                      final hour = (schedule['hour'] as num).toInt();
                      final minute = (schedule['minute'] as num).toInt();
                      final time = TimeOfDay(hour: hour, minute: minute).format(context);
                      final mName = missionName(schedule['mission_id'] as String);
                      final mMap = missionMap(schedule['mission_id'] as String);
                      final isMismatch = mMap != null && currentMap != null && mMap != currentMap;

                      return Card(
                        elevation: 0,
                        color: colors.surfaceElevated,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: enabled ? colors.primary.withValues(alpha: 0.3) : colors.border),
                        ),
                        child: ListTile(
                          onTap: () => onEdit(schedule),
                          leading: CircleAvatar(
                            backgroundColor: (enabled ? colors.primary : colors.surfaceSunken).withValues(alpha: 0.15),
                            child: Icon(
                              Icons.alarm_rounded,
                              color: enabled ? colors.primary : colors.textTertiary,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            schedule['name'] as String? ?? mName,
                            style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text('$time · ${repeatLabel(schedule)} · $mName',
                                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                              const SizedBox(height: 6),
                              _WeekdaysPillStrip(schedule: schedule, colors: colors),
                              if (isMismatch) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, size: 12, color: colors.warning),
                                    const SizedBox(width: 4),
                                    Text('Map mismatch: $mMap (active: $currentMap)',
                                        style: TextStyle(fontSize: 10, color: colors.warning, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: enabled,
                                onChanged: (v) => onToggle(schedule, v),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: colors.danger.withValues(alpha: 0.8), size: 18),
                                onPressed: () => onDelete(schedule['id'] as String),
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
    final colors = AppColors.of(context);
    return Expanded(
      child: Card(
        elevation: 0,
        color: colors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TextStyle(fontSize: 11, color: colors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary)),
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
    this.missionMap,
    this.currentMap,
    required this.repeatLabel,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onRunNow,
  });

  final Map<String, dynamic> schedule;
  final String missionName;
  final String? missionMap;
  final String? currentMap;
  final String repeatLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRunNow;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = schedule['enabled'] == true;
    final hour = (schedule['hour'] as num).toInt();
    final minute = (schedule['minute'] as num).toInt();
    final timeStr =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    final name = (schedule['name'] as String?)?.isNotEmpty == true
        ? schedule['name'] as String
        : missionName;
    final isMismatch = missionMap != null && currentMap != null && missionMap != currentMap;

    return Card(
      elevation: 0,
      color: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: enabled ? colors.primary.withValues(alpha: 0.35) : colors.border,
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (enabled ? colors.primary : colors.surfaceSunken).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: enabled ? colors.primary.withValues(alpha: 0.3) : colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 15,
                        color: enabled ? colors.primary : colors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: enabled ? colors.primary : colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: (enabled ? colors.stateIdle : colors.surfaceSunken).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    enabled ? 'ACTIVE' : 'PAUSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: enabled ? colors.stateIdle : colors.textTertiary,
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
            const SizedBox(height: AppSpacing.xs),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colors.textPrimary),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.route_rounded, size: 13, color: colors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Mission: $missionName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ),
                if (isMismatch) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: colors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 10, color: colors.warning),
                        const SizedBox(width: 3),
                        Text(
                          'Inactive Map ($missionMap)',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: colors.warning),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            _WeekdaysPillStrip(schedule: schedule, colors: colors),
            const Spacer(),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: BorderSide(color: colors.border),
                  ),
                  onPressed: onRunNow,
                  icon: const Icon(Icons.play_arrow_rounded, size: 15),
                  label: const Text('Run Now', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: BorderSide(color: colors.border),
                  ),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 13),
                  label: const Text('Edit', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, size: 17, color: colors.danger.withValues(alpha: 0.8)),
                  tooltip: 'Delete Schedule',
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

/// 7-day pill strip [M] [T] [W] [T] [F] [S] [S] showing active days.
class _WeekdaysPillStrip extends StatelessWidget {
  const _WeekdaysPillStrip({required this.schedule, required this.colors});

  final Map<String, dynamic> schedule;
  final AppColorsTheme colors;

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final repeat = schedule['repeat'] as String? ?? 'daily';
    final isDaily = repeat == 'daily';
    final isInterval = repeat == 'interval';
    final activeDays = (schedule['weekdays'] as List? ?? const []).cast<int>().toSet();

    if (isInterval) {
      final mins = (schedule['interval_minutes'] as num?)?.toInt() ?? 30;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('Interval: every $mins min', style: const TextStyle(fontSize: 10, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
      );
    }

    if (repeat == 'once') {
      return Text('Runs once on ${schedule['date'] ?? 'scheduled date'}', style: TextStyle(fontSize: 11, color: colors.textSecondary));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 7; i++) ...[
          Container(
            width: 19,
            height: 19,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: (isDaily || activeDays.contains(i))
                  ? colors.primary.withValues(alpha: 0.18)
                  : colors.surfaceSunken,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: (isDaily || activeDays.contains(i)) ? colors.primary : colors.border,
                width: 1,
              ),
            ),
            child: Text(
              _days[i],
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: (isDaily || activeDays.contains(i)) ? colors.primary : colors.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
