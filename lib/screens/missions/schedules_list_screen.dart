import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/fade_in.dart';
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
        return days.isEmpty ? 'Weekly' : days;
      default:
        return 'Daily';
    }
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

    return Scaffold(
      appBar: AppBar(title: const Text('Scheduler')),
      floatingActionButton: (robotIp == null || _missions == null)
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ScheduleEditorScreen(missions: _missions!),
                  ),
                );
                if (created == true) _load();
              },
              icon: const Icon(Icons.add_alarm_rounded),
              label: const Text('New Schedule'),
            ),
      body: SafeArea(
        child: robotIp == null
            ? const Center(child: Text('Not connected.'))
            : _Body(
                schedules: _schedules,
                error: _error,
                onRetry: _load,
                missionName: _missionName,
                repeatLabel: _repeatLabel,
                onToggle: _toggleEnabled,
                onEdit: (schedule) async {
                  if (_missions == null) return;
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ScheduleEditorScreen(
                          existing: schedule, missions: _missions!),
                    ),
                  );
                  if (changed == true) _load();
                },
                onDelete: _delete,
              ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.schedules,
    required this.error,
    required this.onRetry,
    required this.missionName,
    required this.repeatLabel,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Map<String, dynamic>>? schedules;
  final SdkApiException? error;
  final VoidCallback onRetry;
  final String Function(String missionId) missionName;
  final String Function(Map<String, dynamic>) repeatLabel;
  final void Function(Map<String, dynamic>, bool) onToggle;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(String) onDelete;

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
                color:
                    unreachable ? AppColors.textSecondary : AppColors.danger),
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
          padding: EdgeInsets.all(AppSpacing.lg), child: SkeletonList());
    }
    if (schedules!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alarm_add_rounded,
                size: 48, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            const Text('No schedules yet.',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            const Text('Set a mission to run automatically at a time.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return CenteredFormColumn(
      maxWidth: 720,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: schedules!.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          final schedule = schedules![i];
          final enabled = schedule['enabled'] == true;
          final hour = (schedule['hour'] as num).toInt();
          final minute = (schedule['minute'] as num).toInt();
          final time = TimeOfDay(hour: hour, minute: minute).format(context);
          return FadeSlideIn(
            delay: Duration(milliseconds: 30 * i),
            offset: 8,
            child: Card(
              child: ListTile(
                onTap: () => onEdit(schedule),
                leading: CircleAvatar(
                  backgroundColor:
                      (enabled ? AppColors.primary : AppColors.textTertiary)
                          .withValues(alpha: 0.12),
                  child: Icon(Icons.alarm_rounded,
                      color:
                          enabled ? AppColors.primary : AppColors.textTertiary),
                ),
                title: Text(schedule['name'] as String? ??
                    missionName(schedule['mission_id'] as String)),
                subtitle: Text(
                    '$time · ${repeatLabel(schedule)} · ${missionName(schedule['mission_id'] as String)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: enabled,
                      onChanged: (v) => onToggle(schedule, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => onDelete(schedule['id'] as String),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
