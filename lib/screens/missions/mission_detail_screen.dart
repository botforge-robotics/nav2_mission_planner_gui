import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/localize_at_dock.dart';
import '../../utils/mission_step_summary.dart';
import '../../widgets/app_shell/app_shell.dart';
import '../../widgets/design/status_pulse.dart';
import '../../widgets/map/occupancy_grid_view.dart';
import 'mission_editor_screen.dart';
import 'graph/mission_graph_editor_screen.dart';

/// Mission Detail & Live Execution Monitor.
/// Provides real-time 2D Lidar Map tracking, live AMR telemetry HUD (speed, battery, ETAs),
/// and step/node execution pipeline tracking for both Sequential Routes and Visual Graphs.
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
    _startPoll(fast: false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMapData());
  }

  void _startPoll({bool fast = false}) {
    _poll?.cancel();
    final interval = fast ? const Duration(seconds: 2) : const Duration(seconds: 4);
    _poll = Timer.periodic(interval, (_) => _refresh());
  }

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
      // Non-fatal if offline
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
      final wasRunning = _isThisMission && (_state == 'running' || _state == 'paused');
      setState(() => _status = status);
      final isRunning = _isThisMission && (_state == 'running' || _state == 'paused');
      if (isRunning != wasRunning) {
        _startPoll(fast: isRunning);
      }
    } on SdkApiException {
      // Transient poll failure
    }
  }

  bool get _isThisMission => _status?['mission_id'] == _id;
  String get _state =>
      _isThisMission ? (_status?['state'] as String? ?? 'idle') : 'idle';
  String? get _pauseReason =>
      _isThisMission ? (_status?['pause_reason'] as String?) : null;
  bool get isLowBatteryPaused =>
      _state == 'paused' && _pauseReason == 'low_battery';

  bool get running => _state == 'running';
  bool get paused => _state == 'paused';

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
    final isGraph = widget.mission['type'] == 'graph' || widget.mission.containsKey('nodes');
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => isGraph
            ? MissionGraphEditorScreen(existingMission: widget.mission)
            : MissionEditorScreen(existing: widget.mission),
      ),
    );
    if (saved == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final api = _api;
    if (api == null) return;
    final colors = AppColors.of(context);

    try {
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
          icon: Icon(
            referencingMissions.isNotEmpty ? Icons.warning_rounded : Icons.delete_outline_rounded,
            color: colors.danger,
            size: 36,
          ),
          title: Text(referencingMissions.isNotEmpty
              ? 'Warning: Referenced Mission'
              : 'Delete Mission?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (referencingMissions.isNotEmpty) ...[
                Text(
                  'This mission is referenced by other missions:\n• ${referencingMissions.join("\n• ")}\n\nDeleting it will cause them to break.',
                  style: TextStyle(color: colors.danger, fontSize: 13),
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
              style: FilledButton.styleFrom(backgroundColor: colors.danger),
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
      Navigator.of(context).pop(true);
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
    final colors = AppColors.of(context);
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;
    final ros2 = context.watch<ConnectionProvider>().ros2;
    final telemetry = context.watch<RobotTelemetryProvider>();

    final isGraph = widget.mission['type'] == 'graph' || widget.mission.containsKey('nodes');
    final steps = (widget.mission['steps'] as List? ?? const []).cast<Map<String, dynamic>>();
    final nodes = (widget.mission['nodes'] as List? ?? const []).cast<Map<String, dynamic>>();

    final pins = _resolveRoutePins(steps, nodes, isGraph);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, __) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back to Missions',
            onPressed: _goBack,
          ),
          title: Row(
            children: [
              Text(widget.mission['name'] as String? ?? _id),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isGraph ? const Color(0xFF00E5FF) : colors.primary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isGraph ? 'VISUAL GRAPH' : 'LINEAR ROUTE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isGraph ? const Color(0xFF00E5FF) : colors.primary,
                  ),
                ),
              ),
            ],
          ),
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
          child: isDesktop
              ? _buildDesktopLayout(context, colors, ros2, telemetry, pins, steps, nodes, isGraph)
              : _buildMobileLayout(context, colors, ros2, telemetry, pins, steps, nodes, isGraph),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    AppColorsTheme colors,
    dynamic ros2,
    RobotTelemetryProvider telemetry,
    List<Map<String, dynamic>> pins,
    List<Map<String, dynamic>> steps,
    List<Map<String, dynamic>> nodes,
    bool isGraph,
  ) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Pane (60%): Interactive 2D Map & Route
          Expanded(
            flex: 6,
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colors.border),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ros2 == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wifi_off_rounded, size: 40, color: colors.textTertiary),
                                const SizedBox(height: 8),
                                Text('Live ROS 2 Map stream disconnected', style: TextStyle(color: colors.textSecondary)),
                              ],
                            ),
                          )
                        : OccupancyGridView(
                            ros2: ros2,
                            interactive: true,
                            initialPose: telemetry.rawPose,
                            initialPath: telemetry.currentPath,
                            locations: pins,
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: colors.surfaceElevated.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.route_rounded, size: 16, color: colors.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Route Preview (${pins.length} waypoints)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: colors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.lg),

          // Right Pane (40%): Telemetry HUD, Controls & Execution Pipeline
          Expanded(
            flex: 4,
            child: Card(
              elevation: 0,
              color: colors.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMissionHeader(colors, steps, nodes, isGraph),
                    const SizedBox(height: AppSpacing.md),
                    _LiveTelemetryHUD(telemetry: telemetry, isRunning: running, colors: colors),
                    const SizedBox(height: AppSpacing.md),
                    _Controls(
                      colors: colors,
                      state: _state,
                      pauseReason: _pauseReason,
                      busy: _busy,
                      onStart: () => _act((api, id) => api.startMission(id)),
                      onPause: () => _act((api, id) => api.pauseMission(id)),
                      onResume: () => _act((api, id) => api.resumeMission(id)),
                      onCancel: () => _act((api, id) => api.cancelMission(id)),
                    ),
                    if (_actionError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(_actionError!, style: TextStyle(color: colors.danger, fontSize: 12)),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Divider(color: colors.border, height: 1),
                    const SizedBox(height: AppSpacing.sm),
                    _buildPipelineHeader(colors, steps, nodes, isGraph),
                    const SizedBox(height: AppSpacing.xs),
                    Expanded(
                      child: isGraph
                          ? _buildGraphNodesPipeline(colors, nodes)
                          : _buildLinearStepsPipeline(colors, steps),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    AppColorsTheme colors,
    dynamic ros2,
    RobotTelemetryProvider telemetry,
    List<Map<String, dynamic>> pins,
    List<Map<String, dynamic>> steps,
    List<Map<String, dynamic>> nodes,
    bool isGraph,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _buildMissionHeader(colors, steps, nodes, isGraph),
        const SizedBox(height: AppSpacing.md),
        if (pins.isNotEmpty && ros2 != null) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.border),
            ),
            child: SizedBox(
              height: 200,
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
          const SizedBox(height: AppSpacing.md),
        ],
        _LiveTelemetryHUD(telemetry: telemetry, isRunning: running, colors: colors),
        const SizedBox(height: AppSpacing.md),
        _Controls(
          colors: colors,
          state: _state,
          pauseReason: _pauseReason,
          busy: _busy,
          onStart: () => _act((api, id) => api.startMission(id)),
          onPause: () => _act((api, id) => api.pauseMission(id)),
          onResume: () => _act((api, id) => api.resumeMission(id)),
          onCancel: () => _act((api, id) => api.cancelMission(id)),
        ),
        if (_actionError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_actionError!, style: TextStyle(color: colors.danger, fontSize: 12)),
        ],
        const SizedBox(height: AppSpacing.md),
        _buildPipelineHeader(colors, steps, nodes, isGraph),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 340,
          child: isGraph
              ? _buildGraphNodesPipeline(colors, nodes)
              : _buildLinearStepsPipeline(colors, steps),
        ),
      ],
    );
  }

  Widget _buildMissionHeader(
    AppColorsTheme colors,
    List<Map<String, dynamic>> steps,
    List<Map<String, dynamic>> nodes,
    bool isGraph,
  ) {
    final statusColor = _stateColor(_state, colors);
    final missionMap = widget.mission['map'] as String?;
    final isMismatch = missionMap != null && _currentMap != null && missionMap != _currentMap;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.mission['name'] as String? ?? _id,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: colors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                isGraph
                    ? '${nodes.length} logic nodes · Visual Workflow'
                    : '${steps.length} route waypoints',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              if (missionMap != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isMismatch ? colors.warning.withValues(alpha: 0.12) : colors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isMismatch ? colors.warning.withValues(alpha: 0.4) : colors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isMismatch ? Icons.warning_amber_rounded : Icons.map_outlined,
                          size: 11, color: isMismatch ? colors.warning : colors.primary),
                      const SizedBox(width: 4),
                      Text(
                        isMismatch ? 'Map: $missionMap (Inactive map: $_currentMap)' : 'Map: $missionMap',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isMismatch ? colors.warning : colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (running) ...[
                StatusPulseDot(color: statusColor, live: true, size: 8),
                const SizedBox(width: 6),
              ],
              Text(
                isLowBatteryPaused ? 'CHARGING' : _state.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPipelineHeader(
    AppColorsTheme colors,
    List<Map<String, dynamic>> steps,
    List<Map<String, dynamic>> nodes,
    bool isGraph,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          isGraph ? 'Execution Node Pipeline (${nodes.length})' : 'Waypoint Sequence (${steps.length})',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colors.textPrimary),
        ),
        if (running || paused)
          Text(
            _statusLine(),
            style: TextStyle(fontSize: 11, color: colors.primary, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }

  Widget _buildGraphNodesPipeline(AppColorsTheme colors, List<Map<String, dynamic>> nodes) {
    if (nodes.isEmpty) {
      return Center(child: Text('No nodes in graph', style: TextStyle(color: colors.textTertiary)));
    }

    final activeNodeId = _status?['active_node_id'] as String?;
    final activeNodeLabel = _status?['active_node_label'] as String?;

    return ListView.separated(
      itemCount: nodes.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, i) {
        final node = nodes[i];
        final id = node['id'] as String? ?? 'n_$i';
        final type = node['type'] as String? ?? '';
        final label = node['label'] as String? ?? type;

        final isCurrent = running && (id == activeNodeId || label == activeNodeLabel);

        return Card(
          elevation: isCurrent ? 2 : 0,
          margin: EdgeInsets.zero,
          color: isCurrent ? colors.primary.withValues(alpha: 0.1) : colors.surfaceSunken,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isCurrent ? colors.primary : colors.border,
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 13,
              backgroundColor: isCurrent ? colors.primary : colors.border,
              child: Icon(
                _nodeTypeIcon(type),
                size: 14,
                color: isCurrent ? colors.textOnPrimary : colors.textSecondary,
              ),
            ),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text(
              _nodeParamsSummary(node),
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: isCurrent
                ? StatusPulseDot(color: colors.primary, live: true, size: 8)
                : Text(type, style: TextStyle(color: colors.textTertiary, fontSize: 10)),
          ),
        );
      },
    );
  }

  Widget _buildLinearStepsPipeline(AppColorsTheme colors, List<Map<String, dynamic>> steps) {
    if (steps.isEmpty) {
      return Center(child: Text('No waypoints defined', style: TextStyle(color: colors.textTertiary)));
    }

    final stepIndex = _isThisMission ? (_status?['step_index'] as int? ?? -1) : -1;

    return ListView.separated(
      itemCount: steps.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, i) {
        final isCurrent = running && i == stepIndex;
        final isDone = _isThisMission && ((stepIndex > i && (running || paused)) || _state == 'completed');

        return Card(
          elevation: isCurrent ? 2 : 0,
          margin: EdgeInsets.zero,
          color: isCurrent ? colors.primary.withValues(alpha: 0.1) : colors.surfaceSunken,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isCurrent ? colors.primary : colors.border,
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 13,
              backgroundColor: isDone
                  ? colors.stateIdle
                  : isCurrent
                      ? colors.primary
                      : colors.border,
              child: isDone
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : Text('${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isCurrent ? colors.textOnPrimary : colors.textSecondary,
                      )),
            ),
            title: Text(missionStepSummary(steps[i]), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(missionStepIcon(steps[i]), size: 12, color: colors.textSecondary),
                const SizedBox(width: 4),
                Text(steps[i]['type'] as String? ?? '', style: TextStyle(color: colors.textSecondary, fontSize: 11)),
              ],
            ),
            trailing: isCurrent
                ? Icon(Icons.navigation_rounded, color: colors.primary, size: 18)
                : null,
          ),
        );
      },
    );
  }

  String _nodeParamsSummary(Map<String, dynamic> node) {
    final p = (node['params'] as Map?) ?? const {};
    final type = node['type'] as String? ?? '';
    if (type == 'navigate') return 'Target: ${p['waypoint'] ?? p['target_waypoint'] ?? '${p['x']}, ${p['y']}'}';
    if (type == 'wait') return 'Wait: ${p['duration'] ?? p['wait_sec'] ?? '5'}s';
    if (type == 'dock') return 'Recharging Bay';
    if (type == 'loop') return 'Repeat: ${p['count'] ?? '3'} times';
    if (type == 'condition') return 'Evaluate: ${p['expression'] ?? 'battery > 20%'}';
    return type;
  }

  static IconData _nodeTypeIcon(String type) => switch (type) {
        'navigate' => Icons.navigation_rounded,
        'wait' => Icons.hourglass_bottom_rounded,
        'dock' => Icons.ev_station_rounded,
        'undock' => Icons.logout_rounded,
        'condition' => Icons.call_split_rounded,
        'loop' => Icons.repeat_rounded,
        'ui_interaction' => Icons.touch_app_rounded,
        'patrol' => Icons.sync_rounded,
        'call_service' || 'call_action' => Icons.terminal_rounded,
        _ => Icons.circle_outlined,
      };

  String _statusLine() {
    final msg = _status?['message'] as String?;
    final stepIndex = (_status?['step_index'] as num?)?.toInt();
    final activeNode = _status?['active_node_label'] as String?;

    if (_state == 'completed') return 'Completed Successfully';
    if (_state == 'running') {
      if (activeNode != null && activeNode.isNotEmpty) return activeNode;
      if (stepIndex != null) return 'Step ${stepIndex + 1}';
      return 'Navigating...';
    }
    return msg ?? _state.toUpperCase();
  }

  List<Map<String, dynamic>> _resolveRoutePins(
    List<Map<String, dynamic>> steps,
    List<Map<String, dynamic>> nodes,
    bool isGraph,
  ) {
    final pins = <Map<String, dynamic>>[];
    int pinIndex = 1;

    if (!isGraph) {
      for (final step in steps) {
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
          pins.add({'name': '${pinIndex++}', 'x': x, 'y': y});
        }
      }
    } else {
      for (final node in nodes) {
        final type = node['type'] as String? ?? '';
        final p = (node['params'] as Map?) ?? const {};
        double? x, y;
        if (type == 'navigate') {
          final target = p['waypoint'] ?? p['target_waypoint'];
          if (target is String) {
            for (final loc in _locations ?? const <Map<String, dynamic>>[]) {
              if (loc['name'] == target) {
                x = (loc['x'] as num?)?.toDouble();
                y = (loc['y'] as num?)?.toDouble();
                break;
              }
            }
          } else {
            x = (p['x'] as num?)?.toDouble();
            y = (p['y'] as num?)?.toDouble();
          }
        } else if (type == 'dock' || type == 'undock') {
          x = _dockPose?.x;
          y = _dockPose?.y;
        }
        if (x != null && y != null) {
          pins.add({'name': '${pinIndex++}', 'x': x, 'y': y});
        }
      }
    }
    return pins;
  }

  Color _stateColor(String state, AppColorsTheme colors) => switch (state) {
        'running' => colors.stateIdle,
        'paused' => colors.warning,
        'completed' => colors.stateIdle,
        'failed' => colors.danger,
        _ => colors.textSecondary,
      };
}

