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
  String? _currentMap;
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
      final results = await Future.wait([
        api.listMissions(),
        api.missionStatus(),
        api.getCurrentMap(),
      ]);
      if (!mounted) return;
      setState(() {
        _missions = results[0] as List<Map<String, dynamic>>;
        _runnerStatus = results[1] as Map<String, dynamic>;
        _currentMap = results[2] as String?;
      });
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _createMission() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MissionEditorScreen()),
    );
    if (created == true) _load();
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

    return Scaffold(
      appBar: AppBar(
        title: Text(isDesktop ? 'Missions & Autonomous Tasks' : 'Missions'),
        actions: [
          if (isDesktop) ...[
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.alarm_rounded, size: 18),
                label: const Text('Scheduler'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SchedulesListScreen()),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Mission'),
                onPressed: _createMission,
              ),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Scheduler',
              icon: const Icon(Icons.alarm_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SchedulesListScreen()),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: isDesktop
          ? null
          : FloatingActionButton.extended(
              onPressed: _createMission,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Mission'),
            ),
      body: SafeArea(
        child: robotIp == null
            ? const Center(child: Text('Not connected.'))
            : _Body(
                missions: _missions,
                runnerStatus: _runnerStatus,
                currentMap: _currentMap,
                error: _error,
                onRetry: _load,
                onCreateMission: _createMission,
                onEdit: (mission) async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                        builder: (_) => MissionEditorScreen(existing: mission)),
                  );
                  if (changed == true) _load();
                },
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
    required this.currentMap,
    required this.error,
    required this.onRetry,
    required this.onCreateMission,
    required this.onEdit,
    required this.onOpen,
  });

  final List<Map<String, dynamic>>? missions;
  final Map<String, dynamic>? runnerStatus;
  final String? currentMap;
  final SdkApiException? error;
  final VoidCallback onRetry;
  final VoidCallback onCreateMission;
  final void Function(Map<String, dynamic>) onEdit;
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
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: onCreateMission,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Mission'),
            ),
          ],
        ),
      );
    }

    final activeId = runnerStatus?['mission_id'] as String?;
    final activeState = runnerStatus?['state'] as String?;
    final pauseReason = runnerStatus?['pause_reason'] as String?;
    final isLowBatteryPaused =
        activeState == 'paused' && pauseReason == 'low_battery';
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;

    if (isDesktop) {
      return _buildDesktop(
          context, missions!, activeId, activeState, pauseReason);
    }

    final isRunning = activeState == 'running' || activeState == 'paused';

    return CenteredFormColumn(
      maxWidth:
          Breakpoints.of(context) == DeviceClass.desktop ? 960 : 720,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: missions!.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          final mission = missions![i];
          final id = mission['id'] as String;
          final steps = (mission['steps'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          final isActive = id == activeId && isRunning;
          final isCompleted = id == activeId && activeState == 'completed';
          final status =
              isActive ? activeState : (isCompleted ? 'completed' : null);
          final loopForever = mission['loop_forever'] == true;
          final loopCount = (mission['loop_count'] as num?)?.toInt() ?? 1;
          final color =
              status == null ? AppColors.primary : _statusColor(status);

          var subtitle = '${steps.length} step${steps.length == 1 ? '' : 's'}';
          if (isActive && isLowBatteryPaused) {
            subtitle += ' · ⚡ Auto-charging at dock';
          } else if (loopForever) {
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
                            if (mission['map'] != null) ...[
                              const SizedBox(height: 4),
                              Builder(builder: (context) {
                                final missionMap = mission['map'] as String;
                                final isMismatch = currentMap != null &&
                                    missionMap != currentMap;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isMismatch
                                        ? AppColors.warning.withValues(alpha: 0.12)
                                        : AppColors.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isMismatch
                                          ? AppColors.warning.withValues(alpha: 0.4)
                                          : AppColors.primary.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isMismatch
                                            ? Icons.warning_amber_rounded
                                            : Icons.map_outlined,
                                        size: 11,
                                        color: isMismatch
                                            ? AppColors.warning
                                            : AppColors.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isMismatch
                                            ? '$missionMap (Inactive)'
                                            : 'Map: $missionMap',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: isMismatch
                                              ? AppColors.warning
                                              : AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            if (steps.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xs),
                              _StepPreviewRow(steps: steps),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      if (status != null) ...[
                        Chip(
                          avatar: status == 'running'
                              ? StatusPulseDot(
                                  color: _statusColor(status),
                                  live: true,
                                  size: 6)
                              : (isActive && isLowBatteryPaused
                                  ? const Icon(Icons.bolt_rounded,
                                      size: 12, color: AppColors.warning)
                                  : null),
                          label: Text(
                              isActive && isLowBatteryPaused
                                  ? 'CHARGING'
                                  : status.toUpperCase(),
                              style: const TextStyle(fontSize: 11)),
                          backgroundColor:
                              _statusColor(status).withValues(alpha: 0.12),
                          labelStyle:
                              TextStyle(color: _statusColor(status)),
                          side: BorderSide.none,
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 20, color: AppColors.primary),
                        tooltip: 'Edit mission',
                        onPressed: () => onEdit(mission),
                      ),
                      const Icon(Icons.chevron_right_rounded,
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

  Widget _buildDesktop(
      BuildContext context,
      List<Map<String, dynamic>> missions,
      String? activeId,
      String? activeState,
      String? pauseReason) {
    final activeMission = activeId != null
        ? missions.firstWhere((m) => m['id'] == activeId,
            orElse: () => const {})
        : null;
    final isRunning = activeState == 'running' || activeState == 'paused';
    final isCompleted = activeState == 'completed';
    final isLowBattery =
        activeState == 'paused' && pauseReason == 'low_battery';

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isRunning &&
              activeMission != null &&
              activeMission.isNotEmpty) ...[
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                side: BorderSide(
                  color: _statusColor(activeState!),
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    StatusPulseDot(
                      color: _statusColor(activeState),
                      live: activeState == 'running',
                      size: 10,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                activeMission['name'] as String? ?? activeId!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Chip(
                                avatar: isLowBattery
                                    ? const Icon(Icons.bolt_rounded,
                                        size: 14, color: AppColors.warning)
                                    : null,
                                label: Text(
                                    isLowBattery
                                        ? 'PAUSED (CHARGING)'
                                        : activeState.toUpperCase(),
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                                backgroundColor: _statusColor(activeState)
                                    .withValues(alpha: 0.15),
                                labelStyle: TextStyle(
                                    color: _statusColor(activeState)),
                                side: BorderSide.none,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (isLowBattery)
                            const Text(
                              'Battery low (≤ 5%) · Auto-docked to recharge · Auto-resumes at 95%',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w600),
                            )
                          else
                            Builder(builder: (context) {
                              final totalSteps =
                                  (activeMission['steps'] as List? ?? []).length;
                              final stepIdx =
                                  (runnerStatus?['step_index'] as int? ?? 0);
                              final currentStepNum = (stepIdx + 1)
                                  .clamp(1, totalSteps > 0 ? totalSteps : 1);
                              return Text(
                                'Step $currentStepNum of $totalSteps currently executing',
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary),
                              );
                            }),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => onOpen(activeMission),
                      icon: const Icon(Icons.fullscreen_rounded, size: 18),
                      label: const Text('View Live Execution'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Row(
            children: [
              Text(
                'All Missions (${missions.length})',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (currentMap != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Chip(
                  avatar: const Icon(Icons.map_outlined,
                      size: 14, color: AppColors.primary),
                  label: Text('Map: $currentMap'),
                  backgroundColor: AppColors.surface,
                ),
              ],
              const Spacer(),
              Chip(
                avatar: const Icon(Icons.tune_rounded,
                    size: 14, color: AppColors.primary),
                label: Text('Mission Runner: ${activeState ?? 'idle'}'),
                backgroundColor: AppColors.surface,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 440,
                mainAxisExtent: 220,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
              ),
              itemCount: missions.length,
              itemBuilder: (context, i) {
                final mission = missions[i];
                final id = mission['id'] as String;
                final steps = (mission['steps'] as List? ?? const [])
                    .cast<Map<String, dynamic>>();
                final isActive = id == activeId && isRunning;
                final isCompletedCard = id == activeId && isCompleted;
                final status = isActive
                    ? activeState
                    : (isCompletedCard ? 'completed' : null);
                final loopForever = mission['loop_forever'] == true;
                final loopCount =
                    (mission['loop_count'] as num?)?.toInt() ?? 1;
                final color =
                    status == null ? AppColors.primary : _statusColor(status);

                var subtitle =
                    '${steps.length} step${steps.length == 1 ? '' : 's'}';
                if (loopForever) {
                  subtitle += ' · repeats forever';
                } else if (loopCount > 1) {
                  subtitle += ' · repeats ${loopCount}x';
                }

                final missionMap = mission['map'] as String?;
                final isMismatch = missionMap != null &&
                    currentMap != null &&
                    missionMap != currentMap;

                return Card(
                  elevation: isActive ? 2 : 0,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.cardRadius),
                    side: BorderSide(
                      color: isActive ? color : AppColors.border,
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: color.withValues(alpha: 0.12),
                              child: Icon(Icons.route_rounded,
                                  color: color, size: 20),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mission['name'] as String? ?? id,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12),
                                  ),
                                  if (missionMap != null) ...[
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isMismatch
                                            ? AppColors.warning.withValues(alpha: 0.12)
                                            : AppColors.primary.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isMismatch
                                              ? AppColors.warning.withValues(alpha: 0.4)
                                              : AppColors.primary.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isMismatch
                                                ? Icons.warning_amber_rounded
                                                : Icons.map_outlined,
                                            size: 10,
                                            color: isMismatch
                                                ? AppColors.warning
                                                : AppColors.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isMismatch
                                                ? '$missionMap (Inactive)'
                                                : 'Map: $missionMap',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: isMismatch
                                                  ? AppColors.warning
                                                  : AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (status != null)
                              Chip(
                                avatar: status == 'running'
                                    ? StatusPulseDot(
                                        color: _statusColor(status),
                                        live: true,
                                        size: 6)
                                    : (isActive && isLowBattery
                                        ? const Icon(Icons.bolt_rounded,
                                            size: 12, color: AppColors.warning)
                                        : null),
                                label: Text(
                                    isActive && isLowBattery
                                        ? 'CHARGING'
                                        : status.toUpperCase(),
                                    style: const TextStyle(fontSize: 11)),
                                backgroundColor: _statusColor(status)
                                    .withValues(alpha: 0.12),
                                labelStyle: TextStyle(
                                    color: _statusColor(status)),
                                side: BorderSide.none,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const Text(
                          'Step Route:',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        _StepPreviewRow(steps: steps),
                        const Spacer(),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => onEdit(mission),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Edit'),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => onOpen(mission),
                                icon: Icon(
                                    isActive
                                        ? Icons.open_in_new_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 16),
                                label: Text(isActive
                                    ? 'View Live'
                                    : 'Details & Run'),
                              ),
                            ),
                          ],
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
