import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/locations_controller.dart';
import '../../services/map_layers_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/localize_at_dock.dart';
import '../../widgets/map/not_localized_banner.dart';
import '../../widgets/map/occupancy_grid_view.dart';
import '../../widgets/navigation/dock_action_sheet.dart';
import '../../widgets/navigation/go_to_confirm_sheet.dart';
import '../dock/dock_position_editor_screen.dart';

/// Reference §5's Map View (2D) — the currently-active map, live, with the
/// robot's position, plus real controls: zoom, a Layers panel (dock,
/// locations, both costmaps, planned path — each independently toggleable),
/// and Localize (seed AMCL's belief of where the robot is — either from the
/// robot's known dock pose, or by picking a point and heading directly on
/// the map).
///
/// 3D Map View (the reference's separate panel) is a different rendering
/// problem entirely (point cloud / mesh, not a 2D grid) and isn't built
/// here.
class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key, this.initialPosePicking = false});

  /// Starts already in "Select on Map" pose-picking mode — used when the
  /// operator declines [NotLocalizedBanner]'s dock-confirm on another
  /// screen and gets sent here specifically to set the pose manually,
  /// skipping the extra tap through the Localize menu.
  final bool initialPosePicking;

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

enum _PickPurpose { localize, addLocation }

class _MapViewScreenState extends State<MapViewScreen> {
  final _transformController = TransformationController();
  Size _viewportSize = Size.zero;

  late bool _posePicking = widget.initialPosePicking;
  _PickPurpose _pickPurpose = _PickPurpose.localize;
  ({double x, double y, double theta})? _draftPose;
  bool _localizing = false;
  bool _savingLocation = false;

  ({double x, double y, double theta})? _dockPose;

