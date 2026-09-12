import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/localize_at_dock.dart';
import '../../utils/mission_step_summary.dart';
import '../../widgets/app_shell/app_shell.dart';
import '../../widgets/design/fade_in.dart';
import '../../widgets/design/status_pulse.dart';
import '../../widgets/map/occupancy_grid_view.dart';
import 'mission_editor_screen.dart';

/// Reference §7's "Going to Kitchen" run view, generalized to any mission:
/// ordered steps with the currently-executing one highlighted, driven by
/// polling GET /missions/status (the mission runner is a single
/// module-level singleton server-side — see missions.py's own docstring —
/// so this poll reflects real state, not a client-side guess).
class MissionDetailScreen extends StatefulWidget {
  const MissionDetailScreen({super.key, required this.mission});

  final Map<String, dynamic> mission;

  @override
  State<MissionDetailScreen> createState() => _MissionDetailScreenState();
}

class _MissionDetailScreenState extends State<MissionDetailScreen> {
  Timer? _poll;
  Map<String, dynamic>? _status;
  String? _actionError;
  bool _busy = false;
  bool _changed = false;

  List<Map<String, dynamic>>? _locations;
  ({double x, double y, double theta})? _dockPose;
  String? _currentMap;

  String get _id => widget.mission['id'] as String;

