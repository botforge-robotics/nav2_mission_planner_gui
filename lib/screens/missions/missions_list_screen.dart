import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/mission_step_summary.dart';
import '../../widgets/design/skeleton.dart';
import '../../widgets/design/status_pulse.dart';
import 'mission_detail_screen.dart';
import 'mission_editor_screen.dart';
import 'schedules_list_screen.dart';
import 'graph/mission_graph_editor_screen.dart';

enum _MissionCategoryFilter { all, graph, linear, active }

/// Mission Catalog & Autonomous Workflow Control Center.
/// Displays visual graph workflows and linear step sequences with live execution
/// telemetry, search, filtering, and instant operator controls.
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

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _MissionCategoryFilter _categoryFilter = _MissionCategoryFilter.all;
  String? _selectedMapFilter; // null = all maps

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final q = _searchController.text.trim().toLowerCase();
      if (q != _searchQuery) {
        setState(() => _searchQuery = q);
      }
    });
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) return;
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
        _error = null;
      });
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _createMission({bool forceGraph = false, bool forceLinear = false}) async {
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;
    final bool openGraph = forceGraph || (!forceLinear && isDesktop);

    if (openGraph) {
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

  Future<void> _controlActiveMission(String action, String missionId) async {
    final api = _api;
    if (api == null) return;
    try {
      if (action == 'pause') await api.pauseMission(missionId);
      if (action == 'resume') await api.resumeMission(missionId);
      if (action == 'cancel') await api.cancelMission(missionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mission ${action == 'cancel' ? 'aborted' : '${action}d'} successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to $action mission: $e'),
          backgroundColor: AppColors.of(context).danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteMission(Map<String, dynamic> mission) async {
    final api = _api;
    if (api == null) return;
    final colors = AppColors.of(context);
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
          icon: Icon(Icons.warning_amber_rounded, color: colors.warning, size: 36),
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
          color: colors.danger,
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
                    color: colors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: colors.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This mission is referenced by other missions:\n• ${referencingMissions.join("\n• ")}\n\nDeleting it may break workflows.',
                          style: TextStyle(fontSize: 12, color: colors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Text(
                'Are you sure you want to permanently delete "$name"?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'This will remove the mission permanently from the robot storage.',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
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
            style: FilledButton.styleFrom(backgroundColor: colors.danger),
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
          behavior: SnackBarBehavior.floating,
        ),
      );
      _load();
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete mission: ${e.message}'),
          backgroundColor: colors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(isDesktop ? 'Autonomous Missions & Tasks' : 'Missions'),
        actions: [
          IconButton(
            tooltip: 'Refresh missions',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                side: BorderSide(color: colors.border),
              ),
              icon: Icon(Icons.alarm_rounded, size: 18, color: colors.primary),
              label: Text('Scheduler', style: TextStyle(color: colors.textPrimary, fontSize: 13)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SchedulesListScreen()),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: PopupMenuButton<String>(
              tooltip: 'Create New Mission',
              onSelected: (mode) {
                if (mode == 'graph') _createMission(forceGraph: true);
                if (mode == 'linear') _createMission(forceLinear: true);
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'graph',
                  child: Row(
                    children: [
                      const Icon(Icons.account_tree_outlined, size: 18, color: Color(0xFF00E5FF)),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Visual Graph Workflow', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Logic nodes, loops, conditions, AI', style: TextStyle(color: colors.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'linear',
                  child: Row(
                    children: [
                      Icon(Icons.route_rounded, size: 18, color: colors.primary),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sequential Route', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Quick waypoint-by-waypoint list', style: TextStyle(color: colors.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor: colors.primary,
                  foregroundColor: colors.textOnPrimary,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Mission'),
                onPressed: null, // triggers PopupMenuButton
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: isDesktop
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _createMission(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Mission'),
            ),
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
                    Text('Connect to your NavPro AMR to view and execute missions.', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                  ],
                ),
              )
            : _Body(
                missions: _missions,
                runnerStatus: _runnerStatus,
                currentMap: _currentMap,
                error: _error,
                searchQuery: _searchQuery,
                searchController: _searchController,
                categoryFilter: _categoryFilter,
                selectedMapFilter: _selectedMapFilter,
                onSelectCategory: (cat) => setState(() => _categoryFilter = cat),
                onSelectMapFilter: (m) => setState(() => _selectedMapFilter = m),
                onRetry: _load,
                onCreateMission: _createMission,
                onDelete: _deleteMission,
                onControlMission: _controlActiveMission,
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
    required this.searchQuery,
    required this.searchController,
    required this.categoryFilter,
    required this.selectedMapFilter,
    required this.onSelectCategory,
    required this.onSelectMapFilter,
    required this.onRetry,
    required this.onCreateMission,
    required this.onEdit,
    required this.onOpen,
    required this.onDelete,
    required this.onControlMission,
  });

  final List<Map<String, dynamic>>? missions;
  final Map<String, dynamic>? runnerStatus;
  final String? currentMap;
  final SdkApiException? error;
  final String searchQuery;
  final TextEditingController searchController;
  final _MissionCategoryFilter categoryFilter;
  final String? selectedMapFilter;
  final ValueChanged<_MissionCategoryFilter> onSelectCategory;
  final ValueChanged<String?> onSelectMapFilter;
  final VoidCallback onRetry;
  final Future<void> Function({bool forceGraph, bool forceLinear}) onCreateMission;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>) onOpen;
  final void Function(Map<String, dynamic>) onDelete;
  final void Function(String action, String missionId) onControlMission;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    if (error != null) {
      final unreachable = error!.isUnreachable;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                unreachable ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
                size: 52,
                color: unreachable ? colors.textSecondary : colors.danger,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                unreachable
                    ? "Missions need navpro-sdk.service running on the robot — it isn't reachable right now."
                    : error!.message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      );
    }

    if (missions == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: SkeletonList(),
      );
    }

    // Active runner state
    final activeId = runnerStatus?['mission_id'] as String?;
    final activeState = runnerStatus?['state'] as String?;
    final pauseReason = runnerStatus?['pause_reason'] as String?;
    final isRunning = activeState == 'running' || activeState == 'paused' || activeState == 'charging_paused';
    final isLowBattery = activeState == 'paused' && pauseReason == 'low_battery';

    final activeMission = activeId != null
        ? missions!.firstWhere((m) => m['id'] == activeId, orElse: () => const {})
        : null;

    // Available maps for filter
    final availableMaps = <String>{};
    for (final m in missions!) {
      final mapName = m['map'] as String?;
      if (mapName != null && mapName.isNotEmpty) {
        availableMaps.add(mapName);
      }
    }

    // Filter missions list
    final filtered = missions!.where((m) {
      final id = m['id'] as String? ?? '';
      final name = m['name'] as String? ?? id;
      final isGraph = m['type'] == 'graph' || m.containsKey('nodes');
      final missionMap = m['map'] as String?;

      // 1. Text search
      if (searchQuery.isNotEmpty) {
        final matchesName = name.toLowerCase().contains(searchQuery);
        final matchesId = id.toLowerCase().contains(searchQuery);
        final matchesMap = missionMap?.toLowerCase().contains(searchQuery) ?? false;
        if (!matchesName && !matchesId && !matchesMap) return false;
      }

      // 2. Map filter
      if (selectedMapFilter != null && missionMap != selectedMapFilter) {
        return false;
      }

      // 3. Category filter
      switch (categoryFilter) {
        case _MissionCategoryFilter.all:
          return true;
        case _MissionCategoryFilter.graph:
          return isGraph;
        case _MissionCategoryFilter.linear:
          return !isGraph;
        case _MissionCategoryFilter.active:
          return id == activeId && isRunning;
      }
    }).toList();

    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? AppSpacing.xl : AppSpacing.md),
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

          // 1. Running Mission Hero Banner (Operations Cockpit)
          if (isRunning && activeMission != null && activeMission.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: _ActiveMissionHeroBanner(
                  mission: activeMission,
                  runnerStatus: runnerStatus,
                  activeState: activeState!,
                  isLowBattery: isLowBattery,
                  onOpen: () => onOpen(activeMission),
                  onControl: onControlMission,
                ),
              ),
            ),

          // 2. Search & Segmented Category Filter Toolbar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _SearchAndFilterToolbar(
                searchController: searchController,
                searchQuery: searchQuery,
                categoryFilter: categoryFilter,
                selectedMapFilter: selectedMapFilter,
                availableMaps: availableMaps,
                currentMap: currentMap,
                allCount: missions!.length,
                graphCount: missions!.where((m) => m['type'] == 'graph' || m.containsKey('nodes')).length,
                linearCount: missions!.where((m) => m['type'] != 'graph' && !m.containsKey('nodes')).length,
                activeCount: (isRunning && activeId != null) ? 1 : 0,
                onSelectCategory: onSelectCategory,
                onSelectMapFilter: onSelectMapFilter,
              ),
            ),
          ),

          // 3. Missions Grid / List
          if (missions!.isEmpty)
            SliverToBoxAdapter(
              child: _buildEmptyState(context, colors),
            )
          else if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: _buildNoSearchResults(context, colors),
            )
          else
            _buildMissionsGrid(context, filtered, activeId, activeState, isRunning, isDesktop),

          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppColorsTheme colors) {
    return Card(
      elevation: 0,
      color: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.route_rounded, size: 38, color: colors.primary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No Autonomous Missions Found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: colors.textPrimary),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                'Missions define automated routines, delivery routes, and logic workflows for your AMR.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => onCreateMission(forceGraph: true),
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: const Text('Create Visual Workflow'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onCreateMission(forceLinear: true),
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: const Text('Create Waypoint Route'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResults(BuildContext context, AppColorsTheme colors) {
    return Card(
      elevation: 0,
      color: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, size: 44, color: colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No matching missions found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Try adjusting your search keywords or clear category filters.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                searchController.clear();
                onSelectCategory(_MissionCategoryFilter.all);
                onSelectMapFilter(null);
              },
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Reset All Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissionsGrid(
    BuildContext context,
    List<Map<String, dynamic>> missionsList,
    String? activeId,
    String? activeState,
    bool isRunning,
    bool isDesktop,
  ) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.crossAxisExtent;
        final isSingleColumn = availableWidth < 680;

        if (isSingleColumn) {
          return SliverList.separated(
            itemCount: missionsList.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) => _MissionCard(
              mission: missionsList[i],
              activeId: activeId,
              activeState: activeState,
              isRunning: isRunning,
              currentMap: currentMap,
              onOpen: () => onOpen(missionsList[i]),
              onEdit: () => onEdit(missionsList[i]),
              onDelete: () => onDelete(missionsList[i]),
            ),
          );
        }

        final crossAxisCount = availableWidth > 1300 ? 3 : 2;

        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            mainAxisExtent: 242,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _MissionCard(
              mission: missionsList[i],
              activeId: activeId,
              activeState: activeState,
              isRunning: isRunning,
              currentMap: currentMap,
              onOpen: () => onOpen(missionsList[i]),
              onEdit: () => onEdit(missionsList[i]),
              onDelete: () => onDelete(missionsList[i]),
            ),
            childCount: missionsList.length,
          ),
        );
      },
    );
  }
}

