import 'package:flutter/material.dart';
import 'package:navpromini_launch_manager_interfaces/srv.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/locations_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/fade_in.dart';
import '../../widgets/design/skeleton.dart';
import '../../widgets/design/status_pulse.dart';
import '../../widgets/map/occupancy_grid_view.dart';
import '../../widgets/sdk_state_builder.dart';
import 'create_map_screen.dart';
import 'map_view_screen.dart';

/// Reference §5's Maps list, laid out to match the team's Stitch mockup
/// ("2. Maps List" — search bar, a card per map with a thumbnail on the
/// right, a "Create Map" call-to-action at the bottom) while
/// keeping every value on it real.
///
/// Calls GetMapList directly over rosbridge (the app's core connection, not
/// the optional SDK) — same service navpromini_sdk's own maps.py calls
/// server-side, same path constant.
///
/// Only the currently-active map is actually viewable/thumbnail-able here:
/// /map only ever carries whatever's loaded right now, not arbitrary saved
/// maps from disk — so the active card gets a live render of the real grid,
/// and every other card gets an honest placeholder icon rather than a
/// fabricated floorplan image or an invented "updated N days ago" (the
/// backend keeps neither). Tapping an inactive map or "Create Map"
/// both do the real thing now — see _switchTo() and CreateMapScreen.
class MapsListScreen extends StatefulWidget {
  const MapsListScreen({super.key});

  @override
  State<MapsListScreen> createState() => _MapsListScreenState();
}

class _MapsListScreenState extends State<MapsListScreen> {
  // Matches navpromini_sdk's own handlers/maps.py MAP_PATH exactly.
  static const _mapPath = 'navpromini_mapping/maps';

  List<String>? _maps;
  String? _error;
  bool _requested = false;
  String _query = '';

  Future<void> _load() async {
    setState(() {
      _error = null;
      _maps = null;
    });

    final ros2 = context.read<ConnectionProvider>().ros2;
    if (ros2 == null) {
      setState(() => _error = 'Not connected.');
      return;
    }

    final client =
        ServiceClient<GetMapList, GetMapListRequest, GetMapListResponse>(
      ros2: ros2,
      name: 'get_map_list',
      type: GetMapList().fullType,
      serviceType: GetMapList(),
      timeout: 15,
    );
    try {
      final resp = await client.call(GetMapListRequest(path: _mapPath));
      if (!mounted) return;
      setState(() => _maps = resp.success ? resp.maplist : const []);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load maps: $e');
    } finally {
      client.dispose();
    }
  }