  SdkApiService? get _api {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    return ip == null ? null : SdkApiService(ip);
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMapData());
  }

  /// Saved locations + dock pose, used only to plot the route preview card
  /// — `navigate` steps by name need a location's x/y looked up, and
  /// `dock`/`undock` steps need the dock's pose (same fallback pattern as
  /// Map View/Teleop: fetchDockPose covers the case where /dock_pose hasn't
  /// freshly republished this run but the SDK still knows it).
  Future<void> _loadMapData() async {
    final api = _api;
    if (api == null) return;
    try {
      final locations = await api.listWaypoints();
      final currentMap = await api.getCurrentMap();
      if (mounted) {
        setState(() {
          _locations = locations;
          _currentMap = currentMap;
        });
      }
    } on SdkApiException {
      // Route preview just won't have pins for by-name steps — not fatal.
    }
    final dock = await fetchDockPose(api);
    if (mounted) setState(() => _dockPose = dock);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final api = _api;
    if (api == null) return;
    try {
      final status = await api.missionStatus();
      if (!mounted) return;
      setState(() => _status = status);
    } on SdkApiException {
      // Transient poll failure — keep showing the last known status rather
      // than flashing an error every 2s.
    }
  }

  bool get _isThisMission => _status?['mission_id'] == _id;
  String get _state =>
      _isThisMission ? (_status?['state'] as String? ?? 'idle') : 'idle';
  String? get _pauseReason =>
      _isThisMission ? (_status?['pause_reason'] as String?) : null;
  bool get isLowBatteryPaused =>
      _state == 'paused' && _pauseReason == 'low_battery';

  Future<void> _act(Future<void> Function(SdkApiService, String) action) async {
    final api = _api;
    if (api == null) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action(api, _id);
      _changed = true;
      await _refresh();
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => MissionEditorScreen(existing: widget.mission)),
    );
    // widget.mission is now stale (edited server-side under the same id) —
    // pop back to the list rather than keep showing it, so the list's own
    // reload picks up the fresh steps/name.
    if (saved == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final api = _api;
    if (api == null) return;

    try {
      // Check if other missions link/redirect to this mission
      final allMissions = await api.listMissions();
      final referencingMissions = <String>[];

      for (final m in allMissions) {
        if (m['id'] == _id) continue;
        final nodes = (m['nodes'] as List? ?? const []).cast<Map<String, dynamic>>();
        for (final node in nodes) {
          if (node['type'] == 'switch_mission' || node['type'] == 'redirect_mission') {
            final target = node['params']?['target_mission_id'] ?? node['params']?['mission_id'];
            if (target == _id) {
              referencingMissions.add(m['name'] as String? ?? m['id'] as String);
              break;
            }
          }
        }
      }

      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(referencingMissions.isNotEmpty
              ? 'Warning: Mission is Referenced'
              : 'Delete Mission?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (referencingMissions.isNotEmpty) ...[
                Text(
                  'This mission is called by other missions via "Switch Mission" nodes:\n• ${referencingMissions.join("\n• ")}\n\nDeleting it will cause those missions to fail or branch to their error paths.',
                  style: TextStyle(color: AppColors.danger, fontSize: 13),
                ),
                const SizedBox(height: 12),
              ],
              Text('Are you sure you want to permanently delete "${widget.mission['name'] ?? _id}"?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      await api.deleteMission(_id);
      _changed = true;
      if (!mounted) return;
      Navigator.of(context).pop();
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(_changed);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = (widget.mission['steps'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final stepIndex =
        _isThisMission ? (_status?['step_index'] as int? ?? -1) : -1;
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;
    final ros2 = context.watch<ConnectionProvider>().ros2;
    final telemetry = context.watch<RobotTelemetryProvider>();

    if (isDesktop) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, __) {
          if (!didPop) _goBack();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back to Missions',
              onPressed: _goBack,
            ),
            title: Text(widget.mission['name'] as String? ?? _id),
            actions: [
              if (!running && !paused) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _edit,
                  tooltip: 'Edit mission',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: _delete,
                  tooltip: 'Delete mission',
                ),
              ],
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Pane: Large Live Interactive Map & Route
                  Expanded(
                    flex: 6,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ros2 == null
                                ? const Center(child: Text('Not connected.'))
                                : OccupancyGridView(
                                    ros2: ros2,
                                    interactive: true,
                                    initialPose: telemetry.rawPose,
                                    initialPath: telemetry.currentPath,
                                    locations: _routePins(steps),
                                    showWaypointRoute: true,
                                    fitWholeMap: false,
                                    showRobot: true,
                                    showDock: true,
                                    showPath: true,
                                  ),
                          ),
                          Positioned(
                            left: AppSpacing.md,
                            top: AppSpacing.md,
                            child: Card(
                              color: AppColors.surface.withValues(alpha: 0.9),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.xs),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.route_rounded,
                                        size: 16, color: AppColors.primary),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      'Route Preview (${_routePins(steps).length} points)',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),

                  // Right Pane: Mission Status, Controls & Steps Pipeline
                  Expanded(
                    flex: 5,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.mission['name'] as String? ??
                                            _id,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${steps.length} steps · ${widget.mission['loop_forever'] == true ? 'repeats forever' : 'repeats ${(widget.mission['loop_count'] ?? 1)}x'}',
                                        style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 13),
                                      ),
                                      if (widget.mission['map'] != null) ...[
                                        const SizedBox(height: 4),
                                        Builder(builder: (context) {
                                          final missionMap =
                                              widget.mission['map'] as String;
                                          final isMismatch = _currentMap != null &&
                                              missionMap != _currentMap;
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isMismatch
                                                  ? AppColors.warning
                                                      .withValues(alpha: 0.12)
                                                  : AppColors.primary
                                                      .withValues(alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isMismatch
                                                    ? AppColors.warning
                                                        .withValues(alpha: 0.4)
                                                    : AppColors.primary
                                                        .withValues(alpha: 0.2),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isMismatch
                                                      ? Icons.warning_amber_rounded
                                                      : Icons.map_outlined,
                                                  size: 13,
                                                  color: isMismatch
                                                      ? AppColors.warning
                                                      : AppColors.primary,
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  isMismatch
                                                      ? 'Map: $missionMap (Active map: $_currentMap)'
                                                      : 'Map: $missionMap',
                                                  style: TextStyle(
                                                    fontSize: 11,
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
                                    ],
                                  ),
                                ),
                                Chip(
                                  avatar: _state == 'running'
                                      ? StatusPulseDot(
                                          color: _stateColor(_state),
                                          live: true,
                                          size: 8)
                                      : (isLowBatteryPaused
                                          ? const Icon(Icons.bolt_rounded,
                                              size: 14,
                                              color: AppColors.warning)
                                          : null),
                                  label: Text(
                                      isLowBatteryPaused
                                          ? 'PAUSED (CHARGING)'
                                          : _state.toUpperCase(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12)),
                                  backgroundColor: _stateColor(_state)
                                      .withValues(alpha: 0.12),
                                  labelStyle:
                                      TextStyle(color: _stateColor(_state)),
                                  side: BorderSide.none,
                                ),
                              ],
                            ),
                            if (isLowBatteryPaused) ...[
                              const SizedBox(height: AppSpacing.md),
                              _LowBatteryChargingNotice(
                                batteryPercent: telemetry.batteryPercentage,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),

                            // Controls Bar
                            _Controls(
                              state: _state,
                              pauseReason: _pauseReason,
                              busy: _busy,
                              onStart: () => _act(
                                  (api, id) => api.startMission(id)),
                              onPause: () => _act(
                                  (api, id) => api.pauseMission(id)),
                              onResume: () => _act(
                                  (api, id) => api.resumeMission(id)),
                              onCancel: () => _act(
                                  (api, id) => api.cancelMission(id)),
                            ),
                            if (_actionError != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Text(_actionError!,
                                  style: const TextStyle(
                                      color: AppColors.danger)),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            const Divider(),
                            const SizedBox(height: AppSpacing.xs),

                            // Steps Pipeline Header
                            Text(
                              'Execution Sequence (${steps.length} steps)',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: AppSpacing.sm),

                            // Steps Pipeline List
                            Expanded(
                              child: ListView.separated(
                                itemCount: steps.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: AppSpacing.xs),
                                itemBuilder: (context, i) {
                                  final isCurrent = running && i == stepIndex;
                                  final isDone = _isThisMission &&
                                      ((stepIndex > i && (running || paused)) ||
                                          _state == 'completed');
                                  return Card(
                                    elevation: isCurrent ? 2 : 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                        color: isCurrent
                                            ? AppColors.primary
                                            : AppColors.border,
                                        width: isCurrent ? 1.5 : 1,
                                      ),
                                    ),
                                    color: isCurrent
                                        ? AppColors.primary
                                            .withValues(alpha: 0.08)
                                        : AppColors.surfaceSunken,
                                    child: ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 13,
                                        backgroundColor: isDone
                                            ? AppColors.stateIdle
                                            : isCurrent
                                                ? AppColors.primary
                                                : AppColors.border,
                                        child: isDone
                                            ? const Icon(Icons.check_rounded,
                                                size: 14, color: Colors.white)
                                            : Text('${i + 1}',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: isCurrent
                                                        ? AppColors.textOnPrimary
                                                        : AppColors
                                                            .textSecondary)),
                                      ),
                                      title: Text(
                                          missionStepSummary(steps[i]),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                      subtitle: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(missionStepIcon(steps[i]),
                                              size: 13,
                                              color: AppColors.textSecondary),
                                          const SizedBox(width: 4),
                                          Text(
                                              steps[i]['type'] as String? ??
                                                  '',
                                              style: const TextStyle(
                                                  color: AppColors
                                                      .textSecondary,
                                                  fontSize: 11)),
                                        ],
                                      ),
                                      trailing: isCurrent
                                          ? const Icon(
                                              Icons.navigation_rounded,
                                              color: AppColors.primary,
                                              size: 18)
                                          : null,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, __) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back to Missions',
            onPressed: _goBack,
          ),
          title: Text(widget.mission['name'] as String? ?? _id),
          actions: [
            if (!running && !paused) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: _edit,
                tooltip: 'Edit mission',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _delete,
                tooltip: 'Delete mission',
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: CenteredFormColumn(
            maxWidth: 640,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RouteMapCard(pins: _routePins(steps)),
                  if (widget.mission['map'] != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Builder(builder: (context) {
                      final missionMap = widget.mission['map'] as String;
                      final isMismatch =
                          _currentMap != null && missionMap != _currentMap;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isMismatch
                              ? AppColors.warning.withValues(alpha: 0.12)
                              : AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isMismatch
                                ? AppColors.warning.withValues(alpha: 0.4)
                                : AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isMismatch
                                  ? Icons.warning_amber_rounded
                                  : Icons.map_outlined,
                              size: 14,
                              color: isMismatch
                                  ? AppColors.warning
                                  : AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isMismatch
                                    ? 'Map Mismatch: Mission is for "$missionMap", active map is "$_currentMap"'
                                    : 'Map: $missionMap',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isMismatch
                                      ? AppColors.warning
                                      : AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  if (_isThisMission) ...[
                    FadeSlideIn(
                      child: Card(
                        color: _stateColor(_state).withValues(alpha: 0.08),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            children: [
                              if (_state == 'running') ...[
                                StatusPulseDot(
                                    color: _stateColor(_state),
                                    live: true,
                                    size: 8),
                                const SizedBox(width: AppSpacing.sm),
                              ] else if (isLowBatteryPaused) ...[
                                const Icon(Icons.bolt_rounded,
                                    color: AppColors.warning),
                                const SizedBox(width: AppSpacing.sm),
                              ] else
                                Icon(Icons.flag_rounded,
                                    color: _stateColor(_state)),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: AppMotion.fast,
                                  child: Text(
                                    _statusLine(),
                                    key: ValueKey(_statusLine()),
                                    style: TextStyle(
                                        color: _stateColor(_state),
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (isLowBatteryPaused) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _LowBatteryChargingNotice(
                        batteryPercent: telemetry.batteryPercentage,
                      ),
                    ],
                  ],
                  if (_actionError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_actionError!,
                        style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text('Waypoint List (${steps.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: ListView.separated(
                      itemCount: steps.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final isCurrent = running && i == stepIndex;
                        final isDone = _isThisMission &&
                            ((stepIndex > i && (running || paused)) ||
                                _state == 'completed');
                        return Card(
                          color: isCurrent
                              ? AppColors.primary.withValues(alpha: 0.06)
                              : null,
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: isDone
                                  ? AppColors.stateIdle
                                  : isCurrent
                                      ? AppColors.primary
                                      : AppColors.border,
                              child: isDone
                                  ? const Icon(Icons.check_rounded,
                                      size: 14, color: Colors.white)
                                  : Text('${i + 1}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: isCurrent
                                              ? AppColors.textOnPrimary
                                              : AppColors.textSecondary)),
                            ),
                            title: Text(missionStepSummary(steps[i])),
                            subtitle: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(missionStepIcon(steps[i]),
                                    size: 14, color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Text(steps[i]['type'] as String? ?? '',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                              ],
                            ),
                            trailing: isCurrent
                                ? const Icon(Icons.navigation_rounded,
                                    color: AppColors.primary)
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _Controls(
                    state: _state,
                    pauseReason: _pauseReason,
                    busy: _busy,
                    onStart: () => _act((api, id) => api.startMission(id)),
                    onPause: () => _act((api, id) => api.pauseMission(id)),
                    onResume: () => _act((api, id) => api.resumeMission(id)),
                    onCancel: () => _act((api, id) => api.cancelMission(id)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _statusLine() {
    final msg = _status?['message'] as String?;
    if (_state == 'completed') {
      return 'Mission Completed · All steps finished successfully';
    }
    var base = _state[0].toUpperCase() + _state.substring(1);
    if (_state == 'paused') {
      if (_pauseReason == 'low_battery') {
        base = 'Paused for Recharge (Auto-resumes at 95%)';
      } else if (_pauseReason == 'user') {
        base = 'Paused by operator';
      }
    }
    final loopTotal = _status?['loop_total'];
    final loopIndex = (_status?['loop_index'] as num?)?.toInt();
    if (_isThisMission && loopIndex != null && (running || paused)) {
      base += loopTotal == null
          ? ' · lap ${loopIndex + 1} · repeating forever'
          : ' · lap ${loopIndex + 1} of $loopTotal';
    }
    return msg != null && msg.isNotEmpty ? '$base — $msg' : base;
  }

  bool get running => _state == 'running';
  bool get paused => _state == 'paused';

  /// Numbered pins for the route preview card — `navigate` steps by raw
  /// x/y or by resolved saved-location name, plus `dock`/`undock` steps
  /// plotted at the known dock pose. Steps with no resolvable position
  /// (wait, call_service, call_action, or a by-name navigate before
  /// locations have loaded) are simply not pinned — they still show in the
  /// waypoint list below.
  List<Map<String, dynamic>> _routePins(List<Map<String, dynamic>> steps) {
    final pins = <Map<String, dynamic>>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      double? x, y;
      if (step['type'] == 'navigate') {
        final target = step['target'];
        if (target is String) {
          for (final loc in _locations ?? const <Map<String, dynamic>>[]) {
            if (loc['name'] == target) {
              x = (loc['x'] as num?)?.toDouble();
              y = (loc['y'] as num?)?.toDouble();
              break;
            }
          }
        } else {
          x = (step['x'] as num?)?.toDouble();
          y = (step['y'] as num?)?.toDouble();
        }
      } else if (step['type'] == 'dock' || step['type'] == 'undock') {
        x = _dockPose?.x;
        y = _dockPose?.y;
      }
      if (x != null && y != null) {
        pins.add({'name': '${i + 1}', 'x': x, 'y': y});
      }
    }
    return pins;
  }

  Color _stateColor(String state) => switch (state) {
        'running' => AppColors.stateExecuting,
        'paused' => AppColors.warning,
        'completed' => AppColors.stateIdle,
        'failed' => AppColors.danger,
        'canceled' => AppColors.textSecondary,
        _ => AppColors.textSecondary,
      };
}

/// A small live-map preview showing the mission's route as numbered pins —
/// mirrors the reference mockup's "Going to Kitchen" view. Renders nothing
/// when there's no robot connection or no step resolves to a position yet
/// (e.g. a by-name navigate step before locations have loaded), rather than
/// showing an empty or broken map.
class _RouteMapCard extends StatelessWidget {
  const _RouteMapCard({required this.pins});

  final List<Map<String, dynamic>> pins;

  @override
  Widget build(BuildContext context) {
    final ros2 = context.watch<ConnectionProvider>().ros2;
    final telemetry = context.watch<RobotTelemetryProvider>();
    if (ros2 == null || pins.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: FadeSlideIn(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 180,
            child: OccupancyGridView(
              ros2: ros2,
              interactive: false,
              initialPose: telemetry.rawPose,
              initialPath: telemetry.currentPath,
              locations: pins,
              showWaypointRoute: true,
              fitWholeMap: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    this.pauseReason,
    required this.busy,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final String state;
  final String? pauseReason;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (state == 'running') {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onPause,
              icon: const Icon(Icons.pause_rounded),
              label: const Text('Pause'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: busy ? null : onCancel,
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Cancel'),
            ),
          ),
        ],
      );
    }
    if (state == 'paused') {
      final isCharging = pauseReason == 'low_battery';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onResume,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(isCharging ? 'Resume Early' : 'Resume'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onCancel,
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(isCharging ? 'Cancel (Stay Docked)' : 'Cancel'),
                ),
              ),
            ],
          ),
          if (isCharging) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Robot auto-resumes once charged to 95%',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      );
    }
    return ElevatedButton.icon(
      onPressed: busy ? null : onStart,
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('Start Mission'),
    );
  }
}

class _LowBatteryChargingNotice extends StatelessWidget {
  const _LowBatteryChargingNotice({this.batteryPercent});

  final double? batteryPercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.battery_charging_full_rounded,
              color: AppColors.warning, size: 24),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Auto-Recharge in Progress',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.warning,
                      ),
                    ),
                    if (batteryPercent != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '(${batteryPercent!.round()}%)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Battery dropped ≤ 5%. Robot docked to recharge and will automatically undock and resume when battery reaches 95%.\n• Tap "Resume Early" to undock immediately.\n• Tap "Cancel" to stop mission (robot stays docked).',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