/// Search input bar, category filter pills, and active map selector chip.
class _SearchAndFilterToolbar extends StatelessWidget {
  const _SearchAndFilterToolbar({
    required this.searchController,
    required this.searchQuery,
    required this.categoryFilter,
    required this.selectedMapFilter,
    required this.availableMaps,
    required this.currentMap,
    required this.allCount,
    required this.graphCount,
    required this.linearCount,
    required this.activeCount,
    required this.onSelectCategory,
    required this.onSelectMapFilter,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final _MissionCategoryFilter categoryFilter;
  final String? selectedMapFilter;
  final Set<String> availableMaps;
  final String? currentMap;
  final int allCount;
  final int graphCount;
  final int linearCount;
  final int activeCount;
  final ValueChanged<_MissionCategoryFilter> onSelectCategory;
  final ValueChanged<String?> onSelectMapFilter;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Bar row
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 42,
                child: TextField(
                  controller: searchController,
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search missions by name or ID...',
                    hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: colors.textSecondary),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () => searchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: colors.surfaceSunken,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
            if (availableMaps.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              PopupMenuButton<String?>(
                tooltip: 'Filter by Map',
                onSelected: onSelectMapFilter,
                itemBuilder: (ctx) => [
                  PopupMenuItem<String?>(
                    value: null,
                    child: Text('All Maps (${availableMaps.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const PopupMenuDivider(),
                  for (final mapName in availableMaps)
                    PopupMenuItem<String?>(
                      value: mapName,
                      child: Row(
                        children: [
                          Icon(
                            mapName == currentMap ? Icons.my_location_rounded : Icons.map_outlined,
                            size: 16,
                            color: mapName == currentMap ? colors.primary : colors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              mapName == currentMap ? '$mapName (Active)' : mapName,
                              style: TextStyle(
                                fontWeight: mapName == currentMap ? FontWeight.bold : FontWeight.normal,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: selectedMapFilter != null ? colors.primary.withValues(alpha: 0.12) : colors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selectedMapFilter != null ? colors.primary.withValues(alpha: 0.4) : colors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 16,
                        color: selectedMapFilter != null ? colors.primary : colors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        selectedMapFilter ?? (currentMap != null ? 'Map: $currentMap' : 'Map: All'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selectedMapFilter != null ? colors.primary : colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down_rounded, size: 18, color: colors.textSecondary),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: AppSpacing.sm),

        // Segmented Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(
                colors: colors,
                label: 'All ($allCount)',
                selected: categoryFilter == _MissionCategoryFilter.all,
                onTap: () => onSelectCategory(_MissionCategoryFilter.all),
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                colors: colors,
                label: 'Visual Graphs ($graphCount)',
                icon: Icons.account_tree_outlined,
                iconColor: const Color(0xFF00E5FF),
                selected: categoryFilter == _MissionCategoryFilter.graph,
                onTap: () => onSelectCategory(_MissionCategoryFilter.graph),
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                colors: colors,
                label: 'Linear Routes ($linearCount)',
                icon: Icons.route_rounded,
                iconColor: colors.primary,
                selected: categoryFilter == _MissionCategoryFilter.linear,
                onTap: () => onSelectCategory(_MissionCategoryFilter.linear),
              ),
              if (activeCount > 0) ...[
                const SizedBox(width: 8),
                _buildFilterChip(
                  colors: colors,
                  label: 'Active Running',
                  icon: Icons.play_circle_fill_rounded,
                  iconColor: colors.stateIdle,
                  selected: categoryFilter == _MissionCategoryFilter.active,
                  onTap: () => onSelectCategory(_MissionCategoryFilter.active),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required AppColorsTheme colors,
    required String label,
    IconData? icon,
    Color? iconColor,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: 0.16) : colors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? colors.primary : (iconColor ?? colors.textSecondary)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? colors.primary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hero Banner shown when an autonomous mission is currently active or charging-paused.
class _ActiveMissionHeroBanner extends StatelessWidget {
  const _ActiveMissionHeroBanner({
    required this.mission,
    required this.runnerStatus,
    required this.activeState,
    required this.isLowBattery,
    required this.onOpen,
    required this.onControl,
  });

  final Map<String, dynamic> mission;
  final Map<String, dynamic>? runnerStatus;
  final String activeState;
  final bool isLowBattery;
  final VoidCallback onOpen;
  final void Function(String action, String missionId) onControl;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final missionId = mission['id'] as String;
    final missionName = mission['name'] as String? ?? missionId;
    final isGraph = mission['type'] == 'graph' || mission.containsKey('nodes');

    final stateColor = switch (activeState) {
      'running' => colors.stateIdle,
      'paused' => colors.warning,
      'failed' => colors.danger,
      _ => colors.primary,
    };

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        side: BorderSide(color: stateColor, width: 2),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              stateColor.withValues(alpha: 0.12),
              colors.surfaceElevated,
            ],
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 640;

            final statusRow = Row(
              children: [
                StatusPulseDot(
                  color: stateColor,
                  live: activeState == 'running',
                  size: 10,
                ),
                const SizedBox(width: 8),
                Text(
                  isLowBattery ? 'PAUSED (CHARGING)' : activeState.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: stateColor,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: (isGraph ? const Color(0xFF00E5FF) : colors.primary).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isGraph ? 'VISUAL WORKFLOW' : 'LINEAR ROUTE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isGraph ? const Color(0xFF00E5FF) : colors.primary,
                    ),
                  ),
                ),
              ],
            );

            final missionTitle = Text(
              missionName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );

            final telemetryText = Builder(builder: (context) {
              final stepIdx = (runnerStatus?['step_index'] as num?)?.toInt() ?? 0;
              final stepTotal = (runnerStatus?['step_total'] as num?)?.toInt() ??
                  (runnerStatus?['step_count'] as num?)?.toInt() ??
                  (mission['steps'] as List? ?? []).length;
              final loopIdx = (runnerStatus?['loop_index'] as num?)?.toInt();
              final loopTotal = (runnerStatus?['loop_total'] as num?)?.toInt();
              final activeNode = runnerStatus?['active_node_label'] as String?;
              final msg = runnerStatus?['message'] as String?;

              final parts = <String>[];
              if (stepTotal > 0) {
                parts.add('Step ${stepIdx + 1}/$stepTotal');
              }
              if (loopIdx != null) {
                if (loopTotal != null && loopTotal > 1) {
                  parts.add('Lap ${loopIdx + 1}/$loopTotal');
                } else if (loopTotal == null) {
                  parts.add('Loop ∞');
                }
              }
              if (activeNode != null && activeNode.isNotEmpty) {
                parts.add(activeNode);
              }
              if (activeState == 'failed' && msg != null && msg.isNotEmpty) {
                parts.add('Error: $msg');
              }
              return Text(
                parts.isEmpty ? 'Executing mission...' : parts.join(' · '),
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            });

            final actionButtons = Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (activeState == 'running')
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: const Size(0, 36),
                      side: BorderSide(color: colors.warning),
                    ),
                    icon: Icon(Icons.pause_rounded, size: 16, color: colors.warning),
                    label: Text('Pause', style: TextStyle(color: colors.warning, fontSize: 12)),
                    onPressed: () => onControl('pause', missionId),
                  ),
                if (activeState == 'paused')
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: const Size(0, 36),
                      side: BorderSide(color: colors.stateIdle),
                    ),
                    icon: Icon(Icons.play_arrow_rounded, size: 16, color: colors.stateIdle),
                    label: Text('Resume', style: TextStyle(color: colors.stateIdle, fontSize: 12)),
                    onPressed: () => onControl('resume', missionId),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(0, 36),
                    side: BorderSide(color: colors.danger.withValues(alpha: 0.5)),
                  ),
                  icon: Icon(Icons.stop_rounded, size: 16, color: colors.danger),
                  label: Text('Abort', style: TextStyle(color: colors.danger, fontSize: 12)),
                  onPressed: () => onControl('cancel', missionId),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                    backgroundColor: colors.primary,
                  ),
                  icon: const Icon(Icons.fullscreen_rounded, size: 16),
                  label: const Text('Live Monitor', style: TextStyle(fontSize: 12)),
                  onPressed: onOpen,
                ),
              ],
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  statusRow,
                  const SizedBox(height: 6),
                  missionTitle,
                  const SizedBox(height: 2),
                  telemetryText,
                  const SizedBox(height: 12),
                  actionButtons,
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      statusRow,
                      const SizedBox(height: 6),
                      missionTitle,
                      const SizedBox(height: 2),
                      telemetryText,
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                actionButtons,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Highly polished dark cockpit mission card supporting both Visual Graph and Linear Routes.
class _MissionCard extends StatelessWidget {
  const _MissionCard({
    required this.mission,
    required this.activeId,
    required this.activeState,
    required this.isRunning,
    required this.currentMap,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> mission;
  final String? activeId;
  final String? activeState;
  final bool isRunning;
  final String? currentMap;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final id = mission['id'] as String;
    final name = mission['name'] as String? ?? id;
    final isGraph = mission['type'] == 'graph' || mission.containsKey('nodes');
    final steps = (mission['steps'] as List? ?? const []).cast<Map<String, dynamic>>();
    final nodes = (mission['nodes'] as List? ?? const []).cast<Map<String, dynamic>>();

    final isActive = id == activeId && isRunning;
    final isCompleted = id == activeId && activeState == 'completed';
    final status = isActive ? activeState : (isCompleted ? 'completed' : null);

    final missionMap = mission['map'] as String?;
    final isMismatch = missionMap != null && currentMap != null && missionMap != currentMap;

    final themeAccentColor = isGraph ? const Color(0xFF00E5FF) : colors.primary;
    final cardBorderColor = isActive
        ? (status == 'running' ? colors.stateIdle : colors.warning)
        : colors.border;

    return Card(
      elevation: isActive ? 2 : 0,
      color: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: cardBorderColor,
          width: isActive ? 1.8 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Avatar + Title + Badges + Popup Menu
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: themeAccentColor.withValues(alpha: 0.12),
                  child: Icon(
                    isGraph ? Icons.account_tree_outlined : Icons.route_rounded,
                    color: themeAccentColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: themeAccentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isGraph ? 'GRAPH WORKFLOW' : 'LINEAR ROUTE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: themeAccentColor,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isGraph ? '${nodes.length} nodes' : '${steps.length} steps',
                            style: TextStyle(fontSize: 11, color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: (status == 'running' ? colors.stateIdle : colors.warning).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: status == 'running' ? colors.stateIdle : colors.warning,
                      ),
                    ),
                  ),
                ],
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, size: 18, color: colors.textSecondary),
                  tooltip: 'Actions',
                  onSelected: (action) {
                    if (action == 'open') onOpen();
                    if (action == 'edit') onEdit();
                    if (action == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'open',
                      child: Row(
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 18, color: colors.stateIdle),
                          const SizedBox(width: 8),
                          const Text('View & Run'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18, color: colors.primary),
                          const SizedBox(width: 8),
                          const Text('Edit Mission'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: colors.danger),
                          const SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: colors.danger)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Map Binding Tag
            if (missionMap != null) ...[
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
                    Icon(
                      isMismatch ? Icons.warning_amber_rounded : Icons.map_outlined,
                      size: 11,
                      color: isMismatch ? colors.warning : colors.primary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        isMismatch ? '$missionMap (Inactive Map)' : 'Map: $missionMap',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isMismatch ? colors.warning : colors.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],

            // Workflow Step / Node Visual Pipeline
            Text(
              isGraph ? 'Workflow Flow:' : 'Step Sequence:',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colors.textSecondary),
            ),
            const SizedBox(height: 4),
            if (isGraph)
              _NodeFlowPreviewRow(nodes: nodes)
            else
              _StepRoutePreviewRow(steps: steps),

            const Spacer(),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 8),

            // Action Buttons
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 34),
                    side: BorderSide(color: colors.border),
                  ),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Delete Mission',
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: colors.danger.withValues(alpha: 0.8)),
                  onPressed: onDelete,
                ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 34),
                    backgroundColor: isActive ? colors.stateIdle : colors.primary,
                  ),
                  onPressed: onOpen,
                  icon: Icon(isActive ? Icons.fullscreen_rounded : Icons.play_arrow_rounded, size: 16),
                  label: Text(isActive ? 'Live View' : 'Run', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal visual pipeline for Visual Graph missions.
class _NodeFlowPreviewRow extends StatelessWidget {
  const _NodeFlowPreviewRow({required this.nodes});

  final List<Map<String, dynamic>> nodes;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final validNodes = nodes.where((n) {
      final t = n['type'] as String? ?? '';
      return t != 'start' && t != 'end';
    }).toList();

    if (validNodes.isEmpty) {
      return Text('Empty workflow graph', style: TextStyle(color: colors.textTertiary, fontSize: 11));
    }

    const maxShown = 5;
    final shown = validNodes.take(maxShown).toList();
    final overflow = validNodes.length - shown.length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < shown.length; i++) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_nodeIcon(shown[i]['type']), size: 12, color: _nodeColor(shown[i]['type'], colors)),
                  const SizedBox(width: 3),
                  Text(
                    _nodeLabel(shown[i]),
                    style: TextStyle(fontSize: 10, color: colors.textPrimary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            if (i < shown.length - 1) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Icon(Icons.chevron_right_rounded, size: 14, color: colors.textTertiary),
              ),
            ],
          ],
          if (overflow > 0) ...[
            const SizedBox(width: 4),
            Text('+$overflow more', style: TextStyle(fontSize: 10, color: colors.textTertiary)),
          ],
        ],
      ),
    );
  }

  static IconData _nodeIcon(dynamic type) => switch (type) {
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

  static Color _nodeColor(dynamic type, AppColorsTheme colors) => switch (type) {
        'navigate' => const Color(0xFF3B82F6),
        'wait' => colors.warning,
        'dock' => const Color(0xFF10B981),
        'undock' => colors.textSecondary,
        'condition' => const Color(0xFFA855F7),
        'loop' => const Color(0xFF8B5CF6),
        'ui_interaction' => const Color(0xFFEC4899),
        'patrol' => const Color(0xFF00E5FF),
        _ => colors.textSecondary,
      };

  static String _nodeLabel(Map<String, dynamic> node) {
    final label = node['label'] as String? ?? node['type'] as String? ?? '';
    if (label.length > 10) return '${label.substring(0, 9)}…';
    return label;
  }
}

/// Horizontal visual pipeline for Linear Step missions.
class _StepRoutePreviewRow extends StatelessWidget {
  const _StepRoutePreviewRow({required this.steps});

  final List<Map<String, dynamic>> steps;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (steps.isEmpty) {
      return Text('No waypoints defined', style: TextStyle(color: colors.textTertiary, fontSize: 11));
    }

    const maxShown = 6;
    final shown = steps.take(maxShown).toList();
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
            Text('+$overflow', style: TextStyle(color: colors.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }
}