  SdkApiService? _api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final api = _apiFor(context.read<ConnectionProvider>().robot?.ip);
      if (api != null) LocationsController.instance.refresh(api);
      _loadDockPose();
    });
    // The layers selection and the saved-locations list are both shared
    // app-wide (see MapLayersController's and LocationsController's own
    // docs) — this screen needs to rebuild when either changes from
    // anywhere, not just from its own Layers panel or its own load.
    MapLayersController.instance.addListener(_onSharedStateChanged);
    LocationsController.instance.addListener(_onSharedStateChanged);
  }

  void _onSharedStateChanged() {
    if (mounted) setState(() {});
  }

  /// The live `/dock_pose` topic (handled inside OccupancyGridView itself)
  /// only republishes when the dockwatch node freshly (re)detects the
  /// dock — a robot that hasn't docked/undocked recently in this run can
  /// have a perfectly real, known dock pose with nothing currently on the
  /// topic. Fetching it here via the SDK and passing it down as
  /// [OccupancyGridView.dockPoseOverride] is the same "genuinely
  /// SDK-exclusive data, passed in by the caller" treatment locations
  /// already get via LocationsController.
  Future<void> _loadDockPose() async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;
    final dock = await fetchDockPose(api);
    if (!mounted || dock == null) return;
    setState(() => _dockPose = dock);
  }

  @override
  void dispose() {
    MapLayersController.instance.removeListener(_onSharedStateChanged);
    LocationsController.instance.removeListener(_onSharedStateChanged);
    _transformController.dispose();
    super.dispose();
  }

  SdkApiService? _apiFor(String? ip) {
    if (ip == null) return null;
    if (_api == null || _api!.robotIp != ip) _api = SdkApiService(ip);
    return _api;
  }

  /// Tapping a location pin on the map goes through the same
  /// distance/ETA-then-confirm flow Teleop's quick-nav list uses — see
  /// [showGoToConfirmSheet].
  void _onLocationTapped(Map<String, dynamic> location) {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final ros2 = context.read<ConnectionProvider>().ros2;
    final api = _apiFor(ip);
    if (api == null || ros2 == null) return;
    if (location['x'] is! num || location['y'] is! num) return;
    final telemetry = context.read<RobotTelemetryProvider>();
    showGoToConfirmSheet(
      context: context,
      ros2: ros2,
      api: api,
      locationName: location['name'] as String? ?? '',
      targetX: (location['x'] as num).toDouble(),
      targetY: (location['y'] as num).toDouble(),
      currentX: telemetry.poseX,
      currentY: telemetry.poseY,
    );
  }

  /// Tapping the dock pin offers the same Go to Dock / Dock / Undock
  /// choice Teleop's own Dock/Undock control exposes, straight from the
  /// map — see [showDockActionSheet].
  void _onDockTapped() {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;
    showDockActionSheet(context: context, api: api, dockPose: _dockPose);
  }

  Future<void> _onLocationDelete(Map<String, dynamic> location) async {
    final name = location['name'] as String? ?? '';
    if (name.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Location'),
        content: Text('Are you sure you want to remove "$name" from this map?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;

    try {
      await api.deleteWaypoint(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location "$name" removed'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      await LocationsController.instance.refresh(api);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete location "$name": $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  /// Scales around the viewport's center rather than the transform's own
  /// origin — a plain `..scale(factor)` keeps (0,0) of the *scene* fixed,
  /// which is essentially never where the viewport happens to be pointed,
  /// so the visible area visibly drifts left/right on every tap. The
  /// standard fix: translate the focal point to the origin, scale, then
  /// translate back — that keeps whatever's currently at the center of the
  /// screen still at the center after zooming.
  void _zoomBy(double factor) {
    if (_viewportSize.isEmpty) return;
    final current = _transformController.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(0.2, 8.0);
    final adjust = target / current;
    final focal = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    _transformController.value = _transformController.value.clone()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(adjust, adjust, adjust, 1.0)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
  }

  Future<void> _openLayersPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ValueListenableBuilder<Set<MapLayer>>(
        valueListenable: MapLayersController.instance,
        builder: (context, visible, _) {
          Widget tile(
              MapLayer layer, IconData icon, String title, String subtitle) {
            return CheckboxListTile(
              secondary: Icon(icon, color: AppColors.textSecondary),
              title: Text(title),
              subtitle: Text(subtitle),
              value: visible.contains(layer),
              onChanged: (checked) => MapLayersController.instance
                  .setVisible(layer, checked ?? false),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Layers',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
              tile(MapLayer.dock, Icons.ev_station_rounded, 'Dock',
                  "The robot's saved dock position"),
              tile(MapLayer.locations, Icons.place_rounded, 'Saved Locations',
                  'Pins for every saved location'),
              tile(MapLayer.path, Icons.route_rounded, 'Planned Path',
                  "The navigation stack's current route"),
              tile(
                  MapLayer.globalCostmap,
                  Icons.grid_on_rounded,
                  'Global Costmap',
                  'Where the planner treats the map as blocked'),
              tile(MapLayer.localCostmap, Icons.grid_4x4_rounded,
                  'Local Costmap', 'Live obstacles the robot sees right now'),
              tile(MapLayer.laserScan, Icons.radar_rounded,
                  'LiDAR Points', 'Real-time laser obstacle reflections'),
              const SizedBox(height: AppSpacing.sm),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openSavedLocationsSheet() async {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ValueListenableBuilder<List<Map<String, dynamic>>?>(
          valueListenable: LocationsController.instance,
          builder: (context, locations, _) {
            if (locations == null || locations.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.place_outlined,
                          size: 40, color: AppColors.textTertiary),
                      SizedBox(height: AppSpacing.sm),
                      Text(
                        'No saved locations on this map.',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        'Use "Save Location" in the map tools to add one.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      const Icon(Icons.place_rounded,
                          size: 20, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Saved Locations (${locations.length})',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: locations.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (context, i) {
                      final loc = locations[i];
                      final name = loc['name'] as String? ?? '';
                      final x = (loc['x'] as num?)?.toDouble() ?? 0.0;
                      final y = (loc['y'] as num?)?.toDouble() ?? 0.0;
                      return Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: AppColors.surfaceSunken,
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.pin_drop_rounded,
                              color: AppColors.primary),
                          title: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 20, color: AppColors.danger),
                                tooltip: 'Delete location',
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  _onLocationDelete(loc);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.navigation_rounded,
                                    size: 20, color: AppColors.accent),
                                tooltip: 'Navigate here',
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  _onLocationTapped(loc);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openLocalizeOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Set Robot Position',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.ev_station_rounded,
                color: AppColors.stateDocking),
            title: const Text('Robot at Dock'),
            subtitle: const Text("Use the robot's saved dock pose"),
            onTap: () => Navigator.of(sheetContext).pop('dock'),
          ),
          ListTile(
            leading:
                const Icon(Icons.touch_app_rounded, color: AppColors.primary),
            title: const Text('Select on Map'),
            subtitle:
                const Text('Tap to set position, drag the handle for heading'),
            onTap: () => Navigator.of(sheetContext).pop('map'),
          ),
          ListTile(
            leading:
                const Icon(Icons.blur_on_rounded, color: AppColors.accent),
            title: const Text('Global Relocalize (Recovery)'),
            subtitle: const Text(
                'Disperse particles across map to recover from slip or strike'),
            onTap: () => Navigator.of(sheetContext).pop('global'),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'dock') {
      await _localizeAtDock();
    } else if (choice == 'global') {
      await _globalRelocalize();
    } else {
      setState(() {
        _posePicking = true;
        _pickPurpose = _PickPurpose.localize;
        _draftPose = null;
      });
    }
  }

  /// "Add Location": the same click-drag pose picker Localize's own
  /// "Select on Map" uses, repurposed — on confirm this saves a *named*
  /// waypoint at the picked pose (via SdkApiService.saveWaypoint's explicit
  /// x/y/theta) instead of localizing to it. Replaces the old dedicated
  /// Add Location screen, which only ever offered "robot's current pose";
  /// picking a pose directly on the map is more general (and matches how
  /// Localize's own picker already works, rather than a second, different
  /// interaction for a very similar task).
  void _startAddLocationPicking() {
    setState(() {
      _posePicking = true;
      _pickPurpose = _PickPurpose.addLocation;
      _draftPose = null;
    });
  }

  Future<void> _localizeAtDock() async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;
    setState(() => _localizing = true);
    try {
      await localizeAtDock(context: context, api: api);
    } finally {
      if (mounted) setState(() => _localizing = false);
    }
  }

  Future<void> _globalRelocalize() async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;
    setState(() => _localizing = true);
    try {
      await api.reinitializeGlobalLocalization();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'AMCL global relocalization triggered. Drive or rotate the robot in place to let particles converge.'),
          duration: Duration(seconds: 4),
        ),
      );
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Global relocalization failed: ${e.message}')),
      );
    } finally {
      if (mounted) setState(() => _localizing = false);
    }
  }

  Future<void> _confirmDraftPose() => _pickPurpose == _PickPurpose.addLocation
      ? _confirmAddLocation()
      : _confirmLocalize();

  Future<void> _confirmLocalize() async {
    final draft = _draftPose;
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (draft == null || api == null) return;
    setState(() => _localizing = true);
    try {
      await api.localize(draft.x, draft.y, theta: draft.theta);
      if (!mounted) return;
      setState(() {
        _posePicking = false;
        _draftPose = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Localized to the selected position.')));
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          e.isUnreachable
              ? "Localizing needs navpro-sdk.service — it isn't reachable right now."
              : e.message,
        ),
      ));
    } finally {
      if (mounted) setState(() => _localizing = false);
    }
  }

  Future<void> _confirmAddLocation() async {
    final draft = _draftPose;
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (draft == null || api == null) return;

    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save Location'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Kitchen'),
          onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, nameController.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    // Deferred, not disposed right here: the dialog's TextField was
    // autofocused, so its selection/keyboard overlay is often still
    // mid-teardown the instant showDialog's Future resolves (Navigator.pop
    // completes the Future before the exit transition finishes). Disposing
    // the controller out from under that in-flight teardown is what threw
    // the framework's "_dependents.isEmpty" assertion (harmless in release
    // builds, but worth avoiding) — waiting a frame lets it finish first.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => nameController.dispose());
    if (name == null || name.isEmpty || !mounted) return;

    setState(() => _savingLocation = true);
    try {
      await api.saveWaypoint(name, x: draft.x, y: draft.y, theta: draft.theta);
      await LocationsController.instance.refresh(api);
      if (!mounted) return;
      setState(() {
        _posePicking = false;
        _draftPose = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved "$name".')));
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          e.isUnreachable
              ? "Saving locations needs navpro-sdk.service — it isn't reachable right now."
              : e.message,
        ),
      ));
    } finally {
      if (mounted) setState(() => _savingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final ros2 = connection.ros2;
    final telemetry = context.watch<RobotTelemetryProvider>();
    final api = _apiFor(connection.robot?.ip);
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;

    return Scaffold(
      appBar: AppBar(
        title: Text(isDesktop ? '2D Map Cockpit' : 'Map View'),
        actions: [
          if (isDesktop) ...[
            if (telemetry.localized)
              Container(
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gps_fixed_rounded, size: 14, color: AppColors.success),
                    const SizedBox(width: 6),
                    Text(
                      'AMCL: (${telemetry.poseX?.toStringAsFixed(2) ?? '--'}, ${telemetry.poseY?.toStringAsFixed(2) ?? '--'}) · ${(telemetry.poseTheta != null ? (telemetry.poseTheta! * 180 / pi).toStringAsFixed(1) : '0.0')}°',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
                    ),
                  ],
                ),
              )
            else
              Container(
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
                    SizedBox(width: 6),
                    Text(
                      'Not Localized',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning),
                    ),
                  ],
                ),
              ),
            if (telemetry.dockStatus != null)
              Container(
                margin: const EdgeInsets.only(right: AppSpacing.md),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.dock_rounded, size: 14, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Dock: ${telemetry.dockStatus}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
      body: ros2 == null
          ? const Center(child: Text('Not connected.'))
          : isDesktop
              ? Row(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              _viewportSize = constraints.biggest;
                              final visibleLayers =
                                  MapLayersController.instance.value;
                              return Container(
                                color: AppColors.background,
                                child: OccupancyGridView(
                                  ros2: ros2,
                                  interactive: true,
                                  showDock:
                                      visibleLayers.contains(MapLayer.dock),
                                  showPath:
                                      visibleLayers.contains(MapLayer.path),
                                  showLaserScan: visibleLayers
                                      .contains(MapLayer.laserScan),
                                  initialPose: telemetry.rawPose,
                                  initialPath: telemetry.currentPath,
                                  showGlobalCostmap: visibleLayers
                                      .contains(MapLayer.globalCostmap),
                                  showLocalCostmap: visibleLayers
                                      .contains(MapLayer.localCostmap),
                                  locations:
                                      visibleLayers.contains(MapLayer.locations)
                                          ? (LocationsController
                                                  .instance.value ??
                                              const [])
                                          : const [],
                                  showOverlays: true,
                                  transformationController:
                                      _transformController,
                                  posePicking: _posePicking,
                                  draftPoseOverride: _draftPose,
                                  onDraftPose: (x, y, theta) => setState(
                                      () => _draftPose =
                                          (x: x, y: y, theta: theta)),
                                  onLocationTap:
                                      visibleLayers.contains(MapLayer.locations)
                                          ? _onLocationTapped
                                          : null,
                                  onDockTap:
                                      visibleLayers.contains(MapLayer.dock)
                                          ? _onDockTapped
                                          : null,
                                  showLocalizationBadge: false,
                                  dockPoseOverride: _dockPose,
                                ),
                              );
                            },
                          ),
                          if (!_posePicking &&
                              !telemetry.localized &&
                              api != null)
                            Positioned(
                              left: AppSpacing.md,
                              right: 120,
                              top: AppSpacing.md,
                              child: NotLocalizedBanner(
                                api: api,
                                onDecline: () {
                                  setState(() {
                                    _posePicking = true;
                                    _pickPurpose = _PickPurpose.localize;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Tap the map to set the position, then drag the handle to set the heading.')));
                                },
                              ),
                            ),
                          Positioned(
                            right: AppSpacing.md,
                            top: AppSpacing.md,
                            child: _DesktopZoomHud(
                              onZoomIn: () => _zoomBy(1.25),
                              onZoomOut: () => _zoomBy(0.8),
                              onReset: () {
                                _transformController.value =
                                    Matrix4.identity();
                              },
                            ),
                          ),
                          if (_posePicking)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _PosePickingBar(
                                hasDraft: _draftPose != null,
                                busy: _pickPurpose == _PickPurpose.addLocation
                                    ? _savingLocation
                                    : _localizing,
                                forLocation:
                                    _pickPurpose == _PickPurpose.addLocation,
                                onCancel: () => setState(() {
                                  _posePicking = false;
                                  _draftPose = null;
                                }),
                                onConfirm: _confirmDraftPose,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _DesktopStudioSidebar(
                      onLocalizeMap: () {
                        setState(() {
                          _posePicking = true;
                          _pickPurpose = _PickPurpose.localize;
                          _draftPose = null;
                        });
                      },
                      onLocalizeDock: _localizeAtDock,
                      onGlobalRelocalize: _globalRelocalize,
                      onAddLocation: _startAddLocationPicking,
                      onLocationTap: _onLocationTapped,
                      onLocationDelete: _onLocationDelete,
                      onDockTap: _onDockTapped,
                      localizing: _localizing,
                    ),
                  ],
                )
              : Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        _viewportSize = constraints.biggest;
                        final visibleLayers = MapLayersController.instance.value;
                        return Container(
                          color: AppColors.background,
                          child: OccupancyGridView(
                            ros2: ros2,
                            interactive: true,
                            showDock: visibleLayers.contains(MapLayer.dock),
                            showPath: visibleLayers.contains(MapLayer.path),
                            showLaserScan:
                                visibleLayers.contains(MapLayer.laserScan),
                            initialPose: telemetry.rawPose,
                            initialPath: telemetry.currentPath,
                            showGlobalCostmap:
                                visibleLayers.contains(MapLayer.globalCostmap),
                            showLocalCostmap:
                                visibleLayers.contains(MapLayer.localCostmap),
                            locations: visibleLayers.contains(MapLayer.locations)
                                ? (LocationsController.instance.value ?? const [])
                                : const [],
                            showOverlays: true,
                            transformationController: _transformController,
                            posePicking: _posePicking,
                            draftPoseOverride: _draftPose,
                            onDraftPose: (x, y, theta) => setState(
                                () => _draftPose = (x: x, y: y, theta: theta)),
                            onLocationTap:
                                visibleLayers.contains(MapLayer.locations)
                                    ? _onLocationTapped
                                    : null,
                            onDockTap: visibleLayers.contains(MapLayer.dock)
                                ? _onDockTapped
                                : null,
                            showLocalizationBadge: false,
                            dockPoseOverride: _dockPose,
                          ),
                        );
                      },
                    ),
                    if (!_posePicking && !telemetry.localized && api != null)
                      Positioned(
                        left: AppSpacing.md,
                        right: 76,
                        top: AppSpacing.md,
                        child: NotLocalizedBanner(
                          api: api,
                          onDecline: () {
                            setState(() {
                              _posePicking = true;
                              _pickPurpose = _PickPurpose.localize;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text(
                                    'Tap the map to set the position, then drag the handle to set the heading.')));
                          },
                        ),
                      ),
                    if (!_posePicking)
                      Positioned(
                        right: AppSpacing.md,
                        top: AppSpacing.md,
                        child: _ControlCluster(
                          layersActive:
                              MapLayersController.instance.value.isNotEmpty,
                          onLayers: _openLayersPanel,
                          onZoomIn: () => _zoomBy(1.25),
                          onZoomOut: () => _zoomBy(0.8),
                          onLocalize: _localizing ? null : _openLocalizeOptions,
                          localizing: _localizing,
                          onAddLocation: _startAddLocationPicking,
                          onShowLocations: _openSavedLocationsSheet,
                        ),
                      ),
                    if (_posePicking)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _PosePickingBar(
                          hasDraft: _draftPose != null,
                          busy: _pickPurpose == _PickPurpose.addLocation
                              ? _savingLocation
                              : _localizing,
                          forLocation: _pickPurpose == _PickPurpose.addLocation,
                          onCancel: () => setState(() {
                            _posePicking = false;
                            _draftPose = null;
                          }),
                          onConfirm: _confirmDraftPose,
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _ControlCluster extends StatelessWidget {
  const _ControlCluster({
    required this.layersActive,
    required this.onLayers,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onLocalize,
    required this.localizing,
    required this.onAddLocation,
    required this.onShowLocations,
  });

  final bool layersActive;
  final VoidCallback onLayers;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback? onLocalize;
  final bool localizing;
  final VoidCallback onAddLocation;
  final VoidCallback onShowLocations;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ClusterCard(children: [
          _ControlButton(
            icon: layersActive
                ? Icons.layers_rounded
                : Icons.layers_clear_rounded,
            tooltip: 'Layers',
            onTap: onLayers,
            color: layersActive ? AppColors.primary : null,
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        _ClusterCard(children: [
          _ControlButton(
              icon: Icons.add_rounded, tooltip: 'Zoom in', onTap: onZoomIn),
          const Divider(height: 1),
          _ControlButton(
              icon: Icons.remove_rounded,
              tooltip: 'Zoom out',
              onTap: onZoomOut),
        ]),
        const SizedBox(height: AppSpacing.sm),
        _ClusterCard(children: [
          _ControlButton(
            icon: Icons.my_location_rounded,
            tooltip: 'Localize',
            onTap: onLocalize,
            busy: localizing,
            color: AppColors.primary,
          ),
          const Divider(height: 1),
          _ControlButton(
            icon: Icons.add_location_alt_rounded,
            tooltip: 'Save Location',
            onTap: onAddLocation,
            color: AppColors.primary,
          ),
          const Divider(height: 1),
          _ControlButton(
            icon: Icons.place_rounded,
            tooltip: 'Saved Locations',
            onTap: onShowLocations,
            color: AppColors.primary,
          ),
        ]),
      ],
    );
  }
}

class _ClusterCard extends StatelessWidget {
  const _ClusterCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: busy
              ? const Center(
                  child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : Icon(icon, color: color ?? AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _PosePickingBar extends StatelessWidget {
  const _PosePickingBar({
    required this.hasDraft,
    required this.busy,
    required this.forLocation,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool hasDraft;
  final bool busy;

  /// True while picking a pose for "Add Location" (name-and-save on
  /// confirm) rather than the default "Localize" purpose (seed AMCL) —
  /// same picker, different wording and destination action.
  final bool forLocation;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasDraft
                  ? 'Drag the handle to set the heading, then confirm.'
                  : forLocation
                      ? "Tap the map to set the location's position."
                      : "Tap the map to set the robot's position.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (busy || !hasDraft) ? null : onConfirm,
                    child: busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.textOnPrimary),
                          )
                        : Text(forLocation ? 'Next' : 'Confirm Position'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopZoomHud extends StatelessWidget {
  const _DesktopZoomHud({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom in',
            icon: const Icon(Icons.add_rounded, size: 20),
            onPressed: onZoomIn,
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'Zoom out',
            icon: const Icon(Icons.remove_rounded, size: 20),
            onPressed: onZoomOut,
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'Reset view / Center',
            icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

class _DesktopStudioSidebar extends StatelessWidget {
  const _DesktopStudioSidebar({
    required this.onLocalizeMap,
    required this.onLocalizeDock,
    required this.onGlobalRelocalize,
    required this.onAddLocation,
    required this.onLocationTap,
    this.onLocationDelete,
    required this.onDockTap,
    required this.localizing,
  });

  final VoidCallback onLocalizeMap;
  final VoidCallback onLocalizeDock;
  final VoidCallback onGlobalRelocalize;
  final VoidCallback onAddLocation;
  final void Function(Map<String, dynamic>) onLocationTap;
  final void Function(Map<String, dynamic>)? onLocationDelete;
  final VoidCallback onDockTap;
  final bool localizing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Section 1: Map Layers
          Row(
            children: [
              const Icon(Icons.layers_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Map Layers',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ValueListenableBuilder<Set<MapLayer>>(
            valueListenable: MapLayersController.instance,
            builder: (context, visible, _) {
              Widget layerTile(MapLayer layer, IconData icon, String title) {
                final isChecked = visible.contains(layer);
                return SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(icon,
                      size: 18,
                      color:
                          isChecked ? AppColors.primary : AppColors.textSecondary),
                  title: Text(title, style: const TextStyle(fontSize: 13)),
                  value: isChecked,
                  onChanged: (v) => MapLayersController.instance
                      .setVisible(layer, v),
                );
              }

              return Column(
                children: [
                  layerTile(MapLayer.dock, Icons.ev_station_rounded, 'Docking Station'),
                  layerTile(MapLayer.locations, Icons.place_rounded, 'Saved Locations'),
                  layerTile(MapLayer.path, Icons.route_rounded, 'Planned Path'),
                  layerTile(MapLayer.globalCostmap, Icons.grid_on_rounded, 'Global Costmap'),
                  layerTile(MapLayer.localCostmap, Icons.grid_4x4_rounded, 'Local Costmap'),
                  layerTile(MapLayer.laserScan, Icons.radar_rounded, 'LiDAR Points'),
                ],
              );
            },
          ),
          const Divider(height: AppSpacing.lg),

          // Section 2: Cartography Tools
          Row(
            children: [
              const Icon(Icons.handyman_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Cartography Tools',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonalIcon(
            onPressed: onLocalizeMap,
            icon: const Icon(Icons.touch_app_rounded, size: 16),
            label: const Text('Set 2D Pose on Map'),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DockPositionEditorScreen(),
              ),
            ),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text('Edit Dock & Standoff Pose'),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: localizing ? null : onLocalizeDock,
            icon: localizing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ev_station_rounded, size: 16),
            label: const Text('Relocalize at Dock'),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: localizing ? null : onGlobalRelocalize,
            icon: const Icon(Icons.blur_on_rounded, size: 16),
            label: const Text('Global Relocalize (Recovery)'),
          ),
          const SizedBox(height: AppSpacing.xs),
          FilledButton.icon(
            onPressed: onAddLocation,
            icon: const Icon(Icons.add_location_alt_rounded, size: 16),
            label: const Text('Save Location'),
          ),
          const Divider(height: AppSpacing.lg),

          // Section 3: Saved Locations on this Map
          Row(
            children: [
              const Icon(Icons.place_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Saved Locations',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ValueListenableBuilder<List<Map<String, dynamic>>?>(
                valueListenable: LocationsController.instance,
                builder: (context, locs, _) => Text(
                  '${locs?.length ?? 0}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ValueListenableBuilder<List<Map<String, dynamic>>?>(
            valueListenable: LocationsController.instance,
            builder: (context, locations, _) {
              if (locations == null || locations.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Center(
                    child: Text(
                      'No saved locations.\nClick "Save Location" above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                );
              }
              return Column(
                children: locations.map((loc) {
                  final name = loc['name'] as String? ?? '';
                  final x = (loc['x'] as num?)?.toDouble() ?? 0.0;
                  final y = (loc['y'] as num?)?.toDouble() ?? 0.0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                    elevation: 0,
                    color: AppColors.surfaceSunken,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      leading: const Icon(Icons.pin_drop_rounded,
                          size: 18, color: AppColors.primary),
                      title: Text(name,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textSecondary),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 16, color: AppColors.danger),
                            tooltip: 'Delete location',
                            onPressed: () => onLocationDelete?.call(loc),
                          ),
                          IconButton(
                            icon: const Icon(Icons.navigation_rounded,
                                size: 16, color: AppColors.accent),
                            tooltip: 'Navigate here',
                            onPressed: () => onLocationTap(loc),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
