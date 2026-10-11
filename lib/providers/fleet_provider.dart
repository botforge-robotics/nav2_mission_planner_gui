import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/fleet_models.dart';
import '../models/map_zone.dart';
import '../services/fleet_api_service.dart';
import '../services/robot_connection_store.dart';

class FleetProvider extends ChangeNotifier {
  FleetProvider({RobotConnectionStore? store})
      : _store = store ?? RobotConnectionStore() {
    _init();
  }

  final RobotConnectionStore _store;
  FleetApiService? _api;
  Timer? _pollTimer;

  bool _isFleetMode = false;
  String? _fleetServerHost = 'localhost';
  int _fleetServerPort = 80;
  String? _token;

  List<FleetRobotInfo> _robots = [];
  List<FleetLevelInfo> _levels = [];
  List<FleetInfo> _fleets = [];
  List<Map<String, dynamic>> _activeMissions = [];

  String? _selectedRobotId;
  String? _selectedLevelId;
  String? _error;
  bool _isLoading = false;

  // Getters
  bool get isFleetMode => _isFleetMode;
  String? get fleetServerHost => _fleetServerHost;
  int get fleetServerPort => _fleetServerPort;
  FleetApiService? get api => _api;
  List<FleetRobotInfo> get robots => List.unmodifiable(_robots);
  List<FleetLevelInfo> get levels => List.unmodifiable(_levels);
  List<FleetInfo> get fleets => List.unmodifiable(_fleets);
  List<Map<String, dynamic>> get activeMissions => List.unmodifiable(_activeMissions);

  String? get selectedRobotId => _selectedRobotId;
  FleetRobotInfo? get selectedRobot {
    if (_selectedRobotId == null) return _robots.isNotEmpty ? _robots.first : null;
    return _robots.firstWhere(
      (r) => r.id == _selectedRobotId,
      orElse: () => _robots.isNotEmpty ? _robots.first : const FleetRobotInfo(id: '', name: '', serial: '', status: ''),
    );
  }

  String? get selectedLevelId => _selectedLevelId;
  FleetLevelInfo? get selectedLevel {
    if (_selectedLevelId == null) return _levels.isNotEmpty ? _levels.first : null;
    return _levels.firstWhere(
      (l) => l.id == _selectedLevelId,
      orElse: () => _levels.isNotEmpty ? _levels.first : const FleetLevelInfo(id: '', name: '', buildingId: '', imageUrl: ''),
    );
  }

  String? get error => _error;
  bool get isLoading => _isLoading;

  String? get token => _token;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  Future<void> _init() async {
    final saved = await _store.load();
    if (saved != null) {
      _isFleetMode = saved.isFleetMode;
      _fleetServerHost = saved.fleetServerHost ?? saved.ip;
      _fleetServerPort = saved.fleetServerPort;
      _token = saved.fleetAuthToken;
      _robotIps.addAll(saved.fleetRobotIps);
      if (_isFleetMode && _fleetServerHost != null) {
        _connectFleet();
      }
    }
  }

  void _connectFleet() async {
    if (_fleetServerHost == null || _fleetServerHost!.isEmpty) return;

    // If token is missing, attempt auto-login using default fleet admin credentials
    if (_token == null || _token!.isEmpty) {
      try {
        final unauthedApi = FleetApiService(serverHost: _fleetServerHost!, port: _fleetServerPort);
        final res = await unauthedApi.login('admin', 'navpro-admin');
        final token = res['token'] as String?;
        if (token != null && token.isNotEmpty) {
          _token = token;
          final saved = await _store.load();
          if (saved != null) {
            final updated = SavedRobot(
              name: saved.name,
              ip: saved.ip,
              fleetServerHost: _fleetServerHost,
              fleetServerPort: _fleetServerPort,
              isFleetMode: _isFleetMode,
              fleetAuthToken: token,
              fleetRobotIps: _robotIps,
            );
            await _store.save(updated);
          }
        }
      } catch (_) {
        // Auto-login failed (e.g. customized credentials or offline), user can sign in manually
      }
    }

    _api = FleetApiService(
      serverHost: _fleetServerHost!,
      port: _fleetServerPort,
      token: _token,
    );
    _startPolling();
    refreshFleet();
  }

