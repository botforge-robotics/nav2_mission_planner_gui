import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nav_msgs/msg.dart' as nav_msgs;
import 'package:provider/provider.dart';

import '../../models/map_zone.dart';
import '../../models/traffic_editor_models.dart';
import '../../providers/connection_provider.dart';
import '../../providers/fleet_provider.dart';
import '../../services/dock_pose_controller.dart';
import '../../services/fleet_api_service.dart';
import '../../services/locations_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../services/zones_controller.dart';
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
  String? _selectedLaneId;
  String? _selectedWallId;
  String? _selectedDoorId;

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
    _activeGrid = OccupancyGridView.cachedGrid;
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
      // NOTE: Exclude pure structural wall/door vertices (i.e. vertices only connected to walls/doors and not part of traffic lanes, chargers, parking, or holding points)
      final laneVertexIds = _graph.lanes.expand((l) => [l.startVertexId, l.endVertexId]).toSet();
      final wallVertexIds = _graph.walls.expand((w) => [w.startVertexId, w.endVertexId]).toSet();
      final doorVertexIds = _graph.doors.expand((d) => [d.startVertexId, d.endVertexId]).toSet();
      final structuralVertexIds = {...wallVertexIds, ...doorVertexIds};

      final newLocationsList = <Map<String, dynamic>>[];
      for (final v in _graph.vertices) {
        final isStructural = structuralVertexIds.contains(v.id) ||
            v.id.startsWith('wall_v_') ||
            v.id.startsWith('door_v_') ||
            v.name.toLowerCase().startsWith('wall') ||
            v.name.toLowerCase().startsWith('door');

        // Only true navigation vertices are registered as waypoints
        final isNavWaypoint = v.isCharger ||
            v.isParking ||
            v.isHoldingPoint ||
            laneVertexIds.contains(v.id) ||
            (v.name.isNotEmpty && !isStructural);

        if (!isNavWaypoint) continue;

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
          final sX = v.standoffX ?? (v.x + (v.standoffDistance ?? 0.7) * cos(v.standoffAngle ?? 0.0));
          final sY = v.standoffY ?? (v.y + (v.standoffDistance ?? 0.7) * sin(v.standoffAngle ?? 0.0));
          final sTheta = atan2(v.y - sY, v.x - sX); // Face towards dock
          newLocationsList.add({
            'name': '${locName}_standoff',
            'x': sX,
            'y': sY,
            'theta': sTheta,
            'type': 'standoff',
          });

          // Sync dock pose to robot if connected
          final dockTheta = atan2(sY - v.y, sX - v.x);
          if (api != null) {
            api.setDockPose(x: v.x, y: v.y, theta: dockTheta).catchError((_) {});
          }

          // Sync dock pose to Fleet Server if in fleet mode
          if (fleet.isFleetMode && fleet.api != null) {
            fleet.api!.saveFleetDockPose(
              x: v.x,
              y: v.y,
              theta: dockTheta,
              dockName: locName,
              levelName: levelName,
            ).catchError((_) => <String, dynamic>{});
          }

          DockPoseController.instance.update(
            dock: (x: v.x, y: v.y, theta: dockTheta),
            standoff: (x: sX, y: sY, theta: sTheta),
          );
        }
      }
      LocationsController.instance.value = newLocationsList;

      // 2. Sync lanes as Preferred Lanes in ZonesController so Nav2 / Mission Planner route planner guides the robot along these traffic paths
      try {
        final existingZones = List<MapZone>.from(ZonesController.instance.value);
        existingZones.removeWhere((z) => z.id.startsWith('traffic_lane_'));
        for (final l in _graph.lanes) {
          final v1 = _graph.vertices.where((v) => v.id == l.startVertexId).firstOrNull;
          final v2 = _graph.vertices.where((v) => v.id == l.endVertexId).firstOrNull;
          if (v1 != null && v2 != null) {
            final laneZone = MapZone.createPolylineLane(
              map: levelName,
              centerline: [Offset(v1.x, v1.y), Offset(v2.x, v2.y)],
              width: l.width,
              name: 'Lane ${v1.name.isNotEmpty ? v1.name : v1.id} → ${v2.name.isNotEmpty ? v2.name : v2.id}',
            );
            // Prefix id to identify as traffic lane sync
            final customLane = MapZone(
              id: 'traffic_lane_${l.id}',
              name: laneZone.name,
              type: ZoneType.preferredLane,
              mapName: levelName,
              points: laneZone.points,
              speedLimitMps: l.speedLimit > 0.0 ? l.speedLimit : null,
            );
            existingZones.add(customLane);
            if (api != null) {
              ZonesController.instance.saveZone(api, customLane, map: levelName).catchError((_) => false);
            }
          }
        }
        ZonesController.instance.value = existingZones;
      } catch (err) {
        debugPrint('Failed to sync traffic lanes to preferred zones: $err');
      }

      // 3. If fleet mode is enabled, update building graph & apply to Open-RMF
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
          m['graph_idx'] = l.graphIdx;
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
      if (e is FleetApiException && e.status == 401 && fleet.isFleetMode) {
        try {
          final refreshed = await fleet.refreshToken();
          if (refreshed != null && mounted) {
            return await _saveGraphToFleet();
          }
        } catch (_) {}
      }
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
    // 1. Try finding nearest vertex within 0.4m
    EditorVertex? closestVertex;
    double closestDist = 0.4;
    for (final v in _graph.vertices) {
      final d = sqrt(pow(v.x - world.dx, 2) + pow(v.y - world.dy, 2));
      if (d < closestDist) {
        closestDist = d;
        closestVertex = v;
      }
    }

    if (closestVertex != null) {
      setState(() {
        _selectedVertexId = closestVertex!.id;
        _selectedLaneId = null;
        _selectedWallId = null;
        _selectedDoorId = null;
      });
      return;
    }

    // 2. Try selecting Doors (within 0.35m threshold)
    double minDoorDist = 0.35;
    EditorDoor? closestDoor;
    for (final d in _graph.doors) {
      final v1 = _graph.vertices.where((v) => v.id == d.startVertexId).firstOrNull;
      final v2 = _graph.vertices.where((v) => v.id == d.endVertexId).firstOrNull;
      if (v1 != null && v2 != null) {
        final dist = _pointToSegmentDistance(world, Offset(v1.x, v1.y), Offset(v2.x, v2.y));
        if (dist < minDoorDist) {
          minDoorDist = dist;
          closestDoor = d;
        }
      }
    }
    if (closestDoor != null) {
      setState(() {
        _selectedVertexId = null;
        _selectedLaneId = null;
        _selectedWallId = null;
        _selectedDoorId = closestDoor!.id;
      });
      return;
    }

    // 3. Try selecting Walls (within 0.35m threshold)
    double minWallDist = 0.35;
    EditorWall? closestWall;
    for (final w in _graph.walls) {
      final v1 = _graph.vertices.where((v) => v.id == w.startVertexId).firstOrNull;
      final v2 = _graph.vertices.where((v) => v.id == w.endVertexId).firstOrNull;
      if (v1 != null && v2 != null) {
        final dist = _pointToSegmentDistance(world, Offset(v1.x, v1.y), Offset(v2.x, v2.y));
        if (dist < minWallDist) {
          minWallDist = dist;
          closestWall = w;
        }
      }
    }
    if (closestWall != null) {
      setState(() {
        _selectedVertexId = null;
        _selectedLaneId = null;
        _selectedWallId = closestWall!.id;
        _selectedDoorId = null;
      });
      return;
    }

    // 4. Try selecting Lanes (within 0.35m threshold)
    double minLaneDist = 0.35;
    EditorEdge? closestLane;
    for (final l in _graph.lanes) {
      final v1 = _graph.vertices.where((v) => v.id == l.startVertexId).firstOrNull;
      final v2 = _graph.vertices.where((v) => v.id == l.endVertexId).firstOrNull;
      if (v1 != null && v2 != null) {
        final dist = _pointToSegmentDistance(world, Offset(v1.x, v1.y), Offset(v2.x, v2.y));
        if (dist < minLaneDist) {
          minLaneDist = dist;
          closestLane = l;
        }
      }
    }
    if (closestLane != null) {
      setState(() {
        _selectedVertexId = null;
        _selectedLaneId = closestLane!.id;
        _selectedWallId = null;
        _selectedDoorId = null;
      });
      return;
    }

    // Tapped empty space: clear all selection
    setState(() {
      _selectedVertexId = null;
      _selectedLaneId = null;
      _selectedWallId = null;
      _selectedDoorId = null;
    });
  }

  double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    final clampedT = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + clampedT * dx, a.dy + clampedT * dy);
    return (p - proj).distance;
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
      _selectedLaneId = null;
      _selectedWallId = null;
      _selectedDoorId = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added waypoint ${newVertex.name} at (${newVertex.x}, ${newVertex.y})m'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _onCanvasSecondaryTap(Offset world) {
    if (_edgeStartVertexId != null) {
      setState(() => _edgeStartVertexId = null);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finished / cancelled active chain.'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _handleEdgeTap(Offset world, {required bool isWall, required bool isDoor}) {
    // Select or create vertex to connect
    EditorVertex? targetVertex;
    double minDist = 0.40; // Snap threshold matching select threshold (0.4m) so connecting to existing intersection waypoints reliably snaps instead of spawning duplicate default-named nodes
    for (final v in _graph.vertices) {
      // When actively extending a chain, never snap back to the start vertex itself!
      if (_edgeStartVertexId != null && v.id == _edgeStartVertexId) continue;
      final d = sqrt(pow(v.x - world.dx, 2) + pow(v.y - world.dy, 2));
      if (d < minDist) {
        minDist = d;
        targetVertex = v;
      }
    }

    if (targetVertex == null) {
      // Auto-create vertex at tap position
      final newId = isWall
          ? 'wall_v_${DateTime.now().millisecondsSinceEpoch}'
          : (isDoor ? 'door_v_${DateTime.now().millisecondsSinceEpoch}' : 'v_${DateTime.now().millisecondsSinceEpoch}');
      final roundedX = double.parse(world.dx.toStringAsFixed(2));
      final roundedY = double.parse(world.dy.toStringAsFixed(2));
      final defaultName = (isWall || isDoor)
          ? '' // Walls and doors in Open-RMF are structural features with no waypoint name
          : 'wp_${_graph.vertices.length + 1}';
      targetVertex = EditorVertex(
        id: newId,
        x: roundedX,
        y: roundedY,
        name: defaultName,
      );
      setState(() {
        _graph.vertices.add(targetVertex!);
      });
    }

    if (_edgeStartVertexId == null) {
      setState(() => _edgeStartVertexId = targetVertex!.id);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isWall
              ? 'Start vertex selected. Tap next point to draw wall (continuous chain; right-click to finish).'
              : (isDoor
                  ? 'Start vertex selected. Tap end vertex to place door.'
                  : 'Start vertex selected. Tap end vertex to create lane (connects 2 vertices).')),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      if (_edgeStartVertexId != targetVertex.id) {
        final startId = _edgeStartVertexId!;
        final endId = targetVertex.id;

        setState(() {
          if (isWall) {
            final newWall = EditorWall(
              id: 'wall_${DateTime.now().millisecondsSinceEpoch}',
              startVertexId: startId,
              endVertexId: endId,
            );
            _graph.walls.add(newWall);
            _selectedWallId = newWall.id;
            _selectedVertexId = null;
            _selectedLaneId = null;
            _selectedDoorId = null;
            _edgeStartVertexId = targetVertex!.id; // Continuous chain for walls
          } else if (isDoor) {
            final newDoor = EditorDoor(
              id: 'door_${DateTime.now().millisecondsSinceEpoch}',
              startVertexId: startId,
              endVertexId: endId,
            );
            _graph.doors.add(newDoor);
            _selectedDoorId = newDoor.id;
            _selectedVertexId = null;
            _selectedLaneId = null;
            _selectedWallId = null;
            _edgeStartVertexId = null; // Doors connect 2 vertices
          } else {
            final newLane = EditorEdge(
              id: 'lane_${DateTime.now().millisecondsSinceEpoch}',
              startVertexId: startId,
              endVertexId: endId,
              bidirectional: true,
            );
            _graph.lanes.add(newLane);
            _selectedLaneId = newLane.id;
            _selectedVertexId = null;
            _selectedWallId = null;
            _selectedDoorId = null;
            _edgeStartVertexId = null; // Lanes connect strictly 2 vertices (no continuous chain)
          }
        });

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isWall
                ? 'Wall segment added. Tap next point to continue wall (or right-click to finish).'
                : (isDoor ? 'Door added between vertices.' : 'Lane created between 2 vertices.')),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        // Tapped same vertex: finish continuous chain
        setState(() => _edgeStartVertexId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chain finished.'), duration: Duration(seconds: 1)),
        );
      }
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
                              if (ros2 != null && _activeGrid != null)
                                Positioned.fill(
                                  child: OccupancyGridView(
                                    ros2: ros2,
                                    interactive: true,
                                    showRobot: true,
                                    showDock: true,
                                    transformationController: _transformController,
                                    onMapLoaded: (grid) => setState(() => _activeGrid = grid),
                                    onMapClickWorld: _onCanvasTap,
                                    onMapSecondaryClickWorld: _onCanvasSecondaryTap,
                                    onMapHoverWorld: (w) => setState(() => _mouseHoverWorld = w),
                                  ),
                                )
                              else
                                Positioned.fill(
                                  child: _StandaloneEditorCanvas(
                                    transformController: _transformController,
                                    grid: _effectiveGrid,
                                    onTapWorld: _onCanvasTap,
                                    onSecondaryTapWorld: _onCanvasSecondaryTap,
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
                                        isStandalone: ros2 == null || _activeGrid == null,
                                        selectedVertexId: _selectedVertexId,
                                        selectedLaneId: _selectedLaneId,
                                        selectedWallId: _selectedWallId,
                                        selectedDoorId: _selectedDoorId,
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
          if (_edgeStartVertexId != null) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: const Size(64, 32),
                ),
                onPressed: () => setState(() => _edgeStartVertexId = null),
                child: const Text('Finish', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
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
            : 'Click next vertex to continue lane chain, or click Finish.';
        break;
      case TrafficFeatureType.wall:
        text = _edgeStartVertexId == null
            ? 'Click start vertex for wall.'
            : 'Click next vertex to continue wall (chains automatically), or click Finish.';
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
    final selectedWall = _selectedWallId != null
        ? _graph.walls.where((w) => w.id == _selectedWallId).firstOrNull
        : null;
    final selectedDoor = _selectedDoorId != null
        ? _graph.doors.where((d) => d.id == _selectedDoorId).firstOrNull
        : null;
    final selectedLane = _selectedLaneId != null
        ? _graph.lanes.where((l) => l.id == _selectedLaneId).firstOrNull
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

          if (selectedVertex != null)
            _VertexPropertiesCard(
              key: ValueKey(selectedVertex.id),
              vertex: selectedVertex,
              graph: _graph,
              onChanged: () => setState(() {}),
              onDelete: _deleteSelectedElement,
              pickingStandoff: _pickingStandoff,
              onTogglePickStandoff: () {
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
            )
          else if (_selectedWallId != null && selectedWall != null)
            _WallPropertiesCard(
              key: ValueKey(selectedWall.id),
              wall: selectedWall,
              graph: _graph,
              onChanged: () => setState(() {}),
              onDelete: _deleteSelectedElement,
            )
          else if (_selectedDoorId != null && selectedDoor != null)
            _DoorPropertiesCard(
              key: ValueKey(selectedDoor.id),
              door: selectedDoor,
              graph: _graph,
              onChanged: () => setState(() {}),
              onDelete: _deleteSelectedElement,
            )
          else if (_selectedLaneId != null && selectedLane != null)
            _LanePropertiesCard(
              key: ValueKey(selectedLane.id),
              lane: selectedLane,
              graph: _graph,
              onChanged: () => setState(() {}),
              onDelete: _deleteSelectedElement,
            )
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text('Click any vertex, door, wall, or lane on the map to inspect parameters.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
              ),
            ),
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
    setState(() {
      if (_selectedVertexId != null) {
        final id = _selectedVertexId!;
        _graph.vertices.removeWhere((v) => v.id == id);
        _graph.lanes.removeWhere((l) => l.startVertexId == id || l.endVertexId == id);
        _graph.walls.removeWhere((w) => w.startVertexId == id || w.endVertexId == id);
        _graph.doors.removeWhere((d) => d.startVertexId == id || d.endVertexId == id);
        _selectedVertexId = null;
      } else if (_selectedWallId != null) {
        _graph.walls.removeWhere((w) => w.id == _selectedWallId);
        _selectedWallId = null;
      } else if (_selectedDoorId != null) {
        _graph.doors.removeWhere((d) => d.id == _selectedDoorId);
        _selectedDoorId = null;
      } else if (_selectedLaneId != null) {
        _graph.lanes.removeWhere((l) => l.id == _selectedLaneId);
        _selectedLaneId = null;
      }
    });
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

class _StandoffDistanceAndAngleFields extends StatefulWidget {
  const _StandoffDistanceAndAngleFields({
    required this.vertex,
    required this.onChanged,
  });

  final EditorVertex vertex;
  final VoidCallback onChanged;

  @override
  State<_StandoffDistanceAndAngleFields> createState() => _StandoffDistanceAndAngleFieldsState();
}

class _StandoffDistanceAndAngleFieldsState extends State<_StandoffDistanceAndAngleFields> {
  late final TextEditingController _distCtrl;
  late final TextEditingController _angleCtrl;

  @override
  void initState() {
    super.initState();
    final d = widget.vertex.standoffDistance ?? 0.7;
    final a = widget.vertex.standoffAngle ?? 0.0;
    _distCtrl = TextEditingController(text: d.toStringAsFixed(2));
    _angleCtrl = TextEditingController(text: a.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant _StandoffDistanceAndAngleFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vertex.id != widget.vertex.id) {
      final d = widget.vertex.standoffDistance ?? 0.7;
      final a = widget.vertex.standoffAngle ?? 0.0;
      _distCtrl.text = d.toStringAsFixed(2);
      _angleCtrl.text = a.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _distCtrl.dispose();
    _angleCtrl.dispose();
    super.dispose();
  }

  void _onDistChanged(String val) {
    final d = double.tryParse(val.trim());
    if (d != null) {
      widget.vertex.standoffDistance = d;
      final angle = widget.vertex.standoffAngle ?? 0.0;
      widget.vertex.standoffX = widget.vertex.x + d * cos(angle);
      widget.vertex.standoffY = widget.vertex.y + d * sin(angle);
      widget.onChanged();
    }
  }

  void _onAngleChanged(String val) {
    final a = double.tryParse(val.trim());
    if (a != null) {
      widget.vertex.standoffAngle = a;
      final d = widget.vertex.standoffDistance ?? 0.7;
      widget.vertex.standoffX = widget.vertex.x + d * cos(a);
      widget.vertex.standoffY = widget.vertex.y + d * sin(a);
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(labelText: 'Dist (m)', isDense: true),
            controller: _distCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: _onDistChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            decoration: const InputDecoration(labelText: 'Angle (rad)', isDense: true),
            controller: _angleCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: _onAngleChanged,
          ),
        ),
      ],
    );
  }
}

