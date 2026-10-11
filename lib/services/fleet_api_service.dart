import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/fleet_models.dart';

class FleetApiException implements Exception {
  final int status;
  final String message;
  const FleetApiException(this.status, this.message);
  @override
  String toString() => 'FleetApiException($status): $message';
}

class FleetApiService {
  final String serverHost;
  final int port;
  final String? token;

  FleetApiService({
    required this.serverHost,
    this.port = 80,
    this.token,
  });

  String get baseUrl => port == 80 ? 'http://$serverHost' : 'http://$serverHost:$port';

  Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<dynamic> _get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    try {
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.isEmpty) return null;
        return jsonDecode(res.body);
      }
      throw FleetApiException(res.statusCode, 'GET $path failed: ${res.body}');
    } catch (e) {
      if (e is FleetApiException) rethrow;
      throw FleetApiException(0, 'Failed to connect to Fleet Server at $baseUrl: $e');
    }
  }

  Future<dynamic> _post(String path, {dynamic body}) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final res = await http.post(
        uri,
        headers: _headers,
        body: body != null ? jsonEncode(body) : null,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.isEmpty) return null;
        return jsonDecode(res.body);
      }
      throw FleetApiException(res.statusCode, 'POST $path failed: ${res.body}');
    } catch (e) {
      if (e is FleetApiException) rethrow;
      throw FleetApiException(0, 'Failed to connect to Fleet Server at $baseUrl: $e');
    }
  }

  Future<dynamic> _put(String path, {dynamic body}) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final res = await http.put(
        uri,
        headers: _headers,
        body: body != null ? jsonEncode(body) : null,
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.isEmpty) return null;
        return jsonDecode(res.body);
      }
      throw FleetApiException(res.statusCode, 'PUT $path failed: ${res.body}');
    } catch (e) {
      if (e is FleetApiException) rethrow;
      throw FleetApiException(0, 'Failed to connect to Fleet Server at $baseUrl: $e');
    }
  }

  Future<dynamic> _delete(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final res = await http.delete(uri, headers: _headers).timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.isEmpty) return null;
        return jsonDecode(res.body);
      }
      throw FleetApiException(res.statusCode, 'DELETE $path failed: ${res.body}');
    } catch (e) {
      if (e is FleetApiException) rethrow;
      throw FleetApiException(0, 'Failed to connect to Fleet Server at $baseUrl: $e');
    }
  }

  Future<void> updateRobotTransform({
    required String robotId,
    required String levelId,
    required double x,
    required double y,
    required double yaw,
    required double scale,
  }) async {
    await _put('/api/v1/robots/$robotId/transforms/$levelId', body: {
      'x': x,
      'y': y,
      'yaw': yaw,
      'scale': scale,
    });
  }

  // --- Auth ---
  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await _post('/api/v1/auth/login', body: {
      'username': username,
      'password': password,
    });
    return res as Map<String, dynamic>;
  }

  // --- Robots & Commissioning ---
  Future<List<FleetRobotInfo>> getRobots({String? fleet, String? status}) async {
    final query = <String, String>{};
    if (fleet != null) query['fleet'] = fleet;
    if (status != null) query['status'] = status;
    final res = await _get('/api/v1/robots', query: query);
    if (res is List) {
      return res.map((item) => FleetRobotInfo.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<FleetRobotInfo> getRobot(String robotId) async {
    final res = await _get('/api/v1/robots/$robotId');
    return FleetRobotInfo.fromJson(res as Map<String, dynamic>);
  }

  Future<void> activateRobot({
    required String robotId,
    required String fleetId,
    required String levelId,
    String? name,
    String? dockWaypoint,
    String? homeWaypoint,
    bool startNav = true,
  }) async {
    await _post('/api/v1/robots/$robotId/activate', body: {
      'fleetId': fleetId,
      'levelId': levelId,
      if (name != null) 'name': name,
      if (dockWaypoint != null) 'dockWaypoint': dockWaypoint,
      if (homeWaypoint != null) 'homeWaypoint': homeWaypoint,
      'startNav': startNav,
    });
  }

  Future<void> decommissionRobot(String robotId) async {
    await _post('/api/v1/robots/$robotId/decommission');
  }

  Future<FleetRobotInfo> createRobot({
    required String serial,
    required String name,
    String? fleetId,
    String? levelId,
    String? dockWaypoint,
    String? homeWaypoint,
    String status = 'active',
  }) async {
    final res = await _post('/api/v1/robots', body: {
      'serial': serial,
      'name': name,
      if (fleetId != null && fleetId.isNotEmpty) 'fleetId': fleetId,
      if (levelId != null && levelId.isNotEmpty) 'levelId': levelId,
      if (dockWaypoint != null && dockWaypoint.isNotEmpty) 'dockWaypoint': dockWaypoint,
      if (homeWaypoint != null && homeWaypoint.isNotEmpty) 'homeWaypoint': homeWaypoint,
      'status': status,
    });
    return FleetRobotInfo.fromJson(res as Map<String, dynamic>);
  }

  Future<void> deleteRobot(String robotId) async {
    await _delete('/api/v1/robots/$robotId');
  }

  Future<void> sendFleetNavCommand({
    required String robotId,
    required String action, // 'start_nav', 'stop_nav', 'set_pose'
    String? levelId,
    String? parkingWaypoint,
    double? x,
    double? y,
    double? yaw,
  }) async {
    await _post('/api/v1/robots/$robotId/nav', body: {
      'action': action,
      if (levelId != null) 'levelId': levelId,
      if (parkingWaypoint != null) 'parkingWaypoint': parkingWaypoint,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (yaw != null) 'yaw': yaw,
    });
  }

  // --- Levels & Multi-Floor ---
  Future<List<FleetLevelInfo>> getLevels() async {
    final res = await _get('/api/v1/levels');
    if (res is List) {
      return res.map((item) => FleetLevelInfo.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getLevelWaypoints(String levelId, {bool parkingOnly = false}) async {
    final res = await _get('/api/v1/levels/$levelId/waypoints', query: {
      'parking': parkingOnly ? '1' : '0',
    });
    if (res is List) {
      return res.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // --- Fleets ---
  Future<List<FleetInfo>> getFleets() async {
    final res = await _get('/api/v1/fleets');
    if (res is List) {
      return res.map((item) => FleetInfo.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }

  // --- Site & Traffic Graph ---
  Future<Map<String, dynamic>> getBuildingGraph() async {
    final res = await _get('/api/v1/site/building');
    return res as Map<String, dynamic>? ?? {};
  }

  Future<void> uploadBuildingYaml(String yamlContent) async {
    await _post('/api/v1/site/building-yaml', body: {
      'yaml': yamlContent,
    });
  }

  Future<void> reloadTrafficGraph() async {
    await _post('/api/v1/site/reload');
  }

  // --- Workflows & RMF Tasks ---
  Future<List<Map<String, dynamic>>> getWorkflows() async {
    final res = await _get('/api/v1/workflows');
    if (res is List) return res.cast<Map<String, dynamic>>();
    return [];
  }

  Future<Map<String, dynamic>> submitMission({
    required String workflowId,
    required String fleet,
    String? robot,
    int? version,
  }) async {
    final res = await _post('/api/v1/missions', body: {
      'workflowId': workflowId,
      'fleet': fleet,
      if (robot != null) 'robot': robot,
      if (version != null) 'version': version,
    });
    return res as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getActiveMissions() async {
    final res = await _get('/api/v1/missions');
    if (res is List) return res.cast<Map<String, dynamic>>();
    return [];
  }

  Future<void> cancelMission(String missionId) async {
    await _post('/api/v1/missions/$missionId/cancel');
  }

  // --- Open-RMF Task Dispatching ---
  Future<Map<String, dynamic>> dispatchRmfTask({
    required String category, // 'patrol', 'delivery', 'clean', 'charge_battery'
    required Map<String, dynamic> description,
    String? fleetName,
    String? robotName,
  }) async {
    final payload = {
      'type': 'dispatch_task_request',
      'request': {
        'category': category,
        'description': description,
        if (fleetName != null && fleetName.isNotEmpty) 'fleet_name': fleetName,
        if (robotName != null && robotName.isNotEmpty) 'robot_name': robotName,
      },
    };
    final res = await _post('/rmf/tasks/dispatch_task', body: payload);
    return res as Map<String, dynamic>? ?? {};
  }

  Future<void> cancelRmfTask(String taskId) async {
    await _post('/rmf/tasks/cancel_task', body: {
      'type': 'cancel_task_request',
      'task_id': taskId,
    });
  }

  // --- Robot Heartbeat / Telemetry Sync ---
  Future<void> sendHeartbeat({
    required String robotId,
    required double x,
    required double y,
    required double yaw,
    double? batteryPercent,
    String mode = 'idle',
    String? levelName,
  }) async {
    await _post('/api/v1/robots/$robotId/heartbeat', body: {
      'pose': {
        'x': x,
        'y': y,
        'yaw': yaw,
        if (levelName != null && levelName.isNotEmpty) 'levelName': levelName,
      },
      if (batteryPercent != null) 'batterySoc': batteryPercent,
      'mode': mode,
    });
  }
}

