import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/mission_step_summary.dart';
import '../../widgets/design/fade_in.dart';
import '../../widgets/design/skeleton.dart';
import '../../widgets/design/status_pulse.dart';
import 'mission_detail_screen.dart';
import 'mission_editor_screen.dart';
import 'schedules_list_screen.dart';

/// Reference §7 (Mission Planner). Missions — named, ordered step sequences
/// with server-side start/pause/resume/cancel — are genuinely SDK-exclusive
/// (navpromini_sdk's Mission Manager, see handlers/missions.py's own module
/// docstring), so this is built on SdkApiService, same carve-out as
/// Locations. See navpromini-sdk-is-optional-not-gateway in project memory.
class MissionsListScreen extends StatefulWidget {
  const MissionsListScreen({super.key});

  @override
  State<MissionsListScreen> createState() => _MissionsListScreenState();
}

class _MissionsListScreenState extends State<MissionsListScreen> {
  List<Map<String, dynamic>>? _missions;
  Map<String, dynamic>? _runnerStatus;
  SdkApiException? _error;
  bool _requested = false;
  SdkApiService? _api;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Missions are robot-owned, not this client's own state — a mission
    // created or edited from another device connected to the same robot
    // (a second phone, a PC) otherwise never appears here until this screen
    // happens to remount. Same periodic-poll pattern MissionDetailScreen
    // already uses for one mission's live status, just for the whole list.
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
    setState(() => _error = null);
    try {
      final results =
          await Future.wait([api.listMissions(), api.missionStatus()]);
      if (!mounted) return;
      setState(() {
        _missions = results[0] as List<Map<String, dynamic>>;
        _runnerStatus = results[1] as Map<String, dynamic>;
      });
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
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
      appBar: AppBar(
        title: const Text('Missions'),
        actions: [
          IconButton(
            tooltip: 'Scheduler',
            icon: const Icon(Icons.alarm_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SchedulesListScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: robotIp == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                      builder: (_) => const MissionEditorScreen()),
                );
                if (created == true) _load();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Mission'),
            ),
      body: SafeArea(
        child: robotIp == null
            ? const Center(child: Text('Not connected.'))
            : _Body(
                missions: _missions,
                runnerStatus: _runnerStatus,
                error: _error,
                onRetry: _load,
                onOpen: (mission) async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                        builder: (_) => MissionDetailScreen(mission: mission)),
                  );
                  if (changed == true) _load();
                },
              ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.missions,
    required this.runnerStatus,
    required this.error,
    required this.onRetry,
    required this.onOpen,
  });

  final List<Map<String, dynamic>>? missions;
  final Map<String, dynamic>? runnerStatus;
  final SdkApiException? error;
  final VoidCallback onRetry;
  final void Function(Map<String, dynamic>) onOpen;

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
                  ? "Missions need navpro-sdk.service running on the robot — it isn't reachable right now."
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

    if (missions == null) {
      return const Padding(
          padding: EdgeInsets.all(AppSpacing.lg), child: SkeletonList());
    }
    if (missions!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_outlined, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            const Text('No missions yet.',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            const Text('Create one from your saved locations.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    final activeId = runnerStatus?['mission_id'] as String?;
    final activeState = runnerStatus?['state'] as String?;

    return CenteredFormColumn(
      maxWidth: 720,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: missions!.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          final mission = missions![i];
          final id = mission['id'] as String;
          final steps = (mission['steps'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          final isActive =
              id == activeId && activeState != null && activeState != 'idle';
          final status = isActive ? activeState : null;
          final loopForever = mission['loop_forever'] == true;
          final loopCount = (mission['loop_count'] as num?)?.toInt() ?? 1;
          final color =
              status == null ? AppColors.primary : _statusColor(status);

          var subtitle = '${steps.length} step${steps.length == 1 ? '' : 's'}';
          if (loopForever) {
            subtitle += ' · repeats forever';
          } else if (loopCount > 1) {
            subtitle += ' · repeats ${loopCount}x';
          }

          return FadeSlideIn(
            delay: Duration(milliseconds: 30 * i),
            offset: 8,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpen(mission),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(Icons.route_rounded, color: color),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(mission['name'] as String? ?? id,
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(subtitle,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                            if (steps.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xs),
                              _StepPreviewRow(steps: steps),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      status != null
                          ? Chip(
                              avatar: status == 'running'
                                  ? StatusPulseDot(
                                      color: _statusColor(status),
                                      live: true,
                                      size: 6)
                                  : null,
                              label: Text(status.toUpperCase(),
                                  style: const TextStyle(fontSize: 11)),
                              backgroundColor:
                                  _statusColor(status).withValues(alpha: 0.12),
                              labelStyle:
                                  TextStyle(color: _statusColor(status)),
                              side: BorderSide.none,
                            )
                          : const Icon(Icons.chevron_right_rounded,
                              color: AppColors.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(String state) => switch (state) {
        'running' => AppColors.stateExecuting,
        'paused' => AppColors.warning,
        'completed' => AppColors.stateIdle,
        'failed' => AppColors.danger,
        'canceled' => AppColors.textSecondary,
        _ => AppColors.textSecondary,
      };
}

/// A quick "shape" of the mission at a glance — small icons for each step's
/// type, in order, capped so a very long mission doesn't overflow the card.
class _StepPreviewRow extends StatelessWidget {
  const _StepPreviewRow({required this.steps});

  final List<Map<String, dynamic>> steps;

  static const _maxShown = 8;

  @override
  Widget build(BuildContext context) {
    final shown = steps.take(_maxShown).toList();
    final overflow = steps.length - shown.length;
    return Row(
      children: [
        for (final step in shown) ...[
          Icon(missionStepIcon(step), size: 13, color: missionStepColor(step)),
          const SizedBox(width: 4),
        ],
        if (overflow > 0)
          Text('+$overflow',
              style:
                  const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
      ],
    );
  }
}