class _VertexPropertiesCard extends StatefulWidget {
  const _VertexPropertiesCard({
    super.key,
    required this.vertex,
    required this.graph,
    required this.onChanged,
    required this.onDelete,
    required this.pickingStandoff,
    required this.onTogglePickStandoff,
  });

  final EditorVertex vertex;
  final RmfLevelGraph graph;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final bool pickingStandoff;
  final VoidCallback onTogglePickStandoff;

  @override
  State<_VertexPropertiesCard> createState() => _VertexPropertiesCardState();
}

class _VertexPropertiesCardState extends State<_VertexPropertiesCard> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _xCtrl;
  late final TextEditingController _yCtrl;
  late final TextEditingController _dockCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.vertex.name);
    _xCtrl = TextEditingController(text: widget.vertex.x.toStringAsFixed(3));
    _yCtrl = TextEditingController(text: widget.vertex.y.toStringAsFixed(3));
    _dockCtrl = TextEditingController(text: widget.vertex.dockName ?? 'charger_1');
  }

  @override
  void didUpdateWidget(covariant _VertexPropertiesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vertex.id != widget.vertex.id) {
      _nameCtrl.text = widget.vertex.name;
      _xCtrl.text = widget.vertex.x.toStringAsFixed(3);
      _yCtrl.text = widget.vertex.y.toStringAsFixed(3);
      _dockCtrl.text = widget.vertex.dockName ?? 'charger_1';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _xCtrl.dispose();
    _yCtrl.dispose();
    _dockCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectedWalls = widget.graph.walls.where((w) => w.startVertexId == widget.vertex.id || w.endVertexId == widget.vertex.id).toList();
    final connectedLanes = widget.graph.lanes.where((l) => l.startVertexId == widget.vertex.id || l.endVertexId == widget.vertex.id).toList();
    final connectedDoors = widget.graph.doors.where((d) => d.startVertexId == widget.vertex.id || d.endVertexId == widget.vertex.id).toList();
    final isIntersection = connectedLanes.length >= 2;
    final displayName = widget.vertex.name.isNotEmpty ? widget.vertex.name : widget.vertex.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isIntersection
                  ? Icons.alt_route_rounded
                  : (widget.vertex.isCharger
                      ? Icons.ev_station_rounded
                      : (widget.vertex.isParking ? Icons.local_parking_rounded : Icons.place_rounded)),
              color: isIntersection
                  ? const Color(0xFF00E5FF)
                  : (widget.vertex.isCharger
                      ? const Color(0xFFF59E0B)
                      : (widget.vertex.isParking ? const Color(0xFF10B981) : AppColors.primary)),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isIntersection ? 'Intersection: $displayName' : 'Vertex: $displayName',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isIntersection)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4)),
                ),
                child: const Text('INTERSECTION', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          decoration: const InputDecoration(labelText: 'Waypoint Name', isDense: true),
          controller: _nameCtrl,
          onChanged: (val) {
            widget.vertex.name = val.trim();
            widget.onChanged();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(labelText: 'X (meters)', isDense: true),
                controller: _xCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) {
                  final n = double.tryParse(val.trim());
                  if (n != null) {
                    widget.vertex.x = n;
                    widget.onChanged();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(labelText: 'Y (meters)', isDense: true),
                controller: _yCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) {
                  final n = double.tryParse(val.trim());
                  if (n != null) {
                    widget.vertex.y = n;
                    widget.onChanged();
                  }
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
          value: widget.vertex.isCharger,
          onChanged: (v) {
            widget.vertex.isCharger = v ?? false;
            widget.onChanged();
          },
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Is Parking / Holding Point', style: TextStyle(fontSize: 13)),
          subtitle: const Text('Designated standby waiting pose for AMR traffic yield', style: TextStyle(fontSize: 10)),
          value: widget.vertex.isParking,
          onChanged: (v) {
            widget.vertex.isParking = v ?? false;
            widget.onChanged();
          },
        ),
        if (widget.vertex.isCharger) ...[
          TextField(
            decoration: const InputDecoration(labelText: 'Dock Name / ID', isDense: true),
            controller: _dockCtrl,
            onChanged: (val) {
              widget.vertex.dockName = val.trim();
              widget.onChanged();
            },
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
                    if (widget.vertex.standoffX != null || widget.vertex.standoffDistance != null)
                      InkWell(
                        onTap: () {
                          widget.vertex.standoffX = null;
                          widget.vertex.standoffY = null;
                          widget.vertex.standoffDistance = null;
                          widget.vertex.standoffAngle = null;
                          widget.onChanged();
                        },
                        child: const Text('Reset', style: TextStyle(fontSize: 10, color: AppColors.danger)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.vertex.standoffX != null
                      ? 'Pose: (${widget.vertex.standoffX!.toStringAsFixed(2)}, ${widget.vertex.standoffY!.toStringAsFixed(2)}) — ${(widget.vertex.standoffDistance ?? 0.7).toStringAsFixed(2)}m'
                      : 'Default standoff: 0.7m approach along dock axis.',
                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                _StandoffDistanceAndAngleFields(
                  vertex: widget.vertex,
                  onChanged: widget.onChanged,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: widget.pickingStandoff ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
                    minimumSize: const Size(double.infinity, 32),
                  ),
                  icon: Icon(widget.pickingStandoff ? Icons.touch_app_rounded : Icons.place_rounded, size: 14),
                  label: Text(widget.pickingStandoff ? 'Click on map to set standoff...' : 'Pick Standoff on Map', style: const TextStyle(fontSize: 11)),
                  onPressed: widget.onTogglePickStandoff,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    isIntersection ? 'Intersection Connections (${connectedLanes.length} lanes)' : 'Connected Relations',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (connectedWalls.isEmpty && connectedLanes.isEmpty && connectedDoors.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('No connected walls, lanes, or doors.', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                ),
              ...connectedWalls.map((w) {
                final otherId = w.startVertexId == widget.vertex.id ? w.endVertexId : w.startVertexId;
                final other = widget.graph.vertices.where((v) => v.id == otherId).firstOrNull;
                final otherDisplayName = (other?.name.isNotEmpty == true) ? other!.name : otherId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.fence_rounded, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(child: Text('Wall to $otherDisplayName', style: const TextStyle(fontSize: 10))),
                      InkWell(
                        onTap: () {
                          widget.graph.walls.remove(w);
                          widget.onChanged();
                        },
                        child: const Icon(Icons.close_rounded, size: 12, color: AppColors.danger),
                      ),
                    ],
                  ),
                );
              }),
              ...connectedLanes.map((l) {
                final otherId = l.startVertexId == widget.vertex.id ? l.endVertexId : l.startVertexId;
                final other = widget.graph.vertices.where((v) => v.id == otherId).firstOrNull;
                final otherDisplayName = (other?.name.isNotEmpty == true) ? other!.name : otherId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.alt_route_rounded, size: 12, color: Color(0xFF00E5FF)),
                      const SizedBox(width: 4),
                      Expanded(child: Text('Lane to $otherDisplayName (${l.bidirectional ? '⇄' : '➔'})', style: const TextStyle(fontSize: 10))),
                      InkWell(
                        onTap: () {
                          widget.graph.lanes.remove(l);
                          widget.onChanged();
                        },
                        child: const Icon(Icons.close_rounded, size: 12, color: AppColors.danger),
                      ),
                    ],
                  ),
                );
              }),
              ...connectedDoors.map((d) {
                final otherId = d.startVertexId == widget.vertex.id ? d.endVertexId : d.startVertexId;
                final other = widget.graph.vertices.where((v) => v.id == otherId).firstOrNull;
                final otherDisplayName = (other?.name.isNotEmpty == true) ? other!.name : otherId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.sensor_door_outlined, size: 12, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      Expanded(child: Text('Door to $otherDisplayName', style: const TextStyle(fontSize: 10))),
                      InkWell(
                        onTap: () {
                          widget.graph.doors.remove(d);
                          widget.onChanged();
                        },
                        child: const Icon(Icons.close_rounded, size: 12, color: AppColors.danger),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Connect relation to...',
                        labelStyle: TextStyle(fontSize: 10),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      items: widget.graph.vertices
                          .where((v) => v.id != widget.vertex.id)
                          .map((v) => DropdownMenuItem(
                                value: v.id,
                                child: Text(
                                  v.name.isNotEmpty ? v.name : v.id,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ))
                          .toList(),
                      onChanged: (targetId) {
                        if (targetId == null) return;
                        showModalBottomSheet(
                          context: context,
                          builder: (bCtx) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.fence_rounded),
                                  title: const Text('Add Wall Connection'),
                                  onTap: () {
                                    Navigator.pop(bCtx);
                                    widget.graph.walls.add(EditorWall(
                                      id: 'wall_${DateTime.now().millisecondsSinceEpoch}',
                                      startVertexId: widget.vertex.id,
                                      endVertexId: targetId,
                                    ));
                                    widget.onChanged();
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.alt_route_rounded, color: Color(0xFF00E5FF)),
                                  title: const Text('Add Lane Connection'),
                                  onTap: () {
                                    Navigator.pop(bCtx);
                                    widget.graph.lanes.add(EditorEdge(
                                      id: 'lane_${DateTime.now().millisecondsSinceEpoch}',
                                      startVertexId: widget.vertex.id,
                                      endVertexId: targetId,
                                      bidirectional: true,
                                    ));
                                    widget.onChanged();
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.sensor_door_outlined, color: Color(0xFFF59E0B)),
                                  title: const Text('Add Door Connection'),
                                  onTap: () {
                                    Navigator.pop(bCtx);
                                    widget.graph.doors.add(EditorDoor(
                                      id: 'door_${DateTime.now().millisecondsSinceEpoch}',
                                      startVertexId: widget.vertex.id,
                                      endVertexId: targetId,
                                    ));
                                    widget.onChanged();
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
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger.withValues(alpha: 0.15), foregroundColor: AppColors.danger),
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('Delete Vertex'),
          onPressed: widget.onDelete,
        ),
      ],
    );
  }
}