  Future<void> _createMap(BuildContext context) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CreateMapScreen()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    // First build only — didChangeDependencies would re-fire on every
    // ConnectionProvider notification (telemetry-adjacent widgets rebuild
    // often); a plain guarded call here avoids re-fetching the map list on
    // every unrelated connection-state change.
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }

    final connection = context.watch<ConnectionProvider>();
    final robotIp = connection.robot?.ip;

    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maps'),
        actions: [
          if (isDesktop && robotIp != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton.icon(
                onPressed: () => _createMap(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create Map (SLAM)'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: robotIp == null
            ? const Center(child: Text('Not connected.'))
            : SdkStateBuilder(
                robotIp: robotIp,
                builder: (context, sdkState) {
                  final activeMap = sdkState.mapName;
                  if (isDesktop) {
                    return _DesktopMapsView(
                      maps: _maps,
                      error: _error,
                      activeMap: activeMap,
                      query: _query,
                      onQueryChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                      ros2: connection.ros2,
                      robotIp: robotIp,
                      onRetry: _load,
                      onCreateMap: () => _createMap(context),
                    );
                  }
                  return CenteredFormColumn(
                    maxWidth:
                        Breakpoints.of(context) == DeviceClass.desktop ? 960 : 720,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Search maps',
                              prefixIcon: const Icon(Icons.search_rounded),
                              // The one screen this session that borrows the
                              // Stitch mockup's fully-pill search field
                              // rather than the app's usual 12px input
                              // radius — a deliberate, scoped match to that
                              // reference, not a global input-style change.
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide:
                                    const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide:
                                    const BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide: const BorderSide(
                                    color: AppColors.primary, width: 1.5),
                              ),
                            ),
                            onChanged: (v) =>
                                setState(() => _query = v.trim().toLowerCase()),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Expanded(
                            child: _Body(
                              maps: _maps,
                              error: _error,
                              activeMap: activeMap,
                              query: _query,
                              ros2: connection.ros2,
                              robotIp: robotIp,
                              onRetry: _load,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ElevatedButton.icon(
                            onPressed: () => _createMap(context),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Create Map'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({
    required this.maps,
    required this.error,
    required this.activeMap,
    required this.query,
    required this.ros2,
    required this.robotIp,
    required this.onRetry,
  });

  final List<String>? maps;
  final String? error;
  final String? activeMap;
  final String query;
  final Ros2? ros2;
  final String? robotIp;
  final VoidCallback onRetry;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _switching = false;

  Future<void> _switchTo(String name) async {
    final ip = widget.robotIp;
    if (ip == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Switch Map?'),
        content: Text(
          'This restarts navigation using "$name" instead of "${widget.activeMap ?? 'the current map'}".',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Switch')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _switching = true);
    try {
      await SdkApiService(ip).activateMap(name);
      if (!mounted) return;
      // activateMap (handlers/mode.py's switch_mode) returns as soon as
      // launch_manager confirms navigation_launch *started* — map_server
      // itself hasn't configured/activated and republished `/map` yet at
      // that point, which routinely takes a few more seconds (confirmed
      // live). Saying so up front instead of a flat past-tense "Switched"
      // is what actually matches what's on screen a moment later — any
      // live map view still genuinely has the old map/no map until
      // map_server catches up, there's nothing this snackbar's wording
      // can shortcut.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Switching to "$name"… it\'ll finish loading in a few seconds.')));
      widget.onRetry();
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          e.isUnreachable
              ? "Switching maps needs navpro-sdk.service — it isn't reachable right now."
              : e.message,
        ),
      ));
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  /// Backs the swipe-to-delete gesture. Returns whether the map was
  /// actually deleted, which [Dismissible] uses to decide whether to
  /// complete the swipe-away animation or snap the tile back — declining
  /// the confirmation, or the server refusing because it's the active map,
  /// both mean "snap back", not "remove the tile from a list it's still
  /// really in".
  Future<bool> _deleteMap(String name, bool isActive) async {
    final ip = widget.robotIp;
    if (ip == null) return false;
    if (isActive) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Switch to a different map before deleting "$name" — it\'s the one navigation is currently using.'),
      ));
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Map?'),
        content:
            Text('This permanently deletes "$name". This can\'t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    try {
      await SdkApiService(ip).deleteMap(name);
      if (!mounted) return true;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Deleted "$name".')));
      return true;
    } on SdkApiException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          e.isUnreachable
              ? "Deleting maps needs navpro-sdk.service — it isn't reachable right now."
              : e.message,
        ),
      ));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final maps = widget.maps;
    final error = widget.error;
    final activeMap = widget.activeMap;
    final query = widget.query;
    final ros2 = widget.ros2;
    final onRetry = widget.onRetry;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.danger),
            const SizedBox(height: AppSpacing.md),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (maps == null) {
      return const SkeletonList();
    }

    final filtered =
        maps.where((m) => m.toLowerCase().contains(query)).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          maps.isEmpty ? 'No saved maps yet.' : 'No maps match "$query".',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return Stack(
      children: [
        _list(context, filtered, activeMap, ros2),
        if (_switching)
          Container(
            color: AppColors.surface.withValues(alpha: 0.7),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: AppSpacing.md),
                  Text('Switching maps — this can take up to a minute…',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _list(BuildContext context, List<String> filtered, String? activeMap,
      Ros2? ros2) {
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final name = filtered[i];
        final isActive = name == activeMap;
        return Dismissible(
          key: ValueKey(name),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _deleteMap(name, isActive),
          onDismissed: (_) => widget.onRetry(),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.danger,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            ),
            child: const Icon(Icons.delete_rounded,
                color: AppColors.textOnPrimary),
          ),
          child: FadeSlideIn(
            delay: Duration(milliseconds: 40 * i),
            offset: 8,
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                onTap: isActive
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const MapViewScreen()),
                        )
                    : () => _switchTo(name),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 6),
                            if (isActive)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StatusPulseDot(
                                      color: AppColors.stateIdle,
                                      live: true,
                                      size: 8),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Active',
                                    style: TextStyle(
                                        color: AppColors.stateIdle,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              )
                            else
                              const Text('Not currently active',
                                  style: TextStyle(
                                      color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.inputRadius),
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSunken,
                            border: Border.all(color: AppColors.border),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.inputRadius),
                          ),
                          // Only the active map has anything real to show here —
                          // /map only ever carries the currently-loaded map, not
                          // arbitrary saved ones from disk. Every other card gets
                          // an honest placeholder rather than a fabricated
                          // floorplan thumbnail.
                          child: isActive && ros2 != null
                              ? OccupancyGridView(
                                  ros2: ros2,
                                  interactive: false,
                                  showRobot: false)
                              : const Center(
                                  child: Icon(Icons.map_outlined,
                                      color: AppColors.textTertiary, size: 28),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopMapsView extends StatefulWidget {
  const _DesktopMapsView({
    required this.maps,
    required this.error,
    required this.activeMap,
    required this.query,
    required this.onQueryChanged,
    required this.ros2,
    required this.robotIp,
    required this.onRetry,
    required this.onCreateMap,
  });

  final List<String>? maps;
  final String? error;
  final String? activeMap;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final Ros2? ros2;
  final String? robotIp;
  final VoidCallback onRetry;
  final VoidCallback onCreateMap;

  @override
  State<_DesktopMapsView> createState() => _DesktopMapsViewState();
}

class _DesktopMapsViewState extends State<_DesktopMapsView> {
  bool _switching = false;

  Future<void> _switchTo(String name) async {
    final ip = widget.robotIp;
    if (ip == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Switch Map?'),
        content: Text(
          'This restarts navigation using "$name" instead of "${widget.activeMap ?? 'the current map'}".',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Switch')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _switching = true);
    try {
      await SdkApiService(ip).activateMap(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Switching to "$name"… it\'ll finish loading in a few seconds.')));
      widget.onRetry();
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          e.isUnreachable
              ? "Switching maps needs navpro-sdk.service — it isn't reachable right now."
              : e.message,
        ),
      ));
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<bool> _deleteMap(String name, bool isActive) async {
    final ip = widget.robotIp;
    if (ip == null) return false;
    if (isActive) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Switch to a different map before deleting "$name" — it\'s the one navigation is currently using.'),
      ));
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Map?'),
        content:
            Text('This permanently deletes "$name". This can\'t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    try {
      await SdkApiService(ip).deleteMap(name);
      if (!mounted) return true;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Deleted "$name".')));
      widget.onRetry();
      return true;
    } on SdkApiException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          e.isUnreachable
              ? "Deleting maps needs navpro-sdk.service — it isn't reachable right now."
              : e.message,
        ),
      ));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final maps = widget.maps;
    final error = widget.error;
    final activeMap = widget.activeMap;
    final query = widget.query;
    final ros2 = widget.ros2;
    final telemetry = context.watch<RobotTelemetryProvider>();

    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.danger),
            const SizedBox(height: AppSpacing.md),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: widget.onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (maps == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: SkeletonList(),
      );
    }

    final filtered =
        maps.where((m) => m.toLowerCase().contains(query)).toList();

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Search & Filter Bar
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search saved maps...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      onChanged: widget.onQueryChanged,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Chip(
                    avatar: const Icon(Icons.folder_copy_outlined,
                        size: 16, color: AppColors.primary),
                    label: Text('${maps.length} total maps'),
                    backgroundColor: AppColors.surface,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (activeMap != null)
                    Chip(
                      avatar: StatusPulseDot(
                          color: AppColors.stateIdle, live: true, size: 8),
                      label: Text('Active: $activeMap'),
                      backgroundColor: AppColors.surface,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // 2. Dual-Pane Content: Map Grid (Left) + Active Station (Right)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: Map Cards Grid (flex: 7)
                    Expanded(
                      flex: 7,
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                maps.isEmpty
                                    ? 'No saved maps yet. Click Create Map above to begin SLAM mapping.'
                                    : 'No maps match "$query".',
                                style: const TextStyle(
                                    color: AppColors.textSecondary),
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 380,
                                mainAxisExtent: 195,
                                crossAxisSpacing: AppSpacing.md,
                                mainAxisSpacing: AppSpacing.md,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final name = filtered[i];
                                final isActive = name == activeMap;
                                return Card(
                                  elevation: isActive ? 2 : 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppSpacing.cardRadius),
                                    side: BorderSide(
                                      color: isActive
                                          ? AppColors.primary
                                          : AppColors.border,
                                      width: isActive ? 2 : 1,
                                    ),
                                  ),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.all(AppSpacing.md),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Header Row: Map name + status
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: (isActive
                                                        ? AppColors.primary
                                                        : AppColors.textSecondary)
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.map_rounded,
                                                size: 20,
                                                color: isActive
                                                    ? AppColors.primary
                                                    : AppColors.textSecondary,
                                              ),
                                            ),
                                            const SizedBox(width: AppSpacing.sm),
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isActive)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: AppColors.success
                                                      .withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: const Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.check_circle_rounded,
                                                        size: 14,
                                                        color: AppColors.success),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'Active',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            AppColors.success,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                        const Spacer(),
                                        Text(
                                          isActive
                                              ? 'Currently loaded in Nav2 navigation stack.'
                                              : 'Stored floorplan ready to load.',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        const Spacer(),
                                        // Action buttons row
                                        Row(
                                          children: [
                                            if (isActive)
                                              Expanded(
                                                child: FilledButton.icon(
                                                  onPressed: () =>
                                                      Navigator.of(context)
                                                          .push(
                                                    MaterialPageRoute(
                                                        builder: (_) =>
                                                            const MapViewScreen()),
                                                  ),
                                                  icon: const Icon(
                                                      Icons.open_in_new_rounded,
                                                      size: 16),
                                                  label: const Text(
                                                      'Open 2D View'),
                                                ),
                                              )
                                            else ...[
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _switchTo(name),
                                                  icon: const Icon(
                                                      Icons.play_arrow_rounded,
                                                      size: 16),
                                                  label: const Text(
                                                      'Load / Activate'),
                                                ),
                                              ),
                                              const SizedBox(
                                                  width: AppSpacing.xs),
                                              IconButton(
                                                tooltip: 'Delete map',
                                                icon: const Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    size: 18,
                                                    color: AppColors.danger),
                                                onPressed: () =>
                                                    _deleteMap(name, isActive),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(width: AppSpacing.lg),

                    // Right: Active Navigation Station (flex: 5)
                    Expanded(
                      flex: 5,
                      child: Card(
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.cardRadius),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.hub_rounded,
                                      size: 20, color: AppColors.primary),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    'Active Map Live Studio',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const Spacer(),
                                  if (activeMap != null)
                                    IconButton(
                                      tooltip: 'Open Fullscreen 2D View',
                                      icon: const Icon(
                                          Icons.open_in_full_rounded,
                                          size: 18),
                                      onPressed: () => Navigator.of(context)
                                          .push(MaterialPageRoute(
                                              builder: (_) =>
                                                  const MapViewScreen())),
                                    ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              if (activeMap != null && ros2 != null) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    height: 280,
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceSunken,
                                      border:
                                          Border.all(color: AppColors.border),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: OccupancyGridView(
                                      ros2: ros2,
                                      interactive: false,
                                      showRobot: true,
                                      initialPose: telemetry.rawPose,
                                      initialPath: telemetry.currentPath,
                                      showDock: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => Navigator.of(context)
                                            .push(MaterialPageRoute(
                                                builder: (_) =>
                                                    const MapViewScreen())),
                                        icon: const Icon(
                                            Icons.my_location_rounded,
                                            size: 16),
                                        label: const Text('Open 2D Cockpit'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                const Divider(),
                                const SizedBox(height: AppSpacing.xs),
                                // Saved Locations header
                                Row(
                                  children: [
                                    const Icon(Icons.place_rounded,
                                        size: 16, color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    const Text('Saved Locations',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                    const Spacer(),
                                    ValueListenableBuilder<
                                        List<Map<String, dynamic>>?>(
                                      valueListenable:
                                          LocationsController.instance,
                                      builder: (context, locs, _) => Text(
                                        '${locs?.length ?? 0} locations',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Expanded(
                                  child: ValueListenableBuilder<
                                      List<Map<String, dynamic>>?>(
                                    valueListenable:
                                        LocationsController.instance,
                                    builder: (context, locations, _) {
                                      if (locations == null ||
                                          locations.isEmpty) {
                                        return const Center(
                                          child: Text(
                                            'No locations saved on this map yet.\nOpen 2D View to add pins.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary),
                                          ),
                                        );
                                      }
                                      return ListView.separated(
                                        itemCount: locations.length,
                                        separatorBuilder: (_, __) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, idx) {
                                          final loc = locations[idx];
                                          final name =
                                              loc['name'] as String? ?? '';
                                          final x = (loc['x'] as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                          final y = (loc['y'] as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                          return ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            leading: const CircleAvatar(
                                              radius: 12,
                                              backgroundColor:
                                                  AppColors.surfaceSunken,
                                              child: Icon(Icons.place_rounded,
                                                  size: 14,
                                                  color: AppColors.primary),
                                            ),
                                            title: Text(name,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            subtitle: Text(
                                              '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      AppColors.textSecondary),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ] else ...[
                                const Expanded(
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.map_outlined,
                                            size: 40,
                                            color: AppColors.textTertiary),
                                        SizedBox(height: AppSpacing.sm),
                                        Text(
                                          'No active map loaded in navigation stack.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_switching)
          Container(
            color: AppColors.surface.withValues(alpha: 0.7),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: AppSpacing.md),
                  Text('Activating map and restarting navigation…'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
