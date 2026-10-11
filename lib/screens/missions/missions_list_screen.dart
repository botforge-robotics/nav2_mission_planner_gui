import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/fleet_provider.dart';
import '../../services/sdk_api_service.dart';
import '../settings/fleet_settings_screen.dart';
import '../../widgets/fleet/dispatch_fleet_task_dialog.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/mission_step_summary.dart';
import '../../widgets/design/fade_in.dart';
import '../../widgets/design/skeleton.dart';
import '../../widgets/design/status_pulse.dart';
import 'mission_detail_screen.dart';
import 'mission_editor_screen.dart';
import 'schedules_list_screen.dart';
import 'graph/mission_graph_editor_screen.dart';

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
  List<Map<String, dynamic>>? _schedules;
  String? _currentMap;
  SdkApiException? _error;
  bool _requested = false;
  SdkApiService? _api;
  Timer? _poll;
  int _selectedTab = 0; // 0 = Tasks Overview (Open-RMF Table), 1 = Mission Library
  String _taskFilter = 'all'; // 'all', 'active', 'queued', 'scheduled', 'history'

  @override
  void initState() {
    super.initState();
    // Missions and Open-RMF tasks are polled every 4s to keep queued, active,
    // and scheduled tasks live and responsive across the fleet.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    setState(() => _error = null);
    if (api != null) {
      try {
        final results = await Future.wait([
          api.listMissions(),
          api.missionStatus(),
          api.getCurrentMap(),
          api.listSchedules(),
        ]);
        if (!mounted) return;
        setState(() {
          _missions = results[0] as List<Map<String, dynamic>>?;
          _runnerStatus = results[1] as Map<String, dynamic>?;
          _currentMap = results[2] as String?;
          _schedules = results[3] as List<Map<String, dynamic>>?;
        });
      } on SdkApiException catch (e) {
        if (!mounted) return;
        setState(() => _error = e);
      }
    }
    if (mounted) {
      final fleet = context.read<FleetProvider>();
      if (fleet.isFleetMode) {
        fleet.refreshRobotsOnly();
      }
    }
  }

  Future<void> _createMission() async {
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;
    if (isDesktop) {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const MissionGraphEditorScreen()),
      );
      if (created == true) _load();
    } else {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const MissionEditorScreen()),
      );
      if (created == true) _load();
    }
  }

  Future<void> _deleteMission(Map<String, dynamic> mission) async {
    final api = _api;
    if (api == null) return;
    final id = mission['id'] as String;
    final name = mission['name'] as String? ?? id;

    // Check if currently active
    final activeId = _runnerStatus?['mission_id'] as String?;
    final activeState = _runnerStatus?['state'] as String?;
    final isRunning = activeState == 'running' || activeState == 'paused' || activeState == 'charging_paused';
    if (id == activeId && isRunning) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 36),
          title: const Text('Mission is Currently Active'),
          content: Text('Cannot delete "$name" while it is ${activeState ?? "running"}.\nPlease cancel or abort the mission before deleting it.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Check if referenced by other missions via switch_mission / redirect_mission
    final referencingMissions = <String>[];
    for (final m in (_missions ?? const [])) {
      if (m['id'] == id) continue;
      final nodes = (m['nodes'] as List? ?? const []).cast<Map<String, dynamic>>();
      for (final node in nodes) {
        if (node['type'] == 'switch_mission' || node['type'] == 'redirect_mission') {
          final target = node['params']?['target_mission_id'] ?? node['params']?['mission_id'];
          if (target == id) {
            referencingMissions.add(m['name'] as String? ?? m['id'] as String);
            break;
          }
        }
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          referencingMissions.isNotEmpty ? Icons.warning_rounded : Icons.delete_outline_rounded,
          color: AppColors.danger,
          size: 36,
        ),
        title: Text(referencingMissions.isNotEmpty
            ? 'Warning: Referenced Mission'
            : 'Delete Mission?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (referencingMissions.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This mission is referenced by other missions:\n• ${referencingMissions.join("\n• ")}\n\nDeleting it may break workflows.',
                          style: const TextStyle(fontSize: 12, color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Text(
                'Are you sure you want to permanently delete "$name"?',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'This will remove the mission permanently from the robot. This action cannot be undone.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Delete Mission'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await api.deleteMission(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mission "$name" deleted'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _load();
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete mission: ${e.message}'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

    final conn = context.watch<ConnectionProvider>();
    final fleet = context.watch<FleetProvider>();
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;
    final hasConnection = conn.robot?.ip != null || fleet.isFleetMode;

    final allTasks = _buildUnifiedTasks(fleet, conn);
    final filteredTasks = _filterTasks(allTasks);

    return Scaffold(
      appBar: AppBar(
        title: Text(isDesktop ? 'Missions & Task Overview' : 'Missions'),
        actions: [
          if (fleet.isFleetMode) ...[
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Dispatch Task'),
                onPressed: () => DispatchFleetTaskDialog.show(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.hub_rounded, size: 16, color: Colors.blue),
                label: Text('Fleet (${fleet.robots.length})'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FleetSettingsScreen()),
                ),
              ),
            ),
          ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.account_tree_outlined, size: 18),
                label: const Text('Workflow Editor'),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const MissionGraphEditorScreen()),
                  );
                  _load();
                },
              ),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Workflow Editor',
              icon: const Icon(Icons.account_tree_outlined),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const MissionGraphEditorScreen()),
                );
                _load();
              },
            ),
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
          : (_selectedTab == 0 && fleet.isFleetMode
              ? FloatingActionButton.extended(
                  onPressed: () => DispatchFleetTaskDialog.show(context),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Dispatch Task'),
                )
              : FloatingActionButton.extended(
                  onPressed: _createMission,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Mission Editor'),
                )),
      body: SafeArea(
        child: !hasConnection
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hub_outlined, size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'No active robot or fleet connected',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Connect to a robot or configure fleet server settings to manage tasks.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FleetSettingsScreen()),
                      ),
                      child: const Text('Open Fleet Settings'),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  // Top Tab Switcher: Tasks Overview vs Mission Library
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        segments: [
                          ButtonSegment<int>(
                            value: 0,
                            icon: const Icon(Icons.table_chart_outlined, size: 18),
                            label: Text(
                              isDesktop
                                  ? 'Tasks Overview (Open-RMF) [${allTasks.length}]'
                                  : 'Tasks (${allTasks.length})',
                            ),
                          ),
                          ButtonSegment<int>(
                            value: 1,
                            icon: const Icon(Icons.account_tree_outlined, size: 18),
                            label: Text(
                              isDesktop
                                  ? 'Mission & Visual Graph Library [${_missions?.length ?? 0}]'
                                  : 'Missions (${_missions?.length ?? 0})',
                            ),
                          ),
                        ],
                        selected: {_selectedTab},
                        onSelectionChanged: (set) {
                          setState(() => _selectedTab = set.first);
                        },
                      ),
                    ),
                  ),

                  Expanded(
                    child: _selectedTab == 0
                        ? _buildOpenRmfTasksView(context, filteredTasks, allTasks, fleet, conn, isDesktop)
                        : _buildMissionLibraryView(context, isDesktop),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMissionLibraryView(BuildContext context, bool isDesktop) {
    if (_missions == null && _error == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: SkeletonList(),
      );
    }

    return _Body(
      missions: _missions,
      runnerStatus: _runnerStatus,
      currentMap: _currentMap,
      error: _error,
      onRetry: _load,
      onCreateMission: _createMission,
      onDelete: _deleteMission,
      onEdit: (mission) async {
        final isGraph = mission['type'] == 'graph' || mission.containsKey('nodes');
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => (isGraph || isDesktop)
                ? MissionGraphEditorScreen(existingMission: mission)
                : MissionEditorScreen(existing: mission),
          ),
        );
        if (changed == true) _load();
      },
      onOpen: (mission) async {
        final isGraph = mission['type'] == 'graph' || mission.containsKey('nodes');
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => isGraph
                ? MissionGraphEditorScreen(existingMission: mission)
                : MissionDetailScreen(mission: mission),
          ),
        );
        if (changed == true) _load();
      },
    );
  }

  List<_RmfTaskEntry> _filterTasks(List<_RmfTaskEntry> tasks) {
    if (_taskFilter == 'all') return tasks;
    return tasks.where((t) => t.statusGroup == _taskFilter).toList();
  }

  List<_RmfTaskEntry> _buildUnifiedTasks(FleetProvider fleet, ConnectionProvider conn) {
    final list = <_RmfTaskEntry>[];

    // 1. Tasks from Fleet Server
    for (final m in fleet.activeMissions) {
      final id = m['id'] as String? ?? m['task_id'] as String? ?? 'task_${m.hashCode}';
      final name = m['name'] as String? ?? m['description']?['category'] as String? ?? id;
      final category = m['category'] as String? ?? m['type'] as String? ?? 'dispatch';
      final assignedRobot = m['robot'] as String? ?? m['robot_name'] as String? ?? m['assigned_robot'] as String?;
      final rawStatus = (m['status'] as String? ?? m['state'] as String? ?? 'queued').toLowerCase();
      final level = m['level'] as String? ?? m['level_name'] as String? ?? m['floor'] as String?;
      final timeStr = m['submitted_time'] as String? ?? m['start_time'] as String? ?? m['created_at'] as String?;
      final progress = (m['progress'] as num?)?.toDouble() ?? (rawStatus == 'completed' || rawStatus == 'succeeded' ? 1.0 : 0.0);

      list.add(_RmfTaskEntry(
        id: id,
        name: name,
        category: category,
        assignedRobot: assignedRobot,
        rawStatus: rawStatus,
        statusGroup: _classifyStatus(rawStatus),
        level: level,
        timestamp: timeStr,
        progress: progress,
        rawPayload: m,
        source: _TaskSource.fleet,
      ));
    }

    // 2. Scheduled tasks from SdkApiService / local scheduler
    if (_schedules != null) {
      for (final s in _schedules!) {
        final id = s['id'] as String? ?? 'sched_${s.hashCode}';
        final missionId = s['mission_id'] as String? ?? 'Mission';
        final name = s['name'] as String? ?? 'Scheduled: $missionId';
        final enabled = s['enabled'] != false;
        final hour = s['hour'] as int? ?? 0;
        final minute = s['minute'] as int? ?? 0;
        final repeat = s['repeat'] as String? ?? 'once';
        final timeStr = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} ($repeat)';

        list.add(_RmfTaskEntry(
          id: id,
          name: name,
          category: 'scheduled_mission',
          assignedRobot: conn.robot?.name ?? 'Assigned Robot',
          rawStatus: enabled ? 'scheduled' : 'disabled',
          statusGroup: 'scheduled',
          level: _currentMap,
          timestamp: timeStr,
          progress: 0.0,
          rawPayload: s,
          source: _TaskSource.schedule,
        ));
      }
    }

    // 3. Local robot active runner status (if in direct robot mode)
    final activeId = _runnerStatus?['mission_id'] as String?;
    final activeState = _runnerStatus?['state'] as String?;
    if (activeId != null && activeState != null && activeState != 'idle') {
      final alreadyInList = list.any((t) => t.id == activeId);
      if (!alreadyInList) {
        final missionObj = _missions?.firstWhere((m) => m['id'] == activeId, orElse: () => const {});
        final name = missionObj?['name'] as String? ?? activeId;
        final rawStatus = activeState.toLowerCase();
        final currentStep = _runnerStatus?['current_step'] as int? ?? 0;
        final totalSteps = (missionObj?['steps'] as List?)?.length ?? 1;
        final progress = totalSteps > 0 ? (currentStep / totalSteps).clamp(0.0, 1.0) : 0.0;

        list.add(_RmfTaskEntry(
          id: activeId,
          name: name,
          category: 'direct_mission',
          assignedRobot: conn.robot?.name ?? 'Local AMR',
          rawStatus: rawStatus,
          statusGroup: _classifyStatus(rawStatus),
          level: _currentMap,
          timestamp: 'Live Active',
          progress: progress,
          rawPayload: _runnerStatus!,
          source: _TaskSource.localRunner,
        ));
      }
    }

    return list;
  }

  static String _classifyStatus(String raw) {
    switch (raw) {
      case 'running':
      case 'underway':
      case 'executing':
      case 'active':
        return 'active';
      case 'pending':
      case 'queued':
      case 'standby':
      case 'paused':
        return 'queued';
      case 'scheduled':
        return 'scheduled';
      case 'succeeded':
      case 'completed':
      case 'failed':
      case 'canceled':
      case 'cancelled':
      case 'aborted':
      case 'killed':
        return 'history';
      default:
        return 'active';
    }
  }

  Widget _buildOpenRmfTasksView(
    BuildContext context,
    List<_RmfTaskEntry> tasks,
    List<_RmfTaskEntry> allTasks,
    FleetProvider fleet,
    ConnectionProvider conn,
    bool isDesktop,
  ) {
    final activeCount = allTasks.where((t) => t.statusGroup == 'active').length;
    final queuedCount = allTasks.where((t) => t.statusGroup == 'queued').length;
    final scheduledCount = allTasks.where((t) => t.statusGroup == 'scheduled').length;
    final historyCount = allTasks.where((t) => t.statusGroup == 'history').length;

    return Column(
      children: [
        // Filter Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Row(
            children: [
              _buildFilterChip('all', 'All (${allTasks.length})', null),
              const SizedBox(width: AppSpacing.xs),
              _buildFilterChip('active', 'Active ($activeCount)', AppColors.stateExecuting),
              const SizedBox(width: AppSpacing.xs),
              _buildFilterChip('queued', 'Queued ($queuedCount)', AppColors.warning),
              const SizedBox(width: AppSpacing.xs),
              _buildFilterChip('scheduled', 'Scheduled ($scheduledCount)', const Color(0xFFB388FF)),
              const SizedBox(width: AppSpacing.xs),
              _buildFilterChip('history', 'History ($historyCount)', AppColors.textSecondary),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                tooltip: 'Refresh tasks',
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: _load,
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        Expanded(
          child: tasks.isEmpty
              ? _buildEmptyTasksState(fleet)
              : (isDesktop ? _buildTasksDataTable(context, tasks, fleet) : _buildTasksCardsList(context, tasks, fleet)),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String filterKey, String label, Color? color) {
    final isSelected = _taskFilter == filterKey;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _taskFilter = filterKey);
      },
      avatar: color != null
          ? StatusPulseDot(
              color: color,
              live: filterKey == 'active',
              size: 8,
            )
          : null,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
      ),
    );
  }

  Widget _buildTasksDataTable(BuildContext context, List<_RmfTaskEntry> tasks, FleetProvider fleet) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppColors.surfaceSunken),
            horizontalMargin: AppSpacing.md,
            columnSpacing: AppSpacing.lg,
            columns: const [
              DataColumn(label: Text('TASK ID / NAME', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('CATEGORY', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('ASSIGNED ROBOT', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('LEVEL', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('PROGRESS', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('TIME', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: tasks.map((task) {
              return DataRow(
                cells: [
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(task.id, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                  DataCell(_buildCategoryBadge(task.category)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.smart_toy_outlined, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          task.assignedRobot ?? 'Unassigned / Auto',
                          style: TextStyle(
                            fontStyle: task.assignedRobot == null ? FontStyle.italic : FontStyle.normal,
                            color: task.assignedRobot == null ? AppColors.textTertiary : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(_buildStatusBadge(task)),
                  DataCell(Text(task.level ?? '—', style: const TextStyle(fontSize: 12))),
                  DataCell(
                    SizedBox(
                      width: 90,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: task.statusGroup == 'history' && task.rawStatus == 'completed'
                                ? 1.0
                                : (task.progress > 0 ? task.progress : null),
                            backgroundColor: AppColors.surfaceSunken,
                            color: task.statusGroup == 'active' ? AppColors.stateExecuting : AppColors.primary,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(task.progress * 100).toInt()}%',
                            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(Text(task.timestamp ?? '—', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (task.statusGroup == 'active' || task.statusGroup == 'queued')
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.danger),
                            tooltip: 'Cancel Task',
                            onPressed: () => _cancelTask(task, fleet),
                          ),
                        IconButton(
                          icon: const Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
                          tooltip: 'Task Details',
                          onPressed: () => _showTaskDetailsDialog(task),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTasksCardsList(BuildContext context, List<_RmfTaskEntry> tasks, FleetProvider fleet) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final task = tasks[i];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showTaskDetailsDialog(task),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildCategoryBadge(task.category),
                      const SizedBox(width: AppSpacing.xs),
                      _buildStatusBadge(task),
                      const Spacer(),
                      if (task.statusGroup == 'active' || task.statusGroup == 'queued')
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.danger),
                          tooltip: 'Cancel Task',
                          onPressed: () => _cancelTask(task, fleet),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(task.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('ID: ${task.id}', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Icon(Icons.smart_toy_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          task.assignedRobot ?? 'Auto-Assigned',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                      if (task.level != null) ...[
                        const Icon(Icons.layers_outlined, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(task.level!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: task.statusGroup == 'history' && task.rawStatus == 'completed'
                          ? 1.0
                          : (task.progress > 0 ? task.progress : null),
                      backgroundColor: AppColors.surfaceSunken,
                      color: task.statusGroup == 'active' ? AppColors.stateExecuting : AppColors.primary,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryBadge(String category) {
    final cat = category.toLowerCase();
    IconData icon = Icons.task_alt_outlined;
    Color color = AppColors.primary;

    if (cat.contains('patrol')) {
      icon = Icons.repeat_rounded;
      color = const Color(0xFF00E5FF);
    } else if (cat.contains('delivery')) {
      icon = Icons.local_shipping_outlined;
      color = const Color(0xFFFF9100);
    } else if (cat.contains('clean')) {
      icon = Icons.cleaning_services_outlined;
      color = const Color(0xFF00E676);
    } else if (cat.contains('charge')) {
      icon = Icons.battery_charging_full_rounded;
      color = AppColors.warning;
    } else if (cat.contains('sched')) {
      icon = Icons.alarm_rounded;
      color = const Color(0xFFB388FF);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            category.toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(_RmfTaskEntry task) {
    Color color;
    String label = task.rawStatus.toUpperCase();
    bool live = false;

    switch (task.statusGroup) {
      case 'active':
        color = AppColors.stateExecuting;
        live = true;
        break;
      case 'queued':
        color = AppColors.warning;
        break;
      case 'scheduled':
        color = const Color(0xFFB388FF);
        break;
      case 'history':
        color = (task.rawStatus == 'completed' || task.rawStatus == 'succeeded')
            ? AppColors.stateIdle
            : AppColors.danger;
        break;
      default:
        color = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: StatusPulseDot(color: color, live: true, size: 6),
            ),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTasksState(FleetProvider fleet) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.assignment_outlined, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No ${_taskFilter == 'all' ? '' : '$_taskFilter '}tasks found',
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Dispatch a fleet task or schedule recurring missions to view status.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (fleet.isFleetMode)
            FilledButton.icon(
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Dispatch Fleet Task'),
              onPressed: () => DispatchFleetTaskDialog.show(context),
            ),
        ],
      ),
    );
  }

  Future<void> _cancelTask(_RmfTaskEntry task, FleetProvider fleet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 36),
        title: const Text('Cancel Task?'),
        content: Text('Are you sure you want to cancel "${task.name}" (${task.id})?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No, keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (task.source == _TaskSource.fleet && fleet.api != null) {
        await fleet.api!.cancelRmfTask(task.id);
      } else if (task.source == _TaskSource.localRunner && _api != null) {
        await _api!.cancelMission(task.id);
      } else if (task.source == _TaskSource.schedule && _api != null) {
        await _api!.deleteSchedule(task.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Task "${task.name}" canceled')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel task: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  void _showTaskDetailsDialog(_RmfTaskEntry task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            _buildCategoryBadge(task.category),
            const SizedBox(width: 8),
            Expanded(
              child: Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Task ID', task.id),
                _detailRow('Status', task.rawStatus.toUpperCase()),
                _detailRow('Status Group', task.statusGroup.toUpperCase()),
                _detailRow('Assigned AMR', task.assignedRobot ?? 'Automatic auction'),
                _detailRow('Level / Map', task.level ?? 'Unspecified'),
                _detailRow('Timestamp', task.timestamp ?? 'N/A'),
                _detailRow('Progress', '${(task.progress * 100).toInt()}%'),
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                const Text('Raw Payload:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    task.rawPayload.toString(),
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

enum _TaskSource {
  fleet,
  schedule,
  localRunner,
}

class _RmfTaskEntry {
  final String id;
  final String name;
  final String category;
  final String? assignedRobot;
  final String rawStatus;
  final String statusGroup; // 'active', 'queued', 'scheduled', 'history'
  final String? level;
  final String? timestamp;
  final double progress;
  final Map<String, dynamic> rawPayload;
  final _TaskSource source;

  const _RmfTaskEntry({
    required this.id,
    required this.name,
    required this.category,
    this.assignedRobot,
    required this.rawStatus,
    required this.statusGroup,
    this.level,
    this.timestamp,
    required this.progress,
    required this.rawPayload,
    required this.source,
  });
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
    required this.onDelete,
  });

  final List<Map<String, dynamic>>? missions;
  final Map<String, dynamic>? runnerStatus;
  final String? currentMap;
  final SdkApiException? error;
  final VoidCallback onRetry;
  final VoidCallback onCreateMission;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>) onOpen;
  final void Function(Map<String, dynamic>) onDelete;

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
              icon: Icon(Breakpoints.of(context) == DeviceClass.desktop
                  ? Icons.account_tree_outlined
                  : Icons.edit_note_rounded),
              label: Text(Breakpoints.of(context) == DeviceClass.desktop
                  ? 'Open Workflow Editor'
                  : 'Mission Editor'),
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
          final isGraph = mission['type'] == 'graph' || mission.containsKey('nodes');
          final steps = (mission['steps'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          final nodes = (mission['nodes'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          final isActive = id == activeId && isRunning;
          final isCompleted = id == activeId && activeState == 'completed';
          final status =
              isActive ? activeState : (isCompleted ? 'completed' : null);
          final loopForever = mission['loop_forever'] == true;
          final loopCount = (mission['loop_count'] as num?)?.toInt() ?? 1;
          final color =
              status == null ? (isGraph ? const Color(0xFF00E5FF) : AppColors.primary) : _statusColor(status);

          var subtitle = isGraph
              ? '${nodes.length} node${nodes.length == 1 ? '' : 's'} · Visual Graph'
              : '${steps.length} step${steps.length == 1 ? '' : 's'}';
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
                      const SizedBox(width: AppSpacing.xs),
                      if (status != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (status == 'running')
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: StatusPulseDot(
                                    color: _statusColor(status),
                                    live: true,
                                    size: 6,
                                  ),
                                ),
                              Text(
                                isActive && isLowBatteryPaused
                                    ? '⚡ CHARGING'
                                    : status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _statusColor(status),
                                ),
                              ),
                            ],
                          ),
                        ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded,
                            size: 20, color: AppColors.textSecondary),
                        tooltip: 'Mission actions',
                        onSelected: (action) {
                          if (action == 'open') onOpen(mission);
                          if (action == 'edit') onEdit(mission);
                          if (action == 'delete') onDelete(mission);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'open',
                            child: Row(
                              children: [
                                Icon(Icons.play_arrow_rounded,
                                    size: 18, color: AppColors.success),
                                SizedBox(width: 8),
                                Text('View / Run'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined,
                                    size: 18, color: AppColors.primary),
                                SizedBox(width: 8),
                                Text('Edit Mission'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded,
                                    size: 18, color: AppColors.danger),
                                SizedBox(width: 8),
                                Text('Delete Mission',
                                    style: TextStyle(color: AppColors.danger)),
                              ],
                            ),
                          ),
                        ],
                      ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final isNarrow = availableWidth < 680;
          final maxCrossAxisExtent = isNarrow ? availableWidth : 440.0;
          final mainAxisExtent = isNarrow ? 218.0 : 224.0;

          return CustomScrollView(
            slivers: [
              if (isRunning &&
                  activeMission != null &&
                  activeMission.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Card(
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
                child: LayoutBuilder(
                  builder: (context, bannerConstraints) {
                    final isCompact = bannerConstraints.maxWidth < 640;

                    return isCompact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  StatusPulseDot(
                                    color: _statusColor(activeState),
                                    live: activeState == 'running',
                                    size: 10,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Wrap(
                                      spacing: AppSpacing.sm,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          activeMission['name'] as String? ??
                                              activeId!,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16),
                                        ),
                                        Chip(
                                          avatar: isLowBattery
                                              ? const Icon(Icons.bolt_rounded,
                                                  size: 14,
                                                  color: AppColors.warning)
                                              : null,
                                          label: Text(
                                              isLowBattery
                                                  ? 'PAUSED (CHARGING)'
                                                  : activeState.toUpperCase(),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                          backgroundColor:
                                              _statusColor(activeState)
                                                  .withValues(alpha: 0.15),
                                          labelStyle: TextStyle(
                                              color: _statusColor(activeState)),
                                          side: BorderSide.none,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
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
                                  final totalSteps = (activeMission['steps']
                                          as List? ??
                                      []).length;
                                  final stepIdx = (runnerStatus?['step_index']
                                          as int? ??
                                      0);
                                  final currentStepNum = (stepIdx + 1)
                                      .clamp(1, totalSteps > 0 ? totalSteps : 1);
                                  return Text(
                                    'Step $currentStepNum of $totalSteps currently executing',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary),
                                  );
                                }),
                              const SizedBox(height: AppSpacing.sm),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () => onOpen(activeMission),
                                  icon: const Icon(Icons.fullscreen_rounded,
                                      size: 18),
                                  label: const Text('View Live Execution'),
                                ),
                              ),
                            ],
                          )
                        : Row(
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
                                    Wrap(
                                      spacing: AppSpacing.sm,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          activeMission['name'] as String? ??
                                              activeId!,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16),
                                        ),
                                        Chip(
                                          avatar: isLowBattery
                                              ? const Icon(Icons.bolt_rounded,
                                                  size: 14,
                                                  color: AppColors.warning)
                                              : null,
                                          label: Text(
                                              isLowBattery
                                                  ? 'PAUSED (CHARGING)'
                                                  : activeState.toUpperCase(),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold)),
                                          backgroundColor:
                                              _statusColor(activeState)
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
                                            (activeMission['steps'] as List? ??
                                                    [])
                                                .length;
                                        final stepIdx =
                                            (runnerStatus?['step_index']
                                                    as int? ??
                                                0);
                                        final currentStepNum = (stepIdx + 1)
                                            .clamp(
                                                1,
                                                totalSteps > 0
                                                    ? totalSteps
                                                    : 1);
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
                              const SizedBox(width: AppSpacing.md),
                              FilledButton.icon(
                                onPressed: () => onOpen(activeMission),
                                icon: const Icon(Icons.fullscreen_rounded,
                                    size: 18),
                                label: const Text('View Live Execution'),
                              ),
                            ],
                          );
                  },
                ),
              ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
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
                    ],
                  ),
                  Chip(
                    avatar: const Icon(Icons.tune_rounded,
                        size: 14, color: AppColors.primary),
                    label: Text('Mission Runner: ${activeState ?? 'idle'}'),
                    backgroundColor: AppColors.surface,
                  ),
                ],
              ),
            ),
          ),
          SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxCrossAxisExtent,
              mainAxisExtent: mainAxisExtent,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                    final mission = missions[i];
                    final id = mission['id'] as String;
                    final isGraph = mission['type'] == 'graph' || mission.containsKey('nodes');
                    final steps = (mission['steps'] as List? ?? const [])
                        .cast<Map<String, dynamic>>();
                    final nodes = (mission['nodes'] as List? ?? const [])
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
                        status == null ? (isGraph ? const Color(0xFF00E5FF) : AppColors.primary) : _statusColor(status);

                    var subtitle = isGraph
                        ? '${nodes.length} node${nodes.length == 1 ? '' : 's'} · Visual Graph'
                        : '${steps.length} step${steps.length == 1 ? '' : 's'}';
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
                        child: LayoutBuilder(
                          builder: (context, cardConstraints) {
                            final isCompactCard = cardConstraints.maxWidth < 360;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: color.withValues(alpha: 0.12),
                                      child: Icon(
                                          isGraph ? Icons.account_tree_outlined : Icons.route_rounded,
                                          color: color,
                                          size: 20),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
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
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
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
                                                  Flexible(
                                                    child: Text(
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
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (status != null) ...[
                                      const SizedBox(width: AppSpacing.xs),
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
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                        backgroundColor: _statusColor(status)
                                            .withValues(alpha: 0.12),
                                        labelStyle: TextStyle(
                                            color: _statusColor(status)),
                                        side: BorderSide.none,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                const Text(
                                  'Step Route:',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 2),
                                _StepPreviewRow(steps: steps),
                                const Spacer(),
                                Row(
                                  children: [
                                    if (isCompactCard) ...[
                                      Tooltip(
                                        message: 'Edit Mission',
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            minimumSize: const Size(36, 36),
                                          ),
                                          onPressed: () => onEdit(mission),
                                          child: const Icon(Icons.edit_outlined, size: 16),
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Tooltip(
                                        message: 'Delete Mission',
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.danger,
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            minimumSize: const Size(36, 36),
                                            side: BorderSide(
                                              color: AppColors.danger.withValues(alpha: 0.35),
                                            ),
                                          ),
                                          onPressed: () => onDelete(mission),
                                          child: const Icon(Icons.delete_outline_rounded, size: 16),
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      Expanded(
                                        child: FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            minimumSize: const Size(0, 36),
                                          ),
                                          onPressed: () => onOpen(mission),
                                          icon: Icon(
                                              isActive
                                                  ? Icons.open_in_new_rounded
                                                  : Icons.play_arrow_rounded,
                                              size: 16),
                                          label: Text(
                                            isActive ? 'View' : 'Run',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      OutlinedButton.icon(
                                        onPressed: () => onEdit(mission),
                                        icon: const Icon(Icons.edit_outlined, size: 16),
                                        label: const Text('Edit'),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.danger,
                                          side: BorderSide(
                                            color: AppColors.danger.withValues(alpha: 0.35),
                                          ),
                                        ),
                                        onPressed: () => onDelete(mission),
                                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                        label: const Text('Delete'),
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
                                          label: Text(
                                            isActive
                                                ? 'View Live'
                                                : 'Details & Run',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    );
                  },
                  childCount: missions.length,
                ),
              ),
            ],
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

  static const _maxShown = 6;

  @override
  Widget build(BuildContext context) {
    final shown = steps.take(_maxShown).toList();
    final overflow = steps.length - shown.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }
}
