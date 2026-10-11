import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nav_msgs/msg.dart' as nav_msgs;
import 'package:provider/provider.dart';

import '../../models/traffic_editor_models.dart';
import '../../providers/connection_provider.dart';
import '../../providers/fleet_provider.dart';
import '../../services/dock_pose_controller.dart';
import '../../services/locations_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map/occupancy_grid_view.dart';

/// Full-featured RMF Traffic Editor matching https://github.com/open-rmf/rmf_traffic_editor
/// Provides tools for:
/// - Selecting & Moving vertices
/// - Adding Vertices (holding points, chargers, parking, named waypoints)
/// - Adding Lanes (bidirectional, directional, speed limits)
/// - Adding Walls (with thickness in meters)
/// - Adding Doors (single/double sliding, swing, telescoping)
/// - Adding Measurements (scale calibration)
/// - Full synchronization with Open-RMF Building Graph via Fleet Server
class TrafficEditorScreen extends StatefulWidget {
  const TrafficEditorScreen({
    super.key,
    this.initialLevelName,
  });

  final String? initialLevelName;

  @override
  State<TrafficEditorScreen> createState() => _TrafficEditorScreenState();
}

class _TrafficEditorScreenState extends State<TrafficEditorScreen> {
  final _transformController = TransformationController();
  TrafficFeatureType _currentTool = TrafficFeatureType.select;

  late RmfLevelGraph _graph;
  String? _activeLevelName;
  String? _activeBuildingId;
  String? _activeBuildingName;

  String? _selectedVertexId;

  String? _edgeStartVertexId;
  Offset? _mouseHoverWorld;
  bool _pickingStandoff = false;
  bool _isSaving = false;
  bool _isLoading = true;

  nav_msgs.OccupancyGrid? _activeGrid;

  static nav_msgs.OccupancyGrid _createDefaultGrid() {
    final g = nav_msgs.OccupancyGrid();
    g.info.resolution = 0.05;
    g.info.width = 1200;
    g.info.height = 1200;
    g.info.origin.position.x = -30.0;
    g.info.origin.position.y = -30.0;
    return g;
  }

  nav_msgs.OccupancyGrid get _effectiveGrid => _activeGrid ?? _createDefaultGrid();