  Future<bool> login(String username, String password) async {
    if (_fleetServerHost == null || _fleetServerHost!.isEmpty) return false;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final unauthedApi = FleetApiService(serverHost: _fleetServerHost!, port: _fleetServerPort);
      final res = await unauthedApi.login(username, password);
      final token = res['token'] as String?;
      if (token != null && token.isNotEmpty) {
        _token = token;
        final saved = await _store.load();
        if (saved != null) {
          final updated = SavedRobot(
            name: saved.name,
            ip: saved.ip,
            fleetServerHost: _fleetServerHost,
            fleetServerPort: _fleetServerPort,
            isFleetMode: _isFleetMode,
            fleetAuthToken: token,
          );
          await _store.save(updated);
        }
        _connectFleet();
        return true;
      }
      return false;
    } catch (e) {
      _error = 'Login failed: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setFleetMode(bool enabled, {String? host, int? port, String? token}) async {
    _isFleetMode = enabled;
    if (host != null) _fleetServerHost = host.trim();
    if (port != null) _fleetServerPort = port;
    if (token != null) _token = token.trim();

    final saved = await _store.load();
    if (saved != null) {
      final updated = SavedRobot(
        name: saved.name,
        ip: saved.ip,
        fleetServerHost: _fleetServerHost,
        fleetServerPort: _fleetServerPort,
        isFleetMode: _isFleetMode,
        fleetAuthToken: _token,
      );
      await _store.save(updated);
    }

    if (_isFleetMode) {
      _connectFleet();
    } else {
      _stopPolling();
    }
    notifyListeners();
  }

  void selectRobot(String id) {
    if (_selectedRobotId != id) {
      _selectedRobotId = id;
      notifyListeners();
    }
  }

