import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nav_msgs/msg.dart' as nav_msgs;
import 'package:provider/provider.dart';

import '../../models/map_zone.dart';
import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/locations_controller.dart';
import '../../services/map_layers_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../services/zones_controller.dart';
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

  bool _zoneEditorMode = false;
  String? _selectedZoneId;
  int? _activeZoneVertexIndex;
  bool _savingZone = false;
  String? _activeMapName;

  bool _drawingLaneMode = false;
  List<Offset> _laneDraftPoints = [];
  double _laneDraftWidth = 1.2;
  String _laneDraftName = 'Preferred Lane';
  Offset? _mouseHoverWorld;

  ({double x, double y, double theta})? _dockPose;
  ({double x, double y, double theta})? _standoffPose;
  nav_msgs.OccupancyGrid? _activeGrid;
  Matrix4? _fittedMatrix;

  SdkApiService? _api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final api = _apiFor(context.read<ConnectionProvider>().robot?.ip);
      if (api != null) {
        LocationsController.instance.refresh(api);
        _loadActiveMapAndZones(api);
      }
      _loadDockPose();
    });
    // The layers selection, saved-locations list, and map zones are shared
    // app-wide — this screen needs to rebuild when either changes from
    // anywhere, not just from its own Layers panel or its own load.
    MapLayersController.instance.addListener(_onSharedStateChanged);
    LocationsController.instance.addListener(_onSharedStateChanged);
    ZonesController.instance.addListener(_onSharedStateChanged);
  }

  void _onSharedStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadActiveMapAndZones(SdkApiService api) async {
    try {
      final mapName = await api.getCurrentMap();
      if (mounted) setState(() => _activeMapName = mapName);
      await ZonesController.instance.refresh(api, map: mapName);
    } catch (_) {
      await ZonesController.instance.refresh(api);
    }
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

    // Resolve standoff from locations if available, else 0.70m forward along dock
    ({double x, double y, double theta})? standoff;
    final locs = LocationsController.instance.value ?? [];
    for (final loc in locs) {
      if (loc['name'] == 'Dock Standoff') {
        final x = (loc['x'] as num?)?.toDouble();
        final y = (loc['y'] as num?)?.toDouble();
        final theta = (loc['theta'] as num?)?.toDouble() ?? 0.0;
        if (x != null && y != null) {
          standoff = (x: x, y: y, theta: theta);
          break;
        }
      }
    }
    standoff ??= (
      x: dock.x + 0.70 * cos(dock.theta),
      y: dock.y + 0.70 * sin(dock.theta),
      theta: dock.theta,
    );

    setState(() {
      _dockPose = dock;
      _standoffPose = standoff;
    });
  }

  @override
  void dispose() {
    MapLayersController.instance.removeListener(_onSharedStateChanged);
    LocationsController.instance.removeListener(_onSharedStateChanged);
    ZonesController.instance.removeListener(_onSharedStateChanged);
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

  void _onZoneVertexMoved(int vertexIndex, double x, double y) {
    if (_selectedZoneId == null) return;
    final zones = List<MapZone>.from(ZonesController.instance.value);
    final zoneIdx = zones.indexWhere((z) => z.id == _selectedZoneId);
    if (zoneIdx == -1) return;
    final zone = zones[zoneIdx];
    if (zone.isCorridorLane) {
      final cl = List<Offset>.from(zone.laneCenterline);
      if (vertexIndex >= 0 && vertexIndex < cl.length) {
        cl[vertexIndex] = Offset(x, y);
        zones[zoneIdx] = zone.withLaneCenterline(cl);
        ZonesController.instance.value = zones;
        setState(() {});
      }
      return;
    }
    if (vertexIndex >= 0 && vertexIndex < zone.points.length) {
      final pts = List<Offset>.from(zone.points);
      pts[vertexIndex] = Offset(x, y);
      zones[zoneIdx] = zone.copyWith(points: pts);
      ZonesController.instance.value = zones;
      setState(() {});
    }
  }

  Future<void> _onZoneVertexMoveEnd() async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (_selectedZoneId == null || api == null) return;
    final zone = ZonesController.instance.value
        .where((z) => z.id == _selectedZoneId)
        .firstOrNull;
    if (zone == null) return;
    try {
      await ZonesController.instance.saveZone(api, zone, map: _activeMapName);
    } catch (e) {
      debugPrint('Failed to auto-save moved vertex: $e');
    }
  }

  Future<void> _onZoneVertexAdded(int insertAfterIndex, double x, double y) async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (_selectedZoneId == null || api == null) return;
    final zones = List<MapZone>.from(ZonesController.instance.value);
    final zoneIdx = zones.indexWhere((z) => z.id == _selectedZoneId);
    if (zoneIdx == -1) return;
    final zone = zones[zoneIdx];
    if (zone.isCorridorLane) {
      final cl = List<Offset>.from(zone.laneCenterline);
      final insertIdx = (insertAfterIndex + 1).clamp(0, cl.length);
      cl.insert(insertIdx, Offset(x, y));
      final updated = zone.withLaneCenterline(cl);
      zones[zoneIdx] = updated;
      ZonesController.instance.value = zones;
      setState(() => _activeZoneVertexIndex = insertIdx);
      try {
        await ZonesController.instance.saveZone(api, updated, map: _activeMapName);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save turn node: $e'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
      return;
    }
    final pts = List<Offset>.from(zone.points);
    final insertIdx = (insertAfterIndex + 1).clamp(0, pts.length);
    pts.insert(insertIdx, Offset(x, y));
    final updated = zone.copyWith(points: pts);
    zones[zoneIdx] = updated;
    ZonesController.instance.value = zones;
    setState(() => _activeZoneVertexIndex = insertIdx);
    try {
      await ZonesController.instance.saveZone(api, updated, map: _activeMapName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save vertex: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _onLaneCanvasClick(Offset world) {
    if (!_drawingLaneMode) return;
    setState(() {
      _laneDraftPoints = [..._laneDraftPoints, world];
    });
  }

  void _undoLanePoint() {
    if (_laneDraftPoints.isNotEmpty) {
      setState(() {
        _laneDraftPoints = List.of(_laneDraftPoints)..removeLast();
      });
    }
  }

  void _cancelDrawingLane() {
    setState(() {
      _drawingLaneMode = false;
      _laneDraftPoints = [];
      _mouseHoverWorld = null;
    });
  }

  Future<void> _finishDrawingLane() async {
    if (_laneDraftPoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please click at least 2 points to define the lane corridor.')),
      );
      return;
    }
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;

    final lane = MapZone.createPolylineLane(
      map: _activeMapName ?? 'default',
      centerline: _laneDraftPoints,
      width: _laneDraftWidth,
      name: _laneDraftName,
    );

    setState(() {
      _drawingLaneMode = false;
      _laneDraftPoints = [];
      _mouseHoverWorld = null;
    });

    try {
      await ZonesController.instance.saveZone(api, lane, map: _activeMapName);
      MapLayersController.instance.setVisible(MapLayer.zones, true);
      setState(() {
        _zoneEditorMode = true;
        _selectedZoneId = lane.id;
        _activeZoneVertexIndex = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Created Preferred Lane "${lane.name}". You can drag turn nodes or adjust width anytime.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save preferred lane: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _onUpdateLaneWidth(double width) async {
    if (_selectedZoneId == null) return;
    final zones = List<MapZone>.from(ZonesController.instance.value);
    final zoneIdx = zones.indexWhere((z) => z.id == _selectedZoneId);
    if (zoneIdx == -1) return;
    final zone = zones[zoneIdx];
    if (!zone.isCorridorLane) return;
    final updated = zone.withLaneWidth(width);
    zones[zoneIdx] = updated;
    ZonesController.instance.value = zones;
    setState(() {});
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api != null) {
      try {
        await ZonesController.instance.saveZone(api, updated, map: _activeMapName);
      } catch (e) {
        debugPrint('Failed to save updated lane width: $e');
      }
    }
  }

  Future<void> _saveActiveZone() async {
    if (_selectedZoneId == null) return;
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;
    final zone = ZonesController.instance.value
        .where((z) => z.id == _selectedZoneId)
        .firstOrNull;
    if (zone == null) return;
    setState(() => _savingZone = true);
    try {
      await ZonesController.instance.saveZone(api, zone, map: _activeMapName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Zone "${zone.name}" saved to robot.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save zone: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingZone = false);
    }
  }

  Future<void> _exitZoneEditor() async {
    if (_selectedZoneId != null) {
      await _saveActiveZone();
    }
    if (mounted) {
      setState(() {
        _zoneEditorMode = false;
        _selectedZoneId = null;
        _activeZoneVertexIndex = null;
      });
    }
  }

  Future<void> _deleteZone(String id) async {
    final zone = ZonesController.instance.value
        .where((z) => z.id == id)
        .firstOrNull;
    final name = zone?.name ?? id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Zone'),
        content: Text('Are you sure you want to remove "$name"?'),
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
      await ZonesController.instance.deleteZone(api, id, map: _activeMapName);
      if (mounted) {
        if (_selectedZoneId == id) {
          setState(() {
            _selectedZoneId = null;
            _activeZoneVertexIndex = null;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Zone "$name" deleted'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete zone "$name": $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _showAddZoneDialog() async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;

    final telemetry = context.read<RobotTelemetryProvider>();
    final centerX = telemetry.poseX ?? _dockPose?.x ?? 0.0;
    final centerY = telemetry.poseY ?? _dockPose?.y ?? 0.0;

    final result = await showDialog<_AddZoneResult>(
      context: context,
      builder: (_) => _AddZoneDialog(
        centerX: centerX,
        centerY: centerY,
        mapName: _activeMapName,
      ),
    );
    if (result == null || !mounted) return;

    if (result.startDrawingLane) {
      MapLayersController.instance.setVisible(MapLayer.zones, true);
      setState(() {
        _drawingLaneMode = true;
        _laneDraftPoints = [];
        _laneDraftWidth = result.laneWidth;
        _laneDraftName = result.laneName ?? 'Preferred Lane';
        _mouseHoverWorld = null;
        _selectedZoneId = null;
        _activeZoneVertexIndex = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Preferred Lane mode: Click on map to place start node, move mouse to preview, click to add turns.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final zone = result.zone;
    if (zone == null) return;

    try {
      await ZonesController.instance.saveZone(api, zone, map: _activeMapName);
      MapLayersController.instance.setVisible(MapLayer.zones, true);
      setState(() {
        _zoneEditorMode = true;
        _selectedZoneId = zone.id;
        _activeZoneVertexIndex = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Created zone "${zone.name}". Drag nodes or tap "+" on an edge to add more.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create zone: $e'),
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
    final target = (current * factor).clamp(0.02, 10.0);
    final adjust = target / current;
    final focal = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    _transformController.value = _transformController.value.clone()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(adjust, adjust, adjust, 1.0)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
  }

  void _onMapLoaded(nav_msgs.OccupancyGrid grid) {
    _activeGrid = grid;
    _fitMapToViewport(grid);
  }

  void _fitMapToViewport(nav_msgs.OccupancyGrid grid) {
    if (_viewportSize.isEmpty || grid.info.width <= 0 || grid.info.height <= 0) return;
    const padding = 36.0;
    final availableW = max(50.0, _viewportSize.width - padding * 2);
    final availableH = max(50.0, _viewportSize.height - padding * 2);
    final scaleW = availableW / grid.info.width;
    final scaleH = availableH / grid.info.height;
    final scale = min(scaleW, scaleH).clamp(0.02, 8.0);

    final mapScaledW = grid.info.width * scale;
    final mapScaledH = grid.info.height * scale;
    final tx = (_viewportSize.width - mapScaledW) / 2;
    final ty = (_viewportSize.height - mapScaledH) / 2;

    final matrix = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1.0);
    _fittedMatrix = matrix.clone();
    _transformController.value = matrix;
  }

  void _centerOnRobot() {
    final telemetry = context.read<RobotTelemetryProvider>();
    final rx = telemetry.poseX;
    final ry = telemetry.poseY;
    if (_viewportSize.isEmpty || _activeGrid == null || rx == null || ry == null) {
      if (_activeGrid != null) _fitMapToViewport(_activeGrid!);
      return;
    }
    final grid = _activeGrid!;
    final px = worldToPixel(grid, rx, ry);
    final currentScale = _transformController.value.getMaxScaleOnAxis().clamp(0.4, 4.0);
    final tx = _viewportSize.width / 2 - currentScale * px.dx;
    final ty = _viewportSize.height / 2 - currentScale * px.dy;
    _transformController.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(currentScale, currentScale, currentScale, 1.0);
  }

  Future<void> _openLayersPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Material(
            color: Colors.transparent,
            child: ValueListenableBuilder<Set<MapLayer>>(
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
                    tile(MapLayer.zones, Icons.polyline_rounded, 'Map Zones',
                        'Restricted areas, speed limits & corridors'),
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
          ),
        ),
      ),
    );
  }

  Future<void> _openSavedLocationsSheet() async {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Material(
        color: Colors.transparent,
        child: SafeArea(
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
    ),
  );
  }

  Future<void> _openLocalizeOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Material(
        color: Colors.transparent,
        child: Column(
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

    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _SaveLocationDialog(),
    );
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
      ),
      body: ros2 == null
          ? const Center(child: Text('Not connected.'))
          : isDesktop
              ? Row(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                _viewportSize = constraints.biggest;
                                if (_activeGrid != null && _transformController.value.isIdentity()) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (mounted && _activeGrid != null && _transformController.value.isIdentity()) {
                                      _fitMapToViewport(_activeGrid!);
                                    }
                                  });
                                }
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
                                    initialPose: telemetry.rawPose ??
                                        telemetry.rawOdomPose,
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
                                    standoffPoseOverride: _standoffPose,
                                    zones: visibleLayers.contains(MapLayer.zones)
                                        ? ZonesController.instance.value
                                        : const [],
                                    showZones:
                                        visibleLayers.contains(MapLayer.zones),
                                    zoneEditorMode: _zoneEditorMode,
                                    selectedZoneId: _selectedZoneId,
                                    activeZoneVertexIndex: _activeZoneVertexIndex,
                                    onZoneTap: (zone) {
                                      setState(() {
                                        _selectedZoneId = zone.id;
                                        _activeZoneVertexIndex = null;
                                        _zoneEditorMode = true;
                                      });
                                    },
                                    onZoneVertexSelected: (idx) {
                                      setState(
                                          () => _activeZoneVertexIndex = idx < 0 ? null : idx);
                                    },
                                    onZoneVertexMoved: _onZoneVertexMoved,
                                    onZoneVertexAdded: _onZoneVertexAdded,
                                    onZoneVertexMoveEnd: _onZoneVertexMoveEnd,
                                    drawingLaneMode: _drawingLaneMode,
                                    laneDraftPoints: _laneDraftPoints,
                                    laneDraftWidth: _laneDraftWidth,
                                    mouseHoverWorld: _mouseHoverWorld,
                                    onMapHoverWorld: (w) =>
                                        setState(() => _mouseHoverWorld = w),
                                    onMapClickWorld: _onLaneCanvasClick,
                                    onFinishLane: _finishDrawingLane,
                                    onMapLoaded: _onMapLoaded,
                                  ),
                                );
                              },
                            ),
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
                              onFitMap: () {
                                if (_activeGrid != null) {
                                  _fitMapToViewport(_activeGrid!);
                                } else if (_fittedMatrix != null) {
                                  _transformController.value =
                                      _fittedMatrix!.clone();
                                } else {
                                  _transformController.value =
                                      Matrix4.identity();
                                }
                              },
                              onCenterRobot:
                                  telemetry.localized ? _centerOnRobot : null,
                            ),
                          ),
                          if (_drawingLaneMode)
                            Positioned(
                              left: AppSpacing.md,
                              right: AppSpacing.md,
                              bottom: AppSpacing.md,
                              child: _DrawLaneHud(
                                laneName: _laneDraftName,
                                pointsCount: _laneDraftPoints.length,
                                corridorWidth: _laneDraftWidth,
                                onWidthChanged: (w) =>
                                    setState(() => _laneDraftWidth = w),
                                onUndo: _undoLanePoint,
                                onCancel: _cancelDrawingLane,
                                onFinish: _finishDrawingLane,
                              ),
                            )
                          else if (_zoneEditorMode && !_posePicking)
                            Positioned(
                              left: AppSpacing.md,
                              right: AppSpacing.md,
                              bottom: AppSpacing.md,
                              child: _ZoneEditorHud(
                                selectedZone: ZonesController.instance.value
                                    .where((z) => z.id == _selectedZoneId)
                                    .firstOrNull,
                                activeVertexIndex: _activeZoneVertexIndex,
                                saving: _savingZone,
                                mapName: _activeMapName,
                                onAddZone: _showAddZoneDialog,
                                onDeleteZone: _selectedZoneId != null
                                    ? () => _deleteZone(_selectedZoneId!)
                                    : null,
                                onUpdateLaneWidth: _onUpdateLaneWidth,
                                onDeselect: () async {
                                  if (_selectedZoneId != null) {
                                    await _saveActiveZone();
                                  }
                                  if (mounted) {
                                    setState(() {
                                      _selectedZoneId = null;
                                      _activeZoneVertexIndex = null;
                                    });
                                  }
                                },
                                onDone: _exitZoneEditor,
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
                      zoneEditorMode: _zoneEditorMode,
                      selectedZoneId: _selectedZoneId,
                      onToggleZoneEditor: () {
                        if (_zoneEditorMode) {
                          _exitZoneEditor();
                        } else {
                          setState(() => _zoneEditorMode = true);
                        }
                      },
                      onAddZone: _showAddZoneDialog,
                      onZoneTap: (z) => setState(() {
                        _selectedZoneId = z.id;
                        _activeZoneVertexIndex = null;
                        _zoneEditorMode = true;
                      }),
                      onZoneDelete: _deleteZone,
                    ),
                  ],
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          _viewportSize = constraints.biggest;
                          if (_activeGrid != null && _transformController.value.isIdentity()) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _activeGrid != null && _transformController.value.isIdentity()) {
                                _fitMapToViewport(_activeGrid!);
                              }
                            });
                          }
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
                              initialPose: telemetry.rawPose ??
                                  telemetry.rawOdomPose,
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
                              standoffPoseOverride: _standoffPose,
                              zones: visibleLayers.contains(MapLayer.zones)
                                  ? ZonesController.instance.value
                                  : const [],
                              showZones: visibleLayers.contains(MapLayer.zones),
                              zoneEditorMode: _zoneEditorMode,
                              selectedZoneId: _selectedZoneId,
                              activeZoneVertexIndex: _activeZoneVertexIndex,
                              onZoneTap: (zone) {
                                setState(() {
                                  _selectedZoneId = zone.id;
                                  _activeZoneVertexIndex = null;
                                  _zoneEditorMode = true;
                                });
                              },
                              onZoneVertexSelected: (idx) {
                                setState(() => _activeZoneVertexIndex = idx < 0 ? null : idx);
                              },
                              onZoneVertexMoved: _onZoneVertexMoved,
                              onZoneVertexAdded: _onZoneVertexAdded,
                              onZoneVertexMoveEnd: _onZoneVertexMoveEnd,
                              drawingLaneMode: _drawingLaneMode,
                              laneDraftPoints: _laneDraftPoints,
                              laneDraftWidth: _laneDraftWidth,
                              mouseHoverWorld: _mouseHoverWorld,
                              onMapHoverWorld: (w) =>
                                  setState(() => _mouseHoverWorld = w),
                              onMapClickWorld: _onLaneCanvasClick,
                              onFinishLane: _finishDrawingLane,
                              onMapLoaded: _onMapLoaded,
                            ),
                          );
                        },
                      ),
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
                          zoneEditorActive: _zoneEditorMode,
                          onLayers: _openLayersPanel,
                          onToggleZoneEditor: () {
                            if (_zoneEditorMode) {
                              _exitZoneEditor();
                            } else {
                              setState(() => _zoneEditorMode = true);
                            }
                          },
                          onZoomIn: () => _zoomBy(1.25),
                          onZoomOut: () => _zoomBy(0.8),
                          onFitMap: () {
                            if (_activeGrid != null) {
                              _fitMapToViewport(_activeGrid!);
                            } else if (_fittedMatrix != null) {
                              _transformController.value =
                                  _fittedMatrix!.clone();
                            } else {
                              _transformController.value = Matrix4.identity();
                            }
                          },
                          onCenterRobot:
                              telemetry.localized ? _centerOnRobot : null,
                          onLocalize: _localizing ? null : _openLocalizeOptions,
                          localizing: _localizing,
                          onAddLocation: _startAddLocationPicking,
                          onShowLocations: _openSavedLocationsSheet,
                        ),
                      ),
                    if (_drawingLaneMode)
                      Positioned(
                        left: AppSpacing.sm,
                        right: AppSpacing.sm,
                        bottom: AppSpacing.sm,
                        child: _DrawLaneHud(
                          laneName: _laneDraftName,
                          pointsCount: _laneDraftPoints.length,
                          corridorWidth: _laneDraftWidth,
                          onWidthChanged: (w) =>
                              setState(() => _laneDraftWidth = w),
                          onUndo: _undoLanePoint,
                          onCancel: _cancelDrawingLane,
                          onFinish: _finishDrawingLane,
                        ),
                      )
                    else if (_zoneEditorMode && !_posePicking)
                      Positioned(
                        left: AppSpacing.sm,
                        right: AppSpacing.sm,
                        bottom: AppSpacing.sm,
                        child: _ZoneEditorHud(
                          selectedZone: ZonesController.instance.value
                              .where((z) => z.id == _selectedZoneId)
                              .firstOrNull,
                          activeVertexIndex: _activeZoneVertexIndex,
                          saving: _savingZone,
                          mapName: _activeMapName,
                          onAddZone: _showAddZoneDialog,
                          onDeleteZone: _selectedZoneId != null
                              ? () => _deleteZone(_selectedZoneId!)
                              : null,
                          onUpdateLaneWidth: _onUpdateLaneWidth,
                          onDeselect: () async {
                            if (_selectedZoneId != null) {
                              await _saveActiveZone();
                            }
                            if (mounted) {
                              setState(() {
                                _selectedZoneId = null;
                                _activeZoneVertexIndex = null;
                              });
                            }
                          },
                          onDone: _exitZoneEditor,
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
    required this.zoneEditorActive,
    required this.onLayers,
    required this.onToggleZoneEditor,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitMap,
    this.onCenterRobot,
    required this.onLocalize,
    required this.localizing,
    required this.onAddLocation,
    required this.onShowLocations,
  });

  final bool layersActive;
  final bool zoneEditorActive;
  final VoidCallback onLayers;
  final VoidCallback onToggleZoneEditor;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitMap;
  final VoidCallback? onCenterRobot;
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
          const Divider(height: 1),
          _ControlButton(
            icon: Icons.polyline_rounded,
            tooltip: 'Map Zones Editor',
            onTap: onToggleZoneEditor,
            color: zoneEditorActive ? AppColors.accent : null,
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
          const Divider(height: 1),
          _ControlButton(
              icon: Icons.crop_free_rounded,
              tooltip: 'Fit map in view',
              onTap: onFitMap),
          if (onCenterRobot != null) ...[
            const Divider(height: 1),
            _ControlButton(
              icon: Icons.my_location_rounded,
              tooltip: 'Center on robot',
              onTap: onCenterRobot,
              color: AppColors.primary,
            ),
          ],
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
    required this.onFitMap,
    this.onCenterRobot,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitMap;
  final VoidCallback? onCenterRobot;

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
            tooltip: 'Fit map in view',
            icon: const Icon(Icons.crop_free_rounded, size: 18),
            onPressed: onFitMap,
          ),
          if (onCenterRobot != null) ...[
            const Divider(height: 1),
            IconButton(
              tooltip: 'Center on robot',
              icon: const Icon(Icons.my_location_rounded,
                  size: 18, color: AppColors.primary),
              onPressed: onCenterRobot,
            ),
          ],
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
    required this.zoneEditorMode,
    this.selectedZoneId,
    required this.onToggleZoneEditor,
    required this.onAddZone,
    required this.onZoneTap,
    this.onZoneDelete,
  });

  final VoidCallback onLocalizeMap;
  final VoidCallback onLocalizeDock;
  final VoidCallback onGlobalRelocalize;
  final VoidCallback onAddLocation;
  final void Function(Map<String, dynamic>) onLocationTap;
  final void Function(Map<String, dynamic>)? onLocationDelete;
  final VoidCallback onDockTap;
  final bool localizing;
  final bool zoneEditorMode;
  final String? selectedZoneId;
  final VoidCallback onToggleZoneEditor;
  final VoidCallback onAddZone;
  final void Function(MapZone zone) onZoneTap;
  final void Function(String id)? onZoneDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: Container(
        width: 320,
        decoration: const BoxDecoration(
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
                  layerTile(MapLayer.zones, Icons.polyline_rounded, 'Map Zones'),
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

          // Group 1: Waypoints & Saved Location Pin
          FilledButton.icon(
            onPressed: onAddLocation,
            icon: const Icon(Icons.add_location_alt_rounded, size: 16),
            label: const Text('Save Current Location Pin'),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Group 2: Map Zones (Speed limits, keep-out, work zones)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: zoneEditorMode
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : AppColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.polyline_rounded,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    const Text('Map Zones',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (zoneEditorMode)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('EDITING',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: onToggleZoneEditor,
                        icon: Icon(
                            zoneEditorMode
                                ? Icons.check_circle_outline_rounded
                                : Icons.edit_rounded,
                            size: 14),
                        label: Text(zoneEditorMode ? 'Done' : 'Edit Zones'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onAddZone,
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: const Text('Add Zone'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Group 3: Robot Localization (AMCL & Pose)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.gps_fixed_rounded,
                        size: 14, color: AppColors.success),
                    SizedBox(width: 6),
                    Text('Robot Localization',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                FilledButton.tonalIcon(
                  onPressed: onLocalizeMap,
                  icon: const Icon(Icons.touch_app_rounded, size: 15),
                  label: const Text('Set 2D Pose on Map'),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: localizing ? null : onLocalizeDock,
                        icon: localizing
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 1.5))
                            : const Icon(Icons.dock_rounded, size: 14),
                        label: const Text('At Dock'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: localizing ? null : onGlobalRelocalize,
                        icon: const Icon(Icons.blur_on_rounded, size: 14),
                        label: const Text('Global Search'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Group 4: Dock & Standoff Calibration
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DockPositionEditorScreen(),
              ),
            ),
            icon: const Icon(Icons.tune_rounded, size: 15),
            label: const Text('Calibrate Dock & Standoff Pose'),
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
          const Divider(height: AppSpacing.lg),

          // Section 4: Map Zones
          Row(
            children: [
              const Icon(Icons.polyline_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Map Zones',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ValueListenableBuilder<List<MapZone>>(
                valueListenable: ZonesController.instance,
                builder: (context, zones, _) => Text(
                  '${zones.length}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ValueListenableBuilder<List<MapZone>>(
            valueListenable: ZonesController.instance,
            builder: (context, zones, _) {
              if (zones.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Center(
                    child: Text(
                      'No zones on this map.\nClick "Add Map Zone" above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                );
              }
              return Column(
                children: zones.map((z) {
                  final isSelected = z.id == selectedZoneId;
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                    elevation: 0,
                    color: isSelected
                        ? z.color.withValues(alpha: 0.15)
                        : AppColors.surfaceSunken,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                          color: isSelected ? z.color : AppColors.border),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      leading: Icon(z.icon, size: 18, color: z.color),
                      title: Text(z.name,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500)),
                      subtitle: Text(
                        '${z.typeLabel}${z.speedLimitMps != null ? " (${z.speedLimitMps} m/s)" : ""} · ${z.points.length} nodes',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textSecondary),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 16, color: AppColors.danger),
                            tooltip: 'Delete zone',
                            onPressed: () => onZoneDelete?.call(z.id),
                          ),
                        ],
                      ),
                      onTap: () => onZoneTap(z),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}
}

class _DrawLaneHud extends StatelessWidget {
  const _DrawLaneHud({
    required this.laneName,
    required this.pointsCount,
    required this.corridorWidth,
    required this.onWidthChanged,
    required this.onUndo,
    required this.onCancel,
    required this.onFinish,
  });

  final String laneName;
  final int pointsCount;
  final double corridorWidth;
  final ValueSetter<double> onWidthChanged;
  final VoidCallback onUndo;
  final VoidCallback onCancel;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;

    return Card(
      elevation: 6,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.draw_rounded,
                          size: 15, color: Color(0xFF3B82F6)),
                      SizedBox(width: 4),
                      Text(
                        'Drawing Lane',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3B82F6)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  laneName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    pointsCount == 0
                        ? 'Click map to place start'
                        : pointsCount == 1
                            ? '1 node placed · click to add turn'
                            : '$pointsCount nodes placed',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Width: ',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded,
                          size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Decrease corridor width (-0.1m)',
                      onPressed: corridorWidth > 0.4
                          ? () => onWidthChanged(
                              (corridorWidth - 0.1).clamp(0.3, 5.0))
                          : null,
                    ),
                    Text(
                      '${corridorWidth.toStringAsFixed(1)}m',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3B82F6)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Increase corridor width (+0.1m)',
                      onPressed: corridorWidth < 5.0
                          ? () => onWidthChanged(
                              (corridorWidth + 0.1).clamp(0.3, 5.0))
                          : null,
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: pointsCount > 0 ? onUndo : null,
                  icon: const Icon(Icons.undo_rounded, size: 15),
                  label: const Text('Undo', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  onPressed: onCancel,
                  style:
                      TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton.icon(
                  onPressed: pointsCount >= 2 ? onFinish : null,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label:
                      const Text('Finish Lane', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: const Color(0xFF3B82F6),
                  ),
                ),
              ],
            ),
            if (isDesktop) ...[
              const SizedBox(height: 4),
              const Text(
                'Click map canvas to place nodes · Line follows mouse · Double-click to complete lane',
                style: TextStyle(fontSize: 10.5, color: AppColors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ZoneEditorHud extends StatelessWidget {
  const _ZoneEditorHud({
    required this.selectedZone,
    required this.activeVertexIndex,
    required this.saving,
    this.mapName,
    required this.onAddZone,
    this.onDeleteZone,
    this.onUpdateLaneWidth,
    required this.onDeselect,
    required this.onDone,
  });

  final MapZone? selectedZone;
  final int? activeVertexIndex;
  final bool saving;
  final String? mapName;
  final VoidCallback onAddZone;
  final VoidCallback? onDeleteZone;
  final ValueSetter<double>? onUpdateLaneWidth;
  final VoidCallback onDeselect;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final zone = selectedZone;
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;

    return Card(
      elevation: 6,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.polyline_rounded,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Zone Editor${mapName != null ? " · $mapName" : ""}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (zone != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: zone.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: zone.color.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(zone.icon, size: 13, color: zone.color),
                        const SizedBox(width: 4),
                        Text(
                          zone.name,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: zone.color),
                        ),
                        if (zone.speedLimitMps != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${zone.speedLimitMps} m/s',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: zone.color),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    zone.isCorridorLane
                        ? '${zone.laneCenterline.length} turns'
                        : '${zone.points.length} nodes',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  if (activeVertexIndex != null)
                    Text(
                      zone.isCorridorLane
                          ? ' (turn #${activeVertexIndex! + 1} active)'
                          : ' (node #${activeVertexIndex! + 1} active)',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent),
                    ),
                  if (zone.isCorridorLane) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Width: ',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary)),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded,
                              size: 16),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Decrease corridor width (-0.1m)',
                          onPressed: onUpdateLaneWidth != null && zone.laneWidth > 0.4
                              ? () => onUpdateLaneWidth!(
                                  (zone.laneWidth - 0.1).clamp(0.3, 5.0))
                              : null,
                        ),
                        Text(
                          '${zone.laneWidth.toStringAsFixed(1)}m',
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF3B82F6)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              size: 16),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Increase corridor width (+0.1m)',
                          onPressed: onUpdateLaneWidth != null && zone.laneWidth < 5.0
                              ? () => onUpdateLaneWidth!(
                                  (zone.laneWidth + 0.1).clamp(0.3, 5.0))
                              : null,
                        ),
                      ],
                    ),
                  ],
                ] else ...[
                  const Expanded(
                    child: Text(
                      'Tap a zone to edit, drag nodes to reshape, or tap "+" to add nodes.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                // Single Done button — saves the active zone (if any) then
                // exits editor mode. Shows a spinner while saving.
                FilledButton.icon(
                  onPressed: saving ? null : onDone,
                  icon: saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textOnPrimary),
                        )
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text(saving ? 'Saving…' : 'Done'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.success,
                  ),
                ),
              ],
            ),
            if (zone != null || !isDesktop) const SizedBox(height: AppSpacing.xs),
            if (zone != null)
              Row(
                children: [
                  Text(
                    zone.isCorridorLane
                        ? 'Drag turn nodes along centerline · Tap "+" to insert turn'
                        : 'Drag vertices to reshape · Tap "+" on edge to insert node',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textTertiary),
                  ),
                  const Spacer(),
                  if (onDeleteZone != null)
                    TextButton.icon(
                      onPressed: onDeleteZone,
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 15, color: AppColors.danger),
                      label: const Text('Delete Zone',
                          style: TextStyle(
                              color: AppColors.danger, fontSize: 12)),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: onDeselect,
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child: const Text('Deselect',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              )
            else if (!isDesktop)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: onAddZone,
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text('Add Zone',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}


class _AddZoneResult {
  final MapZone? zone;
  final bool startDrawingLane;
  final String? laneName;
  final double laneWidth;

  const _AddZoneResult.zone(MapZone this.zone)
      : startDrawingLane = false,
        laneName = null,
        laneWidth = 1.2;

  const _AddZoneResult.drawLane({
    required this.laneName,
    required this.laneWidth,
  })  : zone = null,
        startDrawingLane = true;
}

class _AddZoneDialog extends StatefulWidget {
  const _AddZoneDialog({
    required this.centerX,
    required this.centerY,
    this.mapName,
  });

  final double centerX;
  final double centerY;
  final String? mapName;

  @override
  State<_AddZoneDialog> createState() => _AddZoneDialogState();
}

class _AddZoneDialogState extends State<_AddZoneDialog> {
  final _nameController = TextEditingController();
  final _speedLimitController = TextEditingController(text: '0.08');
  ZoneType _selectedType = ZoneType.restricted;

  double _laneWidth = 1.2;

  @override
  void initState() {
    super.initState();
    _nameController.text = 'Restricted Zone 1';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _speedLimitController.dispose();
    super.dispose();
  }

  void _onTypeChanged(ZoneType type) {
    setState(() {
      _selectedType = type;
      if (_nameController.text.startsWith('Restricted') ||
          _nameController.text.startsWith('Speed Limit') ||
          _nameController.text.startsWith('Preferred') ||
          _nameController.text.startsWith('Caution')) {
        _nameController.text = switch (type) {
          ZoneType.restricted => 'Restricted Zone 1',
          ZoneType.speedLimit => 'Speed Limit Zone 1',
          ZoneType.preferredLane => 'Preferred Lane 1',
          ZoneType.workZone => 'Caution Zone 1',
        };
      }
    });
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (_selectedType == ZoneType.preferredLane) {
      Navigator.of(context).pop(_AddZoneResult.drawLane(
        laneName: name,
        laneWidth: _laneWidth,
      ));
      return;
    }

    double? speedLimit;
    if (_selectedType == ZoneType.speedLimit) {
      speedLimit = double.tryParse(_speedLimitController.text.trim()) ?? 0.08;
    }

    final zone = MapZone.createDefaultRectangle(
      map: widget.mapName ?? 'default',
      center: Offset(widget.centerX, widget.centerY),
      width: 2.0,
      height: 2.0,
      type: _selectedType,
      name: name,
      speedLimitMps: speedLimit,
    );

    Navigator.of(context).pop(_AddZoneResult.zone(zone));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Dialog Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _selectedType.defaultColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_selectedType.icon,
                          color: _selectedType.defaultColor, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Add Map Zone',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.mapName != null
                                ? 'Linked to map: ${widget.mapName}'
                                : 'Define virtual zones & speed limits',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Cancel',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),

                // Zone Name Field
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Zone Name',
                    hintText: 'e.g. Speed Limit Zone 1',
                    prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Zone Type Selection Section Header
                Row(
                  children: [
                    const Icon(Icons.category_rounded,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Select Zone Type',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),

                // Rich Zone Type Cards with Descriptions
                ...ZoneType.values.map((type) {
                  final isSelected = type == _selectedType;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _onTypeChanged(type),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? type.defaultColor.withValues(alpha: 0.08)
                              : AppColors.surfaceSunken,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? type.defaultColor
                                : AppColors.border,
                            width: isSelected ? 2.0 : 1.0,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: type.defaultColor.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(type.icon,
                                  color: type.defaultColor, size: 18),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        type.label,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isSelected
                                              ? type.defaultColor
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isSelected
                                                ? type.defaultColor
                                                : AppColors.textSecondary
                                                    .withValues(alpha: 0.4),
                                            width: isSelected ? 5.0 : 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    type.description,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                // Speed Limit Settings if Speed Limit Zone is selected
                if (_selectedType == ZoneType.speedLimit) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: ZoneType.speedLimit.defaultColor
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: ZoneType.speedLimit.defaultColor
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.speed_rounded,
                                size: 16, color: Color(0xFFF59E0B)),
                            const SizedBox(width: AppSpacing.xs),
                            const Text(
                              'Speed Restriction Setting',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFFF59E0B)),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'Select a preset speed limit or enter a custom velocity:',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _speedChip('0.05', '0.05 m/s (Crawl)'),
                            _speedChip('0.08', '0.08 m/s (Default)'),
                            _speedChip('0.15', '0.15 m/s (Slow)'),
                            _speedChip('0.25', '0.25 m/s (Moderate)'),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _speedLimitController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Maximum Linear Speed',
                            hintText: '0.08',
                            suffixText: 'm/s',
                            prefixIcon: const Icon(Icons.tune_rounded, size: 18),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Preferred Lane Line Tool Guidance
                if (_selectedType == ZoneType.preferredLane) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: ZoneType.preferredLane.defaultColor
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: ZoneType.preferredLane.defaultColor
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.edit_road_rounded,
                                size: 18, color: Color(0xFF3B82F6)),
                            SizedBox(width: AppSpacing.xs),
                            Text(
                              'Interactive Line Tool: Preferred Lane',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF3B82F6)),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'Draw your lane directly on the map canvas:\n'
                          '• Click on the map to place the start node.\n'
                          '• Move mouse — the line and corridor preview follow your cursor.\n'
                          '• Click again to add turn nodes.\n'
                          '• Double-click or click "Finish Lane" when done.',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              height: 1.4),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            const Text(
                              'Corridor Width: ',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                '${_laneWidth.toStringAsFixed(1)} m',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF3B82F6)),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline_rounded,
                                  size: 20),
                              tooltip: 'Decrease width (-0.1m)',
                              onPressed: _laneWidth > 0.4
                                  ? () => setState(() =>
                                      _laneWidth = (_laneWidth - 0.1).clamp(0.3, 5.0))
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline_rounded,
                                  size: 20),
                              tooltip: 'Increase width (+0.1m)',
                              onPressed: _laneWidth < 5.0
                                  ? () => setState(() =>
                                      _laneWidth = (_laneWidth + 0.1).clamp(0.3, 5.0))
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.md),

                // Contour Guidance Card for polygon zones
                if (_selectedType != ZoneType.preferredLane)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 16, color: AppColors.primary),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Zone will be placed as a 2m × 2m rectangle. In the editor, drag any node or tap "+" on an edge to contour into custom polygon shapes.',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),

                // Dialog Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _selectedType.defaultColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      icon: Icon(
                        _selectedType == ZoneType.preferredLane
                            ? Icons.draw_rounded
                            : _selectedType.icon,
                        size: 18,
                      ),
                      label: Text(_selectedType == ZoneType.preferredLane
                          ? 'Draw on Canvas'
                          : 'Create Zone'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _speedChip(String speed, String label) {
    final isSelected = _speedLimitController.text.trim() == speed;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      selectedColor: ZoneType.speedLimit.defaultColor.withValues(alpha: 0.25),
      onSelected: (_) {
        setState(() => _speedLimitController.text = speed);
      },
    );
  }
}

class _SaveLocationDialog extends StatefulWidget {
  const _SaveLocationDialog();

  @override
  State<_SaveLocationDialog> createState() => _SaveLocationDialogState();
}

class _SaveLocationDialogState extends State<_SaveLocationDialog> {
  final _controller = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _submitted = true;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save Location'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'e.g. Kitchen'),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (!_submitted) {
              _submitted = true;
              Navigator.of(context).pop();
            }
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