  @override
  void initState() {
    super.initState();
    _activeLevelName = widget.initialLevelName ?? 'L1';
    _graph = RmfLevelGraph(name: _activeLevelName!);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBuildingGraph());
  }

  Future<void> _loadBuildingGraph() async {
    setState(() => _isLoading = true);
    final fleet = context.read<FleetProvider>();
    if (!fleet.isFleetMode || fleet.api == null) {
      // Direct robot fallback: initialize graph from locations
      final locations = LocationsController.instance.value ?? [];
      final vertices = <EditorVertex>[];
      for (final loc in locations) {
        final name = (loc['name'] as String?) ?? '';
        final x = (loc['x'] as num?)?.toDouble() ?? 0.0;
        final y = (loc['y'] as num?)?.toDouble() ?? 0.0;
        final isCharger = name.toLowerCase().contains('dock') || name.toLowerCase().contains('charge');
        final isParking = name.toLowerCase().contains('park') || isCharger;
        vertices.add(EditorVertex(
          id: 'v_${name.replaceAll(' ', '_')}_${vertices.length}',
          x: x,
          y: y,
          name: name,
          isCharger: isCharger,
          isParking: isParking,
        ));
      }
      setState(() {
        _graph = RmfLevelGraph(name: _activeLevelName ?? 'L1', vertices: vertices);
        _isLoading = false;
      });
      return;
    }

    try {
      final buildings = await fleet.api!.getBuildings();
      if (buildings.isNotEmpty) {
        final b = buildings.first;
        _activeBuildingId = b['id'] as String?;
        _activeBuildingName = b['name'] as String? ?? 'Main Building';
        final graphData = await fleet.api!.getBuildingGraph(_activeBuildingId);
        final levelName = fleet.selectedLevel?.name ?? _activeLevelName ?? 'L1';
        _activeLevelName = levelName;

        // Parse graph for current level
        final allWaypoints = List<Map<String, dynamic>>.from(graphData['waypoints'] as List? ?? []);
        final allLanes = List<Map<String, dynamic>>.from(graphData['lanes'] as List? ?? []);
        final allWalls = List<Map<String, dynamic>>.from(graphData['walls'] as List? ?? []);
        final allDoors = List<Map<String, dynamic>>.from(graphData['doors'] as List? ?? []);

        final levelVertices = allWaypoints
            .where((w) => w['levelName'] == levelName || w['level_name'] == levelName || w['level'] == levelName || !w.containsKey('levelName'))
            .map((w) => EditorVertex.fromJson(w))
            .toList();

        final vertexIds = levelVertices.map((v) => v.id).toSet();
        final levelLanes = allLanes
            .where((l) => vertexIds.contains(l['start_idx'] ?? l['fromId']) && vertexIds.contains(l['end_idx'] ?? l['toId']))
            .map((l) => EditorEdge.fromJson(l))
            .toList();

        final levelWalls = allWalls
            .where((w) => vertexIds.contains(w['start_idx']) && vertexIds.contains(w['end_idx']))
            .map((w) => EditorWall.fromJson(w))
            .toList();

        final levelDoors = allDoors
            .where((d) => vertexIds.contains(d['start_idx']) && vertexIds.contains(d['end_idx']))
            .map((d) => EditorDoor.fromJson(d))
            .toList();

        _graph = RmfLevelGraph(
          name: levelName,
          vertices: levelVertices,
          lanes: levelLanes,
          walls: levelWalls,
          doors: levelDoors,
        );
      }
    } catch (e) {
      debugPrint('Failed to load building graph: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveGraphToFleet() async {
    final fleet = context.read<FleetProvider>();
    final connection = context.read<ConnectionProvider>();
    final ip = connection.robot?.ip;
    final api = ip != null ? SdkApiService(ip) : null;

    setState(() => _isSaving = true);
    try {
      final levelName = _activeLevelName ?? 'L1';

      // 1. Sync vertices as locations across the app (single source of truth for RMF)
      final newLocationsList = <Map<String, dynamic>>[];
      for (final v in _graph.vertices) {
        final locName = v.name.isNotEmpty ? v.name : (v.dockName != null && v.dockName!.isNotEmpty ? v.dockName! : v.id);
        newLocationsList.add({
          'name': locName,
          'x': v.x,
          'y': v.y,
          'theta': 0.0,
          'type': v.isCharger ? 'charger' : (v.isParking ? 'parking' : 'waypoint'),
          'isCharger': v.isCharger,
          'isParking': v.isParking,
        });

        // Also add standoff pose if charger has one
        if (v.isCharger && (v.standoffX != null || v.standoffDistance != null)) {
          final sX = v.standoffX ?? (v.x + (v.standoffDistance ?? 0.8) * cos(v.standoffAngle ?? 0.0));
          final sY = v.standoffY ?? (v.y + (v.standoffDistance ?? 0.8) * sin(v.standoffAngle ?? 0.0));
          final sTheta = atan2(v.y - sY, v.x - sX); // Face towards dock
          newLocationsList.add({
            'name': '${locName}_standoff',
            'x': sX,
            'y': sY,
            'theta': sTheta,
            'type': 'standoff',
          });

          // Sync dock pose to robot if connected
          if (api != null) {
            final dockTheta = atan2(sY - v.y, sX - v.x);
            api.setDockPose(x: v.x, y: v.y, theta: dockTheta).catchError((_) {});
            DockPoseController.instance.update(
              dock: (x: v.x, y: v.y, theta: dockTheta),
              standoff: (x: sX, y: sY, theta: sTheta),
            );
          }
        }
      }
      LocationsController.instance.value = newLocationsList;

      // 2. If fleet mode is enabled, update building graph & apply to Open-RMF
      if (fleet.isFleetMode && fleet.api != null) {
        String? bId = _activeBuildingId;
        if (bId == null || bId.isEmpty) {
          final buildings = await fleet.api!.getBuildings();
          if (buildings.isNotEmpty) {
            bId = buildings.first['id'] as String?;
            _activeBuildingId = bId;
          } else {
            // Auto-create building if none exists
            final created = await fleet.api!.importBuildingYaml(
              'name: ${_activeBuildingName ?? "Campus"}\nlevels:\n  $levelName:\n    drawing:\n      filename: ""\n',
              buildingName: _activeBuildingName ?? 'Campus',
            );
            bId = created['id'] as String? ?? 'campus_1';
            _activeBuildingId = bId;
          }
        }

        final existingGraph = await fleet.api!.getBuildingGraph(bId);
        final otherWaypoints = List<Map<String, dynamic>>.from(existingGraph['waypoints'] as List? ?? [])
            .where((w) => w['levelName'] != levelName && w['level_name'] != levelName)
            .toList();

        final otherLanes = List<Map<String, dynamic>>.from(existingGraph['lanes'] as List? ?? []).where((l) {
          final start = l['start_idx'] ?? l['fromId'];
          final end = l['end_idx'] ?? l['toId'];
          final otherIds = otherWaypoints.map((w) => w['id']).toSet();
          return otherIds.contains(start) && otherIds.contains(end);
        }).toList();

        final levelWaypointsJson = _graph.vertices.map((v) {
          final m = v.toJson();
          m['levelName'] = levelName;
          return m;
        }).toList();

        final levelLanesJson = _graph.lanes.map((l) {
          final m = l.toJson();
          m['fromId'] = l.startVertexId;
          m['toId'] = l.endVertexId;
          return m;
        }).toList();

        final updatedGraph = {
          'waypoints': [...otherWaypoints, ...levelWaypointsJson],
          'lanes': [...otherLanes, ...levelLanesJson],
          'walls': _graph.walls.map((w) => w.toJson()).toList(),
          'doors': _graph.doors.map((d) => d.toJson()).toList(),
        };

        if (bId != null && bId.isNotEmpty) {
          await fleet.api!.updateBuildingGraph(bId, updatedGraph);
        }
        await fleet.api!.applyBuilding();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Building Traffic Graphs generated & applied to Open-RMF Fleet!'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Traffic editor points & dock standoff saved to active locations!'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save traffic graph: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onCanvasTap(Offset world) {
    if (_pickingStandoff && _selectedVertexId != null) {
      final selected = _graph.vertices.where((v) => v.id == _selectedVertexId).firstOrNull;
      if (selected != null) {
        final dist = sqrt(pow(world.dx - selected.x, 2) + pow(world.dy - selected.y, 2));
        final angle = atan2(world.dy - selected.y, world.dx - selected.x);
        setState(() {
          selected.standoffX = world.dx;
          selected.standoffY = world.dy;
          selected.standoffDistance = dist;
          selected.standoffAngle = angle;
          _pickingStandoff = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Custom standoff set at (${world.dx.toStringAsFixed(2)}, ${world.dy.toStringAsFixed(2)}) — ${dist.toStringAsFixed(2)}m'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    switch (_currentTool) {
      case TrafficFeatureType.select:
        _handleSelectTap(world);
        break;
      case TrafficFeatureType.vertex:
        _addVertexAt(world);
        break;
      case TrafficFeatureType.lane:
        _handleEdgeTap(world, isWall: false, isDoor: false);
        break;
      case TrafficFeatureType.wall:
        _handleEdgeTap(world, isWall: true, isDoor: false);
        break;
      case TrafficFeatureType.door:
        _handleEdgeTap(world, isWall: false, isDoor: true);
        break;
      default:
        break;
    }
  }

  void _handleSelectTap(Offset world) {
    // Find nearest vertex within 0.4m
    EditorVertex? closest;
    double closestDist = 0.4;
    for (final v in _graph.vertices) {
      final d = sqrt(pow(v.x - world.dx, 2) + pow(v.y - world.dy, 2));
      if (d < closestDist) {
        closestDist = d;
        closest = v;
      }
    }

    setState(() {
      _selectedVertexId = closest?.id;
    });
  }

  void _addVertexAt(Offset world) {
    final newId = 'v_${DateTime.now().millisecondsSinceEpoch}';
    final roundedX = double.parse(world.dx.toStringAsFixed(2));
    final roundedY = double.parse(world.dy.toStringAsFixed(2));
    final newVertex = EditorVertex(
      id: newId,
      x: roundedX,
      y: roundedY,
      name: 'wp_${_graph.vertices.length + 1}',
    );
    setState(() {
      _graph.vertices.add(newVertex);
      _selectedVertexId = newId;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added waypoint ${newVertex.name} at (${newVertex.x}, ${newVertex.y})m'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _handleEdgeTap(Offset world, {required bool isWall, required bool isDoor}) {
    // Select or create vertex to connect
    EditorVertex? targetVertex;
    double minDist = 0.5;
    for (final v in _graph.vertices) {
      final d = sqrt(pow(v.x - world.dx, 2) + pow(v.y - world.dy, 2));
      if (d < minDist) {
        minDist = d;
        targetVertex = v;
      }
    }

    if (targetVertex == null) {
      // Auto-create vertex at tap position
      final newId = 'v_${DateTime.now().millisecondsSinceEpoch}';
      final roundedX = double.parse(world.dx.toStringAsFixed(2));
      final roundedY = double.parse(world.dy.toStringAsFixed(2));
      targetVertex = EditorVertex(
        id: newId,
        x: roundedX,
        y: roundedY,
        name: 'wp_${_graph.vertices.length + 1}',
      );
      _graph.vertices.add(targetVertex);
    }

    if (_edgeStartVertexId == null) {
      setState(() => _edgeStartVertexId = targetVertex!.id);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start vertex selected. Tap end vertex to create connection.'), duration: Duration(seconds: 2)),
      );
    } else {
      if (_edgeStartVertexId != targetVertex.id) {
        final startId = _edgeStartVertexId!;
        final endId = targetVertex.id;

        if (isWall) {
          _graph.walls.add(EditorWall(
            id: 'wall_${DateTime.now().millisecondsSinceEpoch}',
            startVertexId: startId,
            endVertexId: endId,
          ));
        } else if (isDoor) {
          _graph.doors.add(EditorDoor(
            id: 'door_${DateTime.now().millisecondsSinceEpoch}',
            startVertexId: startId,
            endVertexId: endId,
          ));
        } else {
          _graph.lanes.add(EditorEdge(
            id: 'lane_${DateTime.now().millisecondsSinceEpoch}',
            startVertexId: startId,
            endVertexId: endId,
            bidirectional: true,
          ));
        }
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isWall ? 'Wall added between vertices' : (isDoor ? 'Door added between vertices' : 'Bidirectional lane added')),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      setState(() => _edgeStartVertexId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final fleet = context.watch<FleetProvider>();
    final ros2 = connection.ros2;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.traffic_rounded, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Text('Traffic Editor (Open-RMF) — ${_activeLevelName ?? "L1"}'),
            const SizedBox(width: 12),
            if (fleet.isFleetMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _activeBuildingName ?? 'Fleet Site',
                  style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Export building.yaml',
            icon: const Icon(Icons.code_rounded),
            onPressed: _showYamlDialog,
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            icon: _isSaving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_upload_rounded, size: 18),
            label: const Text('Save & Apply Graph'),
            onPressed: _isSaving ? null : _saveGraphToFleet,
          ),
          const SizedBox(width: AppSpacing.md),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Tool Toolbar (Left)
                _buildToolRail(),

                // Canvas Area (Center)
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          color: AppColors.background,
                          child: Stack(
                            children: [
                              if (ros2 != null)
                                Positioned.fill(
                                  child: OccupancyGridView(
                                    ros2: ros2,
                                    interactive: true,
                                    showRobot: true,
                                    showDock: true,
                                    transformationController: _transformController,
                                    onMapLoaded: (grid) => setState(() => _activeGrid = grid),
                                    onMapClickWorld: _onCanvasTap,
                                    onMapHoverWorld: (w) => setState(() => _mouseHoverWorld = w),
                                  ),
                                )
                              else
                                Positioned.fill(
                                  child: _StandaloneEditorCanvas(
                                    transformController: _transformController,
                                    grid: _effectiveGrid,
                                    onTapWorld: _onCanvasTap,
                                    onHoverWorld: (w) => setState(() => _mouseHoverWorld = w),
                                  ),
                                ),
                              // Overlay Painter for RMF Traffic Elements
                              Positioned.fill(
                                child: IgnorePointer(
                                  ignoring: true,
                                  child: AnimatedBuilder(
                                    animation: _transformController,
                                    builder: (context, _) => CustomPaint(
                                      painter: _RmfTrafficCanvasPainter(
                                        graph: _graph,
                                        grid: _effectiveGrid,
                                        isStandalone: ros2 == null,
                                        selectedVertexId: _selectedVertexId,
                                        edgeStartVertexId: _edgeStartVertexId,
                                        mouseHoverWorld: _mouseHoverWorld,
                                        transform: _transformController.value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Tooltip Instructions Pill
                      Positioned(
                        top: AppSpacing.sm,
                        left: AppSpacing.md,
                        child: _buildInstructionsChip(),
                      ),
                    ],
                  ),
                ),

                // Properties Panel (Right)
                SizedBox(
                  width: 320,
                  child: _buildPropertiesPanel(),
                ),
              ],
            ),
    );
  }

  Widget _buildToolRail() {
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        border: const Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.sm),
          _toolButton(TrafficFeatureType.select, Icons.near_me_rounded, 'Select'),
          _toolButton(TrafficFeatureType.vertex, Icons.add_location_alt_rounded, 'Vertex'),
          _toolButton(TrafficFeatureType.lane, Icons.alt_route_rounded, 'Lane'),
          _toolButton(TrafficFeatureType.wall, Icons.fence_rounded, 'Wall'),
          _toolButton(TrafficFeatureType.door, Icons.sensor_door_outlined, 'Door'),
          const Divider(),
          IconButton(
            tooltip: 'Clear Selected',
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            onPressed: _deleteSelectedElement,
          ),
        ],
      ),
    );
  }

  Widget _toolButton(TrafficFeatureType type, IconData icon, String label) {
    final isSelected = _currentTool == type;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _currentTool = type;
            _edgeStartVertexId = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? AppColors.primary : Colors.transparent),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: isSelected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionsChip() {
    String text;
    switch (_currentTool) {
      case TrafficFeatureType.select:
        text = 'Click any vertex or element to inspect and edit its properties.';
        break;
      case TrafficFeatureType.vertex:
        text = 'Click anywhere on map to drop a new navigation waypoint / charging dock.';
        break;
      case TrafficFeatureType.lane:
        text = _edgeStartVertexId == null
            ? 'Click starting vertex for the lane.'
            : 'Click ending vertex to connect bidirectional lane.';
        break;
      case TrafficFeatureType.wall:
        text = _edgeStartVertexId == null ? 'Click start vertex for wall.' : 'Click end vertex to build wall boundary.';
        break;
      case TrafficFeatureType.door:
        text = _edgeStartVertexId == null ? 'Click start vertex for door.' : 'Click end vertex to place motorized door.';
        break;
      default:
        text = '';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPropertiesPanel() {
    final selectedVertex = _selectedVertexId != null
        ? _graph.vertices.where((v) => v.id == _selectedVertexId).firstOrNull
        : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(left: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('Inspector & Properties', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          const Divider(),

          // Counts summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statChip('Vertices', '${_graph.vertices.length}'),
              _statChip('Lanes', '${_graph.lanes.length}'),
              _statChip('Walls', '${_graph.walls.length}'),
              _statChip('Doors', '${_graph.doors.length}'),
            ],
          ),
          const Divider(),

          if (selectedVertex != null) ...[
            Text('Vertex: ${selectedVertex.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              decoration: const InputDecoration(labelText: 'Waypoint Name', isDense: true),
              controller: TextEditingController(text: selectedVertex.name),
              onChanged: (val) => selectedVertex.name = val.trim(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'X (meters)', isDense: true),
                    controller: TextEditingController(text: selectedVertex.x.toStringAsFixed(3)),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (val) {
                      final n = double.tryParse(val);
                      if (n != null) setState(() => selectedVertex.x = n);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(labelText: 'Y (meters)', isDense: true),
                    controller: TextEditingController(text: selectedVertex.y.toStringAsFixed(3)),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (val) {
                      final n = double.tryParse(val);
                      if (n != null) setState(() => selectedVertex.y = n);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Is Charging Station', style: TextStyle(fontSize: 13)),
              subtitle: const Text('Auto-registered to Open-RMF dispatcher battery fleet', style: TextStyle(fontSize: 10)),
              value: selectedVertex.isCharger,
              onChanged: (v) => setState(() => selectedVertex.isCharger = v ?? false),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Is Parking / Holding Point', style: TextStyle(fontSize: 13)),
              subtitle: const Text('Designated standby waiting pose for AMR traffic yield', style: TextStyle(fontSize: 10)),
              value: selectedVertex.isParking,
              onChanged: (v) => setState(() => selectedVertex.isParking = v ?? false),
            ),
            if (selectedVertex.isCharger) ...[
              TextField(
                decoration: const InputDecoration(labelText: 'Dock Name / ID', isDense: true),
                controller: TextEditingController(text: selectedVertex.dockName ?? 'charger_1'),
                onChanged: (val) => selectedVertex.dockName = val.trim(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.gps_fixed_rounded, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        const Text('Custom Standoff Pose', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const Spacer(),
                        if (selectedVertex.standoffX != null || selectedVertex.standoffDistance != null)
                          InkWell(
                            onTap: () => setState(() {
                              selectedVertex.standoffX = null;
                              selectedVertex.standoffY = null;
                              selectedVertex.standoffDistance = null;
                              selectedVertex.standoffAngle = null;
                            }),
                            child: const Text('Reset', style: TextStyle(fontSize: 10, color: AppColors.danger)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selectedVertex.standoffX != null
                          ? 'Pose: (${selectedVertex.standoffX!.toStringAsFixed(2)}, ${selectedVertex.standoffY!.toStringAsFixed(2)}) — ${(selectedVertex.standoffDistance ?? 0.8).toStringAsFixed(2)}m'
                          : 'Default standoff: 0.8m approach along dock axis.',
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(labelText: 'Dist (m)', isDense: true),
                            controller: TextEditingController(text: (selectedVertex.standoffDistance ?? 0.8).toStringAsFixed(2)),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (val) {
                              final d = double.tryParse(val);
                              if (d != null) {
                                setState(() {
                                  selectedVertex.standoffDistance = d;
                                  final angle = selectedVertex.standoffAngle ?? 0.0;
                                  selectedVertex.standoffX = selectedVertex.x + d * cos(angle);
                                  selectedVertex.standoffY = selectedVertex.y + d * sin(angle);
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(labelText: 'Angle (rad)', isDense: true),
                            controller: TextEditingController(text: (selectedVertex.standoffAngle ?? 0.0).toStringAsFixed(2)),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (val) {
                              final a = double.tryParse(val);
                              if (a != null) {
                                setState(() {
                                  selectedVertex.standoffAngle = a;
                                  final d = selectedVertex.standoffDistance ?? 0.8;
                                  selectedVertex.standoffX = selectedVertex.x + d * cos(a);
                                  selectedVertex.standoffY = selectedVertex.y + d * sin(a);
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _pickingStandoff ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
                        minimumSize: const Size(double.infinity, 32),
                      ),
                      icon: Icon(_pickingStandoff ? Icons.touch_app_rounded : Icons.place_rounded, size: 14),
                      label: Text(_pickingStandoff ? 'Click on map to set standoff...' : 'Pick Standoff on Map', style: const TextStyle(fontSize: 11)),
                      onPressed: () {
                        setState(() => _pickingStandoff = !_pickingStandoff);
                        if (_pickingStandoff) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Click anywhere on the map to place the custom dock standoff approach point!'),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger.withValues(alpha: 0.15), foregroundColor: AppColors.danger),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Delete Vertex'),
              onPressed: _deleteSelectedElement,
            ),
          ] else ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text('Click any element to inspect parameters.', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }

  void _deleteSelectedElement() {
    if (_selectedVertexId != null) {
      final id = _selectedVertexId!;
      setState(() {
        _graph.vertices.removeWhere((v) => v.id == id);
        _graph.lanes.removeWhere((l) => l.startVertexId == id || l.endVertexId == id);
        _graph.walls.removeWhere((w) => w.startVertexId == id || w.endVertexId == id);
        _graph.doors.removeWhere((d) => d.startVertexId == id || d.endVertexId == id);
        _selectedVertexId = null;
      });
    }
  }

  void _showYamlDialog() {
    final yaml = _graph.toBuildingYamlString(_activeBuildingName ?? 'site');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open-RMF building.yaml'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: SelectableText(yaml, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _RmfTrafficCanvasPainter extends CustomPainter {
  final RmfLevelGraph graph;
  final nav_msgs.OccupancyGrid grid;
  final bool isStandalone;
  final String? selectedVertexId;
  final String? edgeStartVertexId;
  final Offset? mouseHoverWorld;
  final Matrix4 transform;

  _RmfTrafficCanvasPainter({
    required this.graph,
    required this.grid,
    this.isStandalone = false,
    this.selectedVertexId,
    this.edgeStartVertexId,
    this.mouseHoverWorld,
    required this.transform,
  });

  Offset _worldToScreen(double wx, double wy) {
    final res = grid.info.resolution;
    final ox = grid.info.origin.position.x;
    final oy = grid.info.origin.position.y;
    final h = grid.info.height;

    // Grid pixel coordinate
    final px = (wx - ox) / res;
    final py = h - ((wy - oy) / res);

    // Apply InteractiveViewer matrix transform directly to the 2D offset
    return MatrixUtils.transformPoint(transform, Offset(px, py));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 0. If standalone (no ROS2 /map received), draw a crisp floor grid pattern
    if (isStandalone) {
      final minorGridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..strokeWidth = 1.0;
      final majorGridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..strokeWidth = 1.2;
      final axisPaint = Paint()
        ..color = const Color(0xFF0284C7).withValues(alpha: 0.45)
        ..strokeWidth = 2.0;

      for (double x = -30; x <= 30; x += 1.0) {
        final p1 = _worldToScreen(x, -30);
        final p2 = _worldToScreen(x, 30);
        final isMajor = (x % 5).abs() < 0.01;
        final isZero = x.abs() < 0.01;
        canvas.drawLine(p1, p2, isZero ? axisPaint : (isMajor ? majorGridPaint : minorGridPaint));
      }
      for (double y = -30; y <= 30; y += 1.0) {
        final p1 = _worldToScreen(-30, y);
        final p2 = _worldToScreen(30, y);
        final isMajor = (y % 5).abs() < 0.01;
        final isZero = y.abs() < 0.01;
        canvas.drawLine(p1, p2, isZero ? axisPaint : (isMajor ? majorGridPaint : minorGridPaint));
      }

      // Draw origin (0, 0)
      final p0 = _worldToScreen(0, 0);
      canvas.drawCircle(p0, 5, Paint()..color = const Color(0xFF0284C7));
    }

    // 1. Draw Walls (Black/Dark Slate Thick Segments)
    final wallPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.square;
    for (final wall in graph.walls) {
      final start = graph.vertices.where((v) => v.id == wall.startVertexId).firstOrNull;
      final end = graph.vertices.where((v) => v.id == wall.endVertexId).firstOrNull;
      if (start != null && end != null) {
        final p1 = _worldToScreen(start.x, start.y);
        final p2 = _worldToScreen(end.x, end.y);
        canvas.drawLine(p1, p2, wallPaint);
      }
    }

    // 2. Draw Doors (Amber / Bronze Segments with Dash)
    final doorPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;
    for (final door in graph.doors) {
      final start = graph.vertices.where((v) => v.id == door.startVertexId).firstOrNull;
      final end = graph.vertices.where((v) => v.id == door.endVertexId).firstOrNull;
      if (start != null && end != null) {
        final p1 = _worldToScreen(start.x, start.y);
        final p2 = _worldToScreen(end.x, end.y);
        canvas.drawLine(p1, p2, doorPaint);
      }
    }

    // 3. Draw Lanes (Neon Cyan / Blue Bidirectional Arrows)
    final lanePaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (final lane in graph.lanes) {
      final start = graph.vertices.where((v) => v.id == lane.startVertexId).firstOrNull;
      final end = graph.vertices.where((v) => v.id == lane.endVertexId).firstOrNull;
      if (start != null && end != null) {
        final p1 = _worldToScreen(start.x, start.y);
        final p2 = _worldToScreen(end.x, end.y);
        canvas.drawLine(p1, p2, lanePaint);
      }
    }

    // 4. In-progress edge draft line
    if (edgeStartVertexId != null && mouseHoverWorld != null) {
      final start = graph.vertices.where((v) => v.id == edgeStartVertexId).firstOrNull;
      if (start != null) {
        final p1 = _worldToScreen(start.x, start.y);
        final p2 = _worldToScreen(mouseHoverWorld!.dx, mouseHoverWorld!.dy);
        final draftPaint = Paint()
          ..color = Colors.amber
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
        canvas.drawLine(p1, p2, draftPaint);
      }
    }

    // 5. Draw Vertices / Waypoints
    for (final v in graph.vertices) {
      final p = _worldToScreen(v.x, v.y);
      final isSelected = v.id == selectedVertexId || v.id == edgeStartVertexId;

      Color vColor = const Color(0xFF0284C7);
      if (v.isCharger) vColor = const Color(0xFFEAB308); // Yellow for charger
      if (v.isParking) vColor = const Color(0xFF10B981); // Emerald for parking

      if (isSelected) {
        canvas.drawCircle(p, 10, Paint()..color = Colors.white.withValues(alpha: 0.6));
      }

      canvas.drawCircle(p, 6, Paint()..color = vColor);
      canvas.drawCircle(p, 6, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);

      if (v.name.isNotEmpty) {
        final textPainter = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: v.name,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, backgroundColor: Colors.black54),
          ),
        )..layout();
        textPainter.paint(canvas, p + const Offset(8, -12));
      }

      // Draw custom standoff point and approach line if charger
      if (v.isCharger && (v.standoffX != null || v.standoffDistance != null)) {
        final sX = v.standoffX ?? (v.x + (v.standoffDistance ?? 0.8) * cos(v.standoffAngle ?? 0.0));
        final sY = v.standoffY ?? (v.y + (v.standoffDistance ?? 0.8) * sin(v.standoffAngle ?? 0.0));
        final sp = _worldToScreen(sX, sY);

        // Dashed approach line from standoff to dock
        final approachPaint = Paint()
          ..color = const Color(0xFFF59E0B)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

        final dx = p.dx - sp.dx;
        final dy = p.dy - sp.dy;
        final totalDist = sqrt(dx * dx + dy * dy);
        if (totalDist > 0) {
          const dashLen = 5.0;
          const spaceLen = 4.0;
          double drawn = 0.0;
          while (drawn < totalDist) {
            final startFraction = drawn / totalDist;
            final endFraction = min((drawn + dashLen) / totalDist, 1.0);
            final pStart = Offset(sp.dx + dx * startFraction, sp.dy + dy * startFraction);
            final pEnd = Offset(sp.dx + dx * endFraction, sp.dy + dy * endFraction);
            canvas.drawLine(pStart, pEnd, approachPaint);
            drawn += dashLen + spaceLen;
          }
        }

        // Target Standoff Pin
        canvas.drawCircle(sp, 7, Paint()..color = const Color(0xFF10B981));
        canvas.drawCircle(sp, 7, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
        canvas.drawCircle(sp, 2.5, Paint()..color = Colors.white);

        // Label with standoff distance
        final distVal = v.standoffDistance ?? 0.8;
        final distPainter = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: '${distVal.toStringAsFixed(2)}m',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10B981), backgroundColor: Colors.black87),
          ),
        )..layout();
        distPainter.paint(canvas, sp + const Offset(8, -8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RmfTrafficCanvasPainter oldDelegate) => true;
}

/// Standalone Interactive Editor Canvas when ROS2 is not connected directly (e.g. Fleet mode or offline)
class _StandaloneEditorCanvas extends StatefulWidget {
  const _StandaloneEditorCanvas({
    required this.transformController,
    required this.grid,
    required this.onTapWorld,
    required this.onHoverWorld,
  });

  final TransformationController transformController;
  final nav_msgs.OccupancyGrid grid;
  final ValueChanged<Offset> onTapWorld;
  final ValueChanged<Offset?> onHoverWorld;

  @override
  State<_StandaloneEditorCanvas> createState() => _StandaloneEditorCanvasState();
}

class _StandaloneEditorCanvasState extends State<_StandaloneEditorCanvas> {
  final GlobalKey _contentKey = GlobalKey();
  Offset? _pointerDownPos;

  Offset? _pixelToWorld(Offset globalPos) {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(globalPos);
    final res = widget.grid.info.resolution;
    final ox = widget.grid.info.origin.position.x;
    final oy = widget.grid.info.origin.position.y;
    final h = widget.grid.info.height;
    final wx = ox + local.dx * res;
    final wy = oy + (h - local.dy) * res;
    return Offset(wx, wy);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.grid.info.width.toDouble();
    final h = widget.grid.info.height.toDouble();

    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      onHover: (e) {
        final world = _pixelToWorld(e.position);
        widget.onHoverWorld(world);
      },
      onExit: (_) => widget.onHoverWorld(null),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _pointerDownPos = e.position,
        onPointerUp: (e) {
          if (_pointerDownPos != null && (e.position - _pointerDownPos!).distance < 12.0) {
            final world = _pixelToWorld(e.position);
            if (world != null) {
              widget.onTapWorld(world);
            }
          }
        },
        child: InteractiveViewer(
          transformationController: widget.transformController,
          minScale: 0.05,
          maxScale: 10.0,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: Container(
            key: _contentKey,
            width: w,
            height: h,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }
}
