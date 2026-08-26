import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/localize_at_dock.dart';
import '../../utils/mission_step_summary.dart';
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
      if (mounted) setState(() => _locations = locations);
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

  @override
  Widget build(BuildContext context) {
    final steps = (widget.mission['steps'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final stepIndex =
        _isThisMission ? (_status?['step_index'] as int? ?? -1) : -1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, __) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
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
                  if (_isThisMission)
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
                            stepIndex > i &&
                            (running || paused);
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
    var base = _state[0].toUpperCase() + _state.substring(1);
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
              locations: pins,
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
    required this.busy,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final String state;
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
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: busy ? null : onResume,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Resume'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onCancel,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Cancel'),
            ),
          ),
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