/// Live Cockpit Telemetry HUD Card showing speed, battery, and execution stats.
class _LiveTelemetryHUD extends StatelessWidget {
  const _LiveTelemetryHUD({
    required this.telemetry,
    required this.isRunning,
    required this.colors,
  });

  final RobotTelemetryProvider telemetry;
  final bool isRunning;
  final AppColorsTheme colors;

  @override
  Widget build(BuildContext context) {
    final speed = telemetry.linearSpeedMps?.abs() ?? 0.0;
    final battery = telemetry.batteryPercentage ?? 100.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetric(
            icon: Icons.speed_rounded,
            color: colors.primary,
            label: 'Velocity',
            value: '${speed.toStringAsFixed(2)} m/s',
          ),
          Container(width: 1, height: 28, color: colors.border),
          _buildMetric(
            icon: battery < 20 ? Icons.battery_alert_rounded : Icons.battery_charging_full_rounded,
            color: battery < 20 ? colors.danger : colors.stateIdle,
            label: 'Battery SOC',
            value: '${battery.round()}%',
          ),
          Container(width: 1, height: 28, color: colors.border),
          _buildMetric(
            icon: Icons.memory_rounded,
            color: const Color(0xFF00E5FF),
            label: 'Control Mode',
            value: isRunning ? 'Auto Nav2' : 'Standby',
          ),
        ],
      ),
    );
  }

  Widget _buildMetric({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colors.textPrimary)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: colors.textTertiary)),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.colors,
    required this.state,
    this.pauseReason,
    required this.busy,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final AppColorsTheme colors;
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
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.warning),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(Icons.pause_rounded, color: colors.warning),
              label: Text('Pause Mission', style: TextStyle(color: colors.warning, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton.icon(
              onPressed: busy ? null : onCancel,
              style: FilledButton.styleFrom(
                backgroundColor: colors.danger,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Abort Mission', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    }
    if (state == 'paused') {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: busy ? null : onResume,
              style: FilledButton.styleFrom(
                backgroundColor: colors.stateIdle,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Resume Mission', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onCancel,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.danger.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: Icon(Icons.stop_rounded, color: colors.danger),
              label: Text('Abort Mission', style: TextStyle(color: colors.danger)),
            ),
          ),
        ],
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      onPressed: busy ? null : onStart,
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: const Text('Start Mission Execution', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }
}