  void selectLevel(String id) {
    if (_selectedLevelId != id) {
      _selectedLevelId = id;
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      refreshRobotsOnly();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refreshRobotsOnly() async {
    final api = _api;
    if (api == null || !_isFleetMode) return;
    try {
      final results = await Future.wait([
        api.getRobots(),
        api.getActiveMissions(),
      ]);
      _robots = results[0] as List<FleetRobotInfo>;
      _activeMissions = results[1] as List<Map<String, dynamic>>;
      _error = null;
      notifyListeners();
    } catch (e) {
      // transient poll error
    }
  }

  Future<void> refreshFleet() async {
    final api = _api;
    if (api == null) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        api.getRobots(),
        api.getLevels(),
        api.getFleets(),
        api.getActiveMissions(),
      ]);

      _robots = results[0] as List<FleetRobotInfo>;
      _levels = results[1] as List<FleetLevelInfo>;
      _fleets = results[2] as List<FleetInfo>;
      _activeMissions = results[3] as List<Map<String, dynamic>>;

      if (_selectedLevelId == null && _levels.isNotEmpty) {
        _selectedLevelId = _levels.first.id;
      }
      if (_selectedRobotId == null && _robots.isNotEmpty) {
        _selectedRobotId = _robots.first.id;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Syncs traffic lanes and waypoints to Open-RMF building graph on the Fleet Server.
  Future<bool> syncTrafficGraph({
    required String levelName,
    required List<MapZone> zones,
    List<Map<String, dynamic>>? waypoints,
  }) async {
    final api = _api;
    if (api == null || !_isFleetMode) return false;
    try {
      final buildings = await api.getBuildings();
      if (buildings.isEmpty) return false;
      final building = buildings.first;
      final buildingId = building['id'] as String;

      Map<String, dynamic> existingGraph = {};
      try {
        existingGraph = await api.getBuildingGraph(buildingId);
      } catch (_) {
        existingGraph = (building['graph'] as Map<String, dynamic>?) ?? {};
      }

      final existingWaypoints = List<Map<String, dynamic>>.from(existingGraph['waypoints'] as List? ?? []);
      final existingLanes = List<Map<String, dynamic>>.from(existingGraph['lanes'] as List? ?? []);
      final existingDoors = List<Map<String, dynamic>>.from(existingGraph['doors'] as List? ?? []);
      final existingLifts = List<Map<String, dynamic>>.from(existingGraph['lifts'] as List? ?? []);

      // Keep waypoints from other levels
      final preservedWaypoints = existingWaypoints.where((w) => w['levelName'] != levelName).toList();
      final preservedWaypointIds = preservedWaypoints.map((w) => w['id'] as String).toSet();

      // Keep lanes connecting preserved waypoints
      final preservedLanes = existingLanes.where((l) {
        final from = l['fromId'] as String?;
        final to = l['toId'] as String?;
        return preservedWaypointIds.contains(from) && preservedWaypointIds.contains(to);
      }).toList();

      final newLevelWaypoints = <Map<String, dynamic>>[];
      final newLevelLanes = <Map<String, dynamic>>[];

      // Add waypoints (docks, charging, points of interest)
      if (waypoints != null) {
        for (final wp in waypoints) {
          final name = wp['name'] as String? ?? 'wp';
          final id = wp['id'] as String? ?? 'wp_${levelName}_$name';
          final isDock = name.toLowerCase().contains('dock') || name.toLowerCase().contains('charger');
          newLevelWaypoints.add({
            'id': id,
            'name': name,
            'levelName': levelName,
            'x': (wp['x'] as num?)?.toDouble() ?? 0.0,
            'y': (wp['y'] as num?)?.toDouble() ?? 0.0,
            'isCharger': wp['isCharger'] == true || isDock,
            'isParking': wp['isParking'] == true || isDock,
          });
        }
      }

      // Convert preferred lanes from this level into Open-RMF graph vertices & bidirectional lane edges
      final preferredLanes = zones.where((z) => z.type == ZoneType.preferredLane && z.isCorridorLane).toList();
      for (int laneIdx = 0; laneIdx < preferredLanes.length; laneIdx++) {
        final lane = preferredLanes[laneIdx];
        final cl = lane.laneCenterline;
        final nodeIds = <String>[];
        for (int ptIdx = 0; ptIdx < cl.length; ptIdx++) {
          final pt = cl[ptIdx];
          final vertexId = 'lane_${lane.id}_v$ptIdx';
          final vertexName = '${lane.name}_$ptIdx';
          nodeIds.add(vertexId);
          newLevelWaypoints.add({
            'id': vertexId,
            'name': vertexName,
            'levelName': levelName,
            'x': pt.dx,
            'y': pt.dy,
            'isCharger': false,
            'isParking': false,
          });
        }
        for (int i = 0; i < nodeIds.length - 1; i++) {
          newLevelLanes.add({
            'fromId': nodeIds[i],
            'toId': nodeIds[i + 1],
            'bidirectional': true,
          });
        }
      }

      final updatedGraph = {
        'waypoints': [...preservedWaypoints, ...newLevelWaypoints],
        'lanes': [...preservedLanes, ...newLevelLanes],
        'doors': existingDoors,
        'lifts': existingLifts,
      };

      await api.updateBuildingGraph(buildingId, updatedGraph);
      return true;
    } catch (e) {
      debugPrint('Failed to sync traffic graph: $e');
      return false;
    }
  }

  // Robot Commissioning Actions
  Future<void> commissionRobot({
    required String robotId,
    required String fleetId,
    required String levelId,
    String? name,
    String? dockWaypoint,
    String? homeWaypoint,
    bool startNav = true,
  }) async {
    final api = _api;
    if (api == null) return;
    await api.activateRobot(
      robotId: robotId,
      fleetId: fleetId,
      levelId: levelId,
      name: name,
      dockWaypoint: dockWaypoint,
      homeWaypoint: homeWaypoint,
      startNav: startNav,
    );
    await refreshFleet();
  }

  Future<void> createRobot({
    required String serial,
    required String name,
    String? fleetId,
    String? levelId,
    String? dockWaypoint,
    String? homeWaypoint,
  }) async {
    final api = _api;
    if (api == null) return;
    await api.createRobot(
      serial: serial,
      name: name,
      fleetId: fleetId,
      levelId: levelId,
      dockWaypoint: dockWaypoint,
      homeWaypoint: homeWaypoint,
      status: 'active',
    );
    await refreshFleet();
  }

  Future<void> deleteRobot(String robotId) async {
    final api = _api;
    if (api == null) return;
    await api.deleteRobot(robotId);
    await refreshFleet();
  }

  Future<void> decommissionRobot(String robotId) async {
    final api = _api;
    if (api == null) return;
    await api.decommissionRobot(robotId);
    await refreshFleet();
  }

  Future<void> sendNavCommand({
    required String robotId,
    required String action,
    String? parkingWaypoint,
    double? x,
    double? y,
    double? yaw,
  }) async {
    final api = _api;
    if (api == null) return;
    await api.sendFleetNavCommand(
      robotId: robotId,
      action: action,
      levelId: _selectedLevelId,
      parkingWaypoint: parkingWaypoint,
      x: x,
      y: y,
      yaw: yaw,
    );
    await refreshRobotsOnly();
  }

  // Workflows / RMF Task Actions
  Future<void> dispatchTask({
    required String workflowId,
    required String fleet,
    String? robot,
  }) async {
    final api = _api;
    if (api == null) return;
    await api.submitMission(
      workflowId: workflowId,
      fleet: fleet,
      robot: robot,
    );
    await refreshFleet();
  }

  Future<Map<String, dynamic>> dispatchRmfTask({
    required String category, // 'patrol', 'delivery', 'clean', 'charge_battery'
    required Map<String, dynamic> description,
    String? fleetName,
    String? robotName,
  }) async {
    final api = _api;
    if (api == null) return {};
    final res = await api.dispatchRmfTask(
      category: category,
      description: description,
      fleetName: fleetName,
      robotName: robotName,
    );
    await refreshFleet();
    return res;
  }

  Future<void> cancelRmfTask(String taskId) async {
    final api = _api;
    if (api == null) return;
    try {
      await api.cancelRmfTask(taskId);
    } catch (_) {
      // In case task ID is a workflow mission id
      await api.cancelMission(taskId);
    }
    await refreshFleet();
  }

  Future<void> cancelTask(String missionId) async {
    final api = _api;
    if (api == null) return;
    await api.cancelMission(missionId);
    await refreshFleet();
  }

  // --- Robot Direct IP Mapping ---
  final Map<String, String> _robotIps = {};
  Map<String, String> get robotIps => Map.unmodifiable(_robotIps);

  void registerRobotIp(String robotId, String ip) {
    _robotIps[robotId] = ip;
    notifyListeners();
    _store.load().then((saved) {
      if (saved != null) {
        final updated = SavedRobot(
          name: saved.name,
          ip: saved.ip,
          fleetServerHost: saved.fleetServerHost,
          fleetServerPort: saved.fleetServerPort,
          isFleetMode: saved.isFleetMode,
          fleetAuthToken: saved.fleetAuthToken,
          fleetRobotIps: _robotIps,
        );
        _store.save(updated);
      }
    });
  }

  String? getRobotIp(String robotId) => _robotIps[robotId];

  // --- Robot Heartbeat / Live Pose Sync ---
  Future<void> reportRobotHeartbeat({
    required String robotId,
    required double x,
    required double y,
    required double yaw,
    double? batteryPercent,
    String mode = 'idle',
    String? levelName,
  }) async {
    final api = _api;
    if (api == null || !_isFleetMode) return;
    try {
      await api.sendHeartbeat(
        robotId: robotId,
        x: x,
        y: y,
        yaw: yaw,
        batteryPercent: batteryPercent,
        mode: mode,
        levelName: levelName ?? selectedLevel?.name,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