class _LanePropertiesCard extends StatefulWidget {
  const _LanePropertiesCard({
    super.key,
    required this.lane,
    required this.graph,
    required this.onChanged,
    required this.onDelete,
  });

  final EditorEdge lane;
  final RmfLevelGraph graph;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_LanePropertiesCard> createState() => _LanePropertiesCardState();
}

class _LanePropertiesCardState extends State<_LanePropertiesCard> {
  late final TextEditingController _widthCtrl;
  late final TextEditingController _speedCtrl;

  @override
  void initState() {
    super.initState();
    _widthCtrl = TextEditingController(text: widget.lane.width.toStringAsFixed(2));
    _speedCtrl = TextEditingController(text: widget.lane.speedLimit.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant _LanePropertiesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lane.id != widget.lane.id) {
      _widthCtrl.text = widget.lane.width.toStringAsFixed(2);
      _speedCtrl.text = widget.lane.speedLimit.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _speedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otherVertices = widget.graph.vertices.toList();
    final startV = widget.graph.vertices.where((v) => v.id == widget.lane.startVertexId).firstOrNull;
    final endV = widget.graph.vertices.where((v) => v.id == widget.lane.endVertexId).firstOrNull;
    final startName = (startV?.name.isNotEmpty == true) ? startV!.name : widget.lane.startVertexId;
    final endName = (endV?.name.isNotEmpty == true) ? endV!.name : widget.lane.endVertexId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.alt_route_rounded, color: Color(0xFF00E5FF), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Lane: $startName ⇄ $endName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: otherVertices.any((v) => v.id == widget.lane.startVertexId) ? widget.lane.startVertexId : null,
          decoration: const InputDecoration(labelText: 'Start Vertex / Intersection', isDense: true),
          items: otherVertices.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name.isNotEmpty ? v.name : v.id, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (newStart) {
            if (newStart != null) {
              widget.lane.startVertexId = newStart;
              widget.onChanged();
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: otherVertices.any((v) => v.id == widget.lane.endVertexId) ? widget.lane.endVertexId : null,
          decoration: const InputDecoration(labelText: 'End Vertex / Intersection', isDense: true),
          items: otherVertices.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name.isNotEmpty ? v.name : v.id, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (newEnd) {
            if (newEnd != null) {
              widget.lane.endVertexId = newEnd;
              widget.onChanged();
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Bidirectional', style: TextStyle(fontSize: 13)),
          subtitle: const Text('AMRs can navigate in both directions (⇄)', style: TextStyle(fontSize: 10)),
          value: widget.lane.bidirectional,
          onChanged: (v) {
            widget.lane.bidirectional = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          decoration: const InputDecoration(labelText: 'Lane Width (m, default 0.40m)', isDense: true),
          controller: _widthCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (val) {
            final w = double.tryParse(val.trim());
            if (w != null && w > 0.0) {
              widget.lane.width = w;
              widget.onChanged();
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          decoration: const InputDecoration(labelText: 'Speed Limit (m/s, 0 = unlimited)', isDense: true),
          controller: _speedCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (val) {
            final sl = double.tryParse(val.trim());
            if (sl != null) {
              widget.lane.speedLimit = sl;
              widget.onChanged();
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger.withValues(alpha: 0.15), foregroundColor: AppColors.danger),
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('Delete Lane'),
          onPressed: widget.onDelete,
        ),
      ],
    );
  }
}

class _WallPropertiesCard extends StatefulWidget {
  const _WallPropertiesCard({
    super.key,
    required this.wall,
    required this.graph,
    required this.onChanged,
    required this.onDelete,
  });

  final EditorWall wall;
  final RmfLevelGraph graph;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_WallPropertiesCard> createState() => _WallPropertiesCardState();
}

class _WallPropertiesCardState extends State<_WallPropertiesCard> {
  late final TextEditingController _thicknessCtrl;

  @override
  void initState() {
    super.initState();
    _thicknessCtrl = TextEditingController(text: widget.wall.thickness.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant _WallPropertiesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wall.id != widget.wall.id) {
      _thicknessCtrl.text = widget.wall.thickness.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _thicknessCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otherVertices = widget.graph.vertices.toList();
    final startV = widget.graph.vertices.where((v) => v.id == widget.wall.startVertexId).firstOrNull;
    final endV = widget.graph.vertices.where((v) => v.id == widget.wall.endVertexId).firstOrNull;
    final startName = (startV?.name.isNotEmpty == true) ? startV!.name : widget.wall.startVertexId;
    final endName = (endV?.name.isNotEmpty == true) ? endV!.name : widget.wall.endVertexId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.fence_rounded, color: AppColors.textPrimary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Wall: $startName ⇄ $endName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: otherVertices.any((v) => v.id == widget.wall.startVertexId) ? widget.wall.startVertexId : null,
          decoration: const InputDecoration(labelText: 'Start Vertex', isDense: true),
          items: otherVertices.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name.isNotEmpty ? v.name : v.id, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (newStart) {
            if (newStart != null) {
              widget.wall.startVertexId = newStart;
              widget.onChanged();
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: otherVertices.any((v) => v.id == widget.wall.endVertexId) ? widget.wall.endVertexId : null,
          decoration: const InputDecoration(labelText: 'End Vertex', isDense: true),
          items: otherVertices.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name.isNotEmpty ? v.name : v.id, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (newEnd) {
            if (newEnd != null) {
              widget.wall.endVertexId = newEnd;
              widget.onChanged();
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          decoration: const InputDecoration(labelText: 'Thickness (meters)', isDense: true),
          controller: _thicknessCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (val) {
            final t = double.tryParse(val.trim());
            if (t != null && t > 0.0) {
              widget.wall.thickness = t;
              widget.onChanged();
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger.withValues(alpha: 0.15), foregroundColor: AppColors.danger),
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('Delete Wall'),
          onPressed: widget.onDelete,
        ),
      ],
    );
  }
}

class _DoorPropertiesCard extends StatefulWidget {
  const _DoorPropertiesCard({
    super.key,
    required this.door,
    required this.graph,
    required this.onChanged,
    required this.onDelete,
  });

  final EditorDoor door;
  final RmfLevelGraph graph;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<_DoorPropertiesCard> createState() => _DoorPropertiesCardState();
}

class _DoorPropertiesCardState extends State<_DoorPropertiesCard> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _motionCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.door.name);
    _motionCtrl = TextEditingController(text: widget.door.motionTime.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant _DoorPropertiesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.door.id != widget.door.id) {
      _nameCtrl.text = widget.door.name;
      _motionCtrl.text = widget.door.motionTime.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _motionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otherVertices = widget.graph.vertices.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.sensor_door_outlined, color: Color(0xFFF59E0B), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Door: ${widget.door.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: otherVertices.any((v) => v.id == widget.door.startVertexId) ? widget.door.startVertexId : null,
          decoration: const InputDecoration(labelText: 'Start Vertex', isDense: true),
          items: otherVertices.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name.isNotEmpty ? v.name : v.id, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (newStart) {
            if (newStart != null) {
              widget.door.startVertexId = newStart;
              widget.onChanged();
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: otherVertices.any((v) => v.id == widget.door.endVertexId) ? widget.door.endVertexId : null,
          decoration: const InputDecoration(labelText: 'End Vertex', isDense: true),
          items: otherVertices.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name.isNotEmpty ? v.name : v.id, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (newEnd) {
            if (newEnd != null) {
              widget.door.endVertexId = newEnd;
              widget.onChanged();
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          decoration: const InputDecoration(labelText: 'Door Name', isDense: true),
          controller: _nameCtrl,
          onChanged: (val) {
            widget.door.name = val.trim();
            widget.onChanged();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<DoorType>(
          initialValue: widget.door.doorType,
          decoration: const InputDecoration(labelText: 'Door Type', isDense: true),
          items: DoorType.values.map((type) => DropdownMenuItem(value: type, child: Text(type.label, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) {
            if (v != null) {
              widget.door.doorType = v;
              widget.onChanged();
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          decoration: const InputDecoration(labelText: 'Motion Duration (sec)', isDense: true),
          controller: _motionCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (val) {
            final mt = double.tryParse(val.trim());
            if (mt != null) {
              widget.door.motionTime = mt;
              widget.onChanged();
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger.withValues(alpha: 0.15), foregroundColor: AppColors.danger),
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('Delete Door'),
          onPressed: widget.onDelete,
        ),
      ],
    );
  }
}

class _RmfTrafficCanvasPainter extends CustomPainter {
  final RmfLevelGraph graph;
  final nav_msgs.OccupancyGrid grid;
  final bool isStandalone;
  final String? selectedVertexId;
  final String? selectedLaneId;
  final String? selectedWallId;
  final String? selectedDoorId;
  final String? edgeStartVertexId;
  final Offset? mouseHoverWorld;
  final Matrix4 transform;

  _RmfTrafficCanvasPainter({
    required this.graph,
    required this.grid,
    this.isStandalone = false,
    this.selectedVertexId,
    this.selectedLaneId,
    this.selectedWallId,
    this.selectedDoorId,
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

    // 1. Draw Walls (Clean Open-RMF Site Charcoal / Slate with white inner core)
    final wallOutlinePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.square;
    final wallCorePaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.square;
    final wallHighlightPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.9)
      ..strokeWidth = 11.0
      ..strokeCap = StrokeCap.square;

    for (final wall in graph.walls) {
      final start = graph.vertices.where((v) => v.id == wall.startVertexId).firstOrNull;
      final end = graph.vertices.where((v) => v.id == wall.endVertexId).firstOrNull;
      if (start != null && end != null) {
        final p1 = _worldToScreen(start.x, start.y);
        final p2 = _worldToScreen(end.x, end.y);
        if (wall.id == selectedWallId) {
          canvas.drawLine(p1, p2, wallHighlightPaint);
        }
        canvas.drawLine(p1, p2, wallOutlinePaint);
        canvas.drawLine(p1, p2, wallCorePaint);
      }
    }

    // 2. Draw Doors (Open-RMF Site Orange/Amber Hinged/Sliding Markers)
    final doorUnderlay = Paint()
      ..color = const Color(0xFFEA580C)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;
    final doorCore = Paint()
      ..color = const Color(0xFFFDBA74)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final doorHighlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 10.0
      ..strokeCap = StrokeCap.round;

    for (final door in graph.doors) {
      final start = graph.vertices.where((v) => v.id == door.startVertexId).firstOrNull;
      final end = graph.vertices.where((v) => v.id == door.endVertexId).firstOrNull;
      if (start != null && end != null) {
        final p1 = _worldToScreen(start.x, start.y);
        final p2 = _worldToScreen(end.x, end.y);
        if (door.id == selectedDoorId) {
          canvas.drawLine(p1, p2, doorHighlightPaint);
        }
        canvas.drawLine(p1, p2, doorUnderlay);
        canvas.drawLine(p1, p2, doorCore);
      }
    }

    // Helper to draw an arrowhead along a segment (RMF Site chevron / arrowhead)
    void drawArrowHead(Offset from, Offset to, Color color, {double arrowSize = 9.0}) {
      final dx = to.dx - from.dx;
      final dy = to.dy - from.dy;
      final angle = atan2(dy, dx);
      final arrowPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      final path = Path();
      path.moveTo(to.dx, to.dy);
      path.lineTo(
        to.dx - arrowSize * cos(angle - pi / 6),
        to.dy - arrowSize * sin(angle - pi / 6),
      );
      path.lineTo(
        to.dx - (arrowSize * 0.6) * cos(angle),
        to.dy - (arrowSize * 0.6) * sin(angle),
      );
      path.lineTo(
        to.dx - arrowSize * cos(angle + pi / 6),
        to.dy - arrowSize * sin(angle + pi / 6),
      );
      path.close();
      canvas.drawPath(path, arrowPaint);
      canvas.drawPath(path, strokePaint);
    }

    // 3. Draw Lanes (Open-RMF Site emerald/green for bidirectional, cyan for unidirectional)
    final laneHaloPaint = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.6)
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;
    final laneBidiPaint = Paint()
      ..color = const Color(0xFF10B981) // Emerald Green for bidirectional (standard Open-RMF nav graph)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final laneUniPaint = Paint()
      ..color = const Color(0xFF06B6D4) // Cyan / Blue for single-direction
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    final laneHighlightPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.9)
      ..strokeWidth = 9.0
      ..strokeCap = StrokeCap.round;

    for (final lane in graph.lanes) {
      final start = graph.vertices.where((v) => v.id == lane.startVertexId).firstOrNull;
      final end = graph.vertices.where((v) => v.id == lane.endVertexId).firstOrNull;
      if (start != null && end != null) {
        final p1 = _worldToScreen(start.x, start.y);
        final p2 = _worldToScreen(end.x, end.y);
        final lColor = lane.bidirectional ? const Color(0xFF10B981) : const Color(0xFF06B6D4);
        final pPaint = lane.bidirectional ? laneBidiPaint : laneUniPaint;

        if (lane.id == selectedLaneId) {
          canvas.drawLine(p1, p2, laneHighlightPaint);
        }
        canvas.drawLine(p1, p2, laneHaloPaint);
        canvas.drawLine(p1, p2, pPaint);

        // Draw directional chevron arrows along the lane
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final len = (p2 - p1).distance;
        if (len > 24) {
          if (lane.bidirectional) {
            // Opposing dual arrows along lane showing both directions
            final f1 = Offset(p1.dx + (p2.dx - p1.dx) * 0.40, p1.dy + (p2.dy - p1.dy) * 0.40);
            final f2 = Offset(p1.dx + (p2.dx - p1.dx) * 0.60, p1.dy + (p2.dy - p1.dy) * 0.60);
            drawArrowHead(p1, f2, lColor, arrowSize: 9.0);
            drawArrowHead(p2, f1, lColor, arrowSize: 9.0);
          } else {
            // Single forward arrow start -> end
            drawArrowHead(p1, mid, lColor, arrowSize: 11.0);
          }
        }
      }
    }

    // 4. In-progress edge draft line & snap preview
    EditorVertex? hoverSnapVertex;
    if (mouseHoverWorld != null) {
      double minSnap = 0.40;
      for (final v in graph.vertices) {
        if (edgeStartVertexId != null && v.id == edgeStartVertexId) continue;
        final d = sqrt(pow(v.x - mouseHoverWorld!.dx, 2) + pow(v.y - mouseHoverWorld!.dy, 2));
        if (d < minSnap) {
          minSnap = d;
          hoverSnapVertex = v;
        }
      }
    }

    if (edgeStartVertexId != null && mouseHoverWorld != null) {
      final start = graph.vertices.where((v) => v.id == edgeStartVertexId).firstOrNull;
      if (start != null) {
        final p1 = _worldToScreen(start.x, start.y);
        final targetWorld = hoverSnapVertex != null ? Offset(hoverSnapVertex.x, hoverSnapVertex.y) : mouseHoverWorld!;
        final p2 = _worldToScreen(targetWorld.dx, targetWorld.dy);
        final draftPaint = Paint()
          ..color = hoverSnapVertex != null ? const Color(0xFF00E5FF) : const Color(0xFF38BDF8)
          ..strokeWidth = hoverSnapVertex != null ? 2.8 : 2.0
          ..style = PaintingStyle.stroke;
        canvas.drawLine(p1, p2, draftPaint);

        if (hoverSnapVertex != null) {
          // Snap halo around target waypoint
          canvas.drawCircle(p2, 10.0, Paint()..color = const Color(0xFF00E5FF).withValues(alpha: 0.35));
          canvas.drawCircle(p2, 6.0, Paint()..color = const Color(0xFF00E5FF)..style = PaintingStyle.stroke..strokeWidth = 2.0);
        }
      }
    }

    // 5. Draw Vertices (Open-RMF Site Visual Style)
    // Distinguish nav waypoints vs pure structural wall & door vertices
    final laneVertexIds = graph.lanes.expand((l) => [l.startVertexId, l.endVertexId]).toSet();
    final wallVertexIds = graph.walls.expand((w) => [w.startVertexId, w.endVertexId]).toSet();
    final doorVertexIds = graph.doors.expand((d) => [d.startVertexId, d.endVertexId]).toSet();
    final structuralVertexIds = {...wallVertexIds, ...doorVertexIds};

    for (final v in graph.vertices) {
      final p = _worldToScreen(v.x, v.y);
      final isSelected = v.id == selectedVertexId || v.id == edgeStartVertexId;
      final isStructural = structuralVertexIds.contains(v.id) ||
          v.id.startsWith('wall_v_') ||
          v.id.startsWith('door_v_') ||
          v.name.toLowerCase().startsWith('wall') ||
          v.name.toLowerCase().startsWith('door');

      final isNavWaypoint = v.isCharger ||
          v.isParking ||
          v.isHoldingPoint ||
          laneVertexIds.contains(v.id) ||
          (v.name.isNotEmpty && !isStructural);

      if (isSelected) {
        canvas.drawCircle(p, 12, Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.35));
        canvas.drawCircle(p, 10, Paint()..color = Colors.white.withValues(alpha: 0.8));
      }

      if (!isNavWaypoint) {
        // Structural wall/door vertex: subtle square node in RMF Site style (not rendered as waypoint)
        final isDoorEndpoint = doorVertexIds.contains(v.id) || v.id.startsWith('door_');
        final nodeColor = isDoorEndpoint ? const Color(0xFF10B981) : const Color(0xFF64748B);
        canvas.drawRect(
          Rect.fromCenter(center: p, width: 6, height: 6),
          Paint()..color = nodeColor,
        );
        canvas.drawRect(
          Rect.fromCenter(center: p, width: 6, height: 6),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
        // Wall vertices don't display pill badges unless selected
        if (isSelected) {
          final textSpan = TextSpan(
            text: v.name.isNotEmpty ? v.name : 'Wall Vertex',
            style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600),
          );
          final textPainter = TextPainter(textDirection: TextDirection.ltr, text: textSpan)..layout();
          final bgRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(p.dx + 6, p.dy - 12, textPainter.width + 6, textPainter.height + 2),
            const Radius.circular(3),
          );
          canvas.drawRRect(bgRect, Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.85));
          textPainter.paint(canvas, p + const Offset(9, -11));
        }
        continue;
      }

      // Navigation Vertices (Open-RMF Site Editor colored waypoint pins)
      final connectedLanesCount = graph.lanes.where((l) => l.startVertexId == v.id || l.endVertexId == v.id).length;
      final isIntersection = connectedLanesCount >= 2;

      Color vColor = const Color(0xFF0284C7); // Sky Blue for regular waypoint
      String typeLabel = 'WAYPOINT';

      if (v.isCharger) {
        vColor = const Color(0xFFF59E0B); // Amber / Yellow for charger dock
        typeLabel = 'CHARGER';
      } else if (v.isParking) {
        vColor = const Color(0xFF10B981); // Emerald green for parking
        typeLabel = 'PARKING';
      } else if (v.isHoldingPoint) {
        vColor = const Color(0xFF8B5CF6); // Violet for holding point
        typeLabel = 'HOLDING';
      } else if (isIntersection) {
        vColor = const Color(0xFF00E5FF); // Cyan for intersection waypoint
        typeLabel = 'INTERSECTION';
      }

      // Outer glow and border
      canvas.drawCircle(p, 6.0, Paint()..color = const Color(0xFF0F172A));
      canvas.drawCircle(p, 5.0, Paint()..color = vColor);
      canvas.drawCircle(p, 2.0, Paint()..color = Colors.white);

      // Render Clean Badge & Name Pill
      final displayName = v.name.isNotEmpty ? v.name : v.id;
      final textSpan = TextSpan(
        children: [
          TextSpan(text: '$displayName ', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
          if (v.isCharger || v.isParking || v.isHoldingPoint || isIntersection)
            TextSpan(
              text: '[$typeLabel]',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: v.isCharger
                    ? const Color(0xFFFDE047)
                    : (v.isParking
                        ? const Color(0xFF6EE7B7)
                        : (v.isHoldingPoint ? const Color(0xFFC4B5FD) : const Color(0xFF67E8F9))),
              ),
            ),
        ],
      );
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: textSpan,
      )..layout();

      // Paint label background capsule
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(p.dx + 8, p.dy - 13, textPainter.width + 8, textPainter.height + 4),
        const Radius.circular(4),
      );
      canvas.drawRRect(bgRect, Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.85));
      canvas.drawRRect(bgRect, Paint()..color = vColor.withValues(alpha: 0.4)..style = PaintingStyle.stroke..strokeWidth = 1.0);
      textPainter.paint(canvas, p + const Offset(12, -11));

      // Draw custom standoff point and approach line if charger
      if (v.isCharger && (v.standoffX != null || v.standoffDistance != null)) {
        final sX = v.standoffX ?? (v.x + (v.standoffDistance ?? 0.7) * cos(v.standoffAngle ?? 0.0));
        final sY = v.standoffY ?? (v.y + (v.standoffDistance ?? 0.7) * sin(v.standoffAngle ?? 0.0));
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
        final distVal = v.standoffDistance ?? 0.7;
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
    this.onSecondaryTapWorld,
    required this.onHoverWorld,
  });

  final TransformationController transformController;
  final nav_msgs.OccupancyGrid grid;
  final ValueChanged<Offset> onTapWorld;
  final ValueChanged<Offset>? onSecondaryTapWorld;
  final ValueChanged<Offset?> onHoverWorld;

  @override
  State<_StandaloneEditorCanvas> createState() => _StandaloneEditorCanvasState();
}

class _StandaloneEditorCanvasState extends State<_StandaloneEditorCanvas> {
  final GlobalKey _contentKey = GlobalKey();

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
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) {
          final world = _pixelToWorld(details.globalPosition);
          if (world != null) {
            widget.onTapWorld(world);
          }
        },
        onSecondaryTapUp: (details) {
          final world = _pixelToWorld(details.globalPosition);
          if (world != null) {
            widget.onSecondaryTapWorld?.call(world);
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
