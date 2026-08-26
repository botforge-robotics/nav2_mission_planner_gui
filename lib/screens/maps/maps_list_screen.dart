import 'package:flutter/material.dart';
import 'package:navpromini_launch_manager_interfaces/srv.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';

import '../../providers/connection_provider.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Maps')),
      body: SafeArea(
        child: robotIp == null
            ? const Center(child: Text('Not connected.'))
            : SdkStateBuilder(
                robotIp: robotIp,
                builder: (context, sdkState) {
                  final activeMap = sdkState.mapName;
                  return CenteredFormColumn(
                    maxWidth: 720,
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
