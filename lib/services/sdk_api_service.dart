import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown for every failure path — a non-2xx response with the SDK's own
/// `{"error": {"code","message","detail"}}` body (see navpromini_sdk's
/// handlers/base.py), or the request never reaching the robot at all (SDK
/// not running, wrong IP, timeout). `code` is `'unreachable'` for the latter
/// so callers can special-case "the SDK just isn't up right now" — expected
/// and common, since the SDK is optional enrichment, not the app's core
/// connection — separately from a real API error.
class SdkApiException implements Exception {
  const SdkApiException(this.code, this.message,
      [this.detail = const {}, this.status = 0]);

  final String code;
  final String message;
  final Map<String, dynamic> detail;

  /// The real HTTP status code, or 0 when the request never got a response
  /// at all (`code == 'unreachable'`) — kept separate from [code], which is
  /// the SDK's own business error code (e.g. `waypoint_not_found`), not
  /// necessarily derivable from the status.
  final int status;

  bool get isUnreachable => code == 'unreachable';

  @override
  String toString() => message;
}

/// Thin client for navpromini_sdk's HTTP surface (`/api/v1/...`) — the
/// mission runner, waypoint store, docking/motion actions and raw-tool calls
/// that have no ROS-native equivalent worth reimplementing client-side (see
/// navpromini-sdk-is-optional-not-gateway in project memory: this is exactly
/// the "genuinely SDK-exclusive functionality" carve-out, not a routing of
/// core connectivity through the SDK). Every screen built on this must treat
/// [SdkApiException.isUnreachable] as a normal, expected state — the SDK
/// service may simply not be running.
class SdkApiService {
  SdkApiService(this.robotIp, {this.port = 8090});

  final String robotIp;
  final int port;

  String get baseUrl => 'http://$robotIp:$port';
  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final result = await _sendWithStatus(method, path,
        body: body, query: query, timeout: timeout);
    return result.body;
  }

  Future<({int status, Map<String, dynamic> body})> _sendWithStatus(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    late final http.Response resp;
    try {
      final uri = _uri(path, query);
      final headers = {'Content-Type': 'application/json'};
      final encoded = body != null ? jsonEncode(body) : null;
      final future = switch (method) {
        'GET' => http.get(uri, headers: headers),
        'POST' => http.post(uri, headers: headers, body: encoded),
        'PUT' => http.put(uri, headers: headers, body: encoded),
        'DELETE' => http.delete(uri, headers: headers),
        _ => throw ArgumentError('Unsupported method $method'),
      };
      resp = await future.timeout(timeout);
    } catch (exc) {
      throw SdkApiException(
        'unreachable',
        "Can't reach the robot's SDK at $baseUrl. It may not be running — "
            'this feature needs navpro-sdk.service.',
      );
    }

    final raw = resp.body.trim();
    Map<String, dynamic> parsed = const {};
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) parsed = decoded;
      } catch (_) {
        // Non-JSON body (shouldn't happen — every SDK response is JSON per
        // base.py) — fall through with an empty map and let the status code
        // still decide success/failure below.
      }
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return (status: resp.statusCode, body: parsed);
    }

    final error = parsed['error'] as Map<String, dynamic>?;
    throw SdkApiException(
      error?['code'] as String? ?? 'http_${resp.statusCode}',
      error?['message'] as String? ??
          'Request failed (HTTP ${resp.statusCode})',
      (error?['detail'] as Map?)?.cast<String, dynamic>() ?? const {},
      resp.statusCode,
    );
  }

  // -- system --------------------------------------------------------------

  Future<Map<String, dynamic>> systemInfo() =>
      _send('GET', '/api/v1/system/info');
  Future<Map<String, dynamic>> systemHealth() =>
      _send('GET', '/api/v1/system/health');

  // -- state -----------------------------------------------------------------

  /// Full BMS telemetry — `data` carries percentage/voltage/current/
  /// temperature/status/charging (the same shape RobotTelemetryProvider's
  /// own rosbridge subscription derives its percentage from), `detail`
  /// carries the raw pack read this app doesn't otherwise surface:
  /// remain_capacity_ah, per-cell voltages/temperatures, charge_state,
  /// charger_connected, failure_bits. Used by Dock & Charge for the fields
  /// beyond plain percentage.
  Future<Map<String, dynamic>> battery() =>
      _send('GET', '/api/v1/state/battery');

  // -- waypoints (Locations) ------------------------------------------------

  Future<List<Map<String, dynamic>>> listWaypoints() async {
    final resp = await _send('GET', '/api/v1/waypoints');
    return (resp['waypoints'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  /// Saves a named waypoint. With [x]/[y] omitted, the endpoint captures the
  /// robot's *current* map-frame pose instead (its own documented default —
  /// see handlers/waypoints.py's own docstring); passed explicitly, it saves
  /// exactly that pose instead — used by Map View's click-drag "Add
  /// Location" pose picker.
  Future<Map<String, dynamic>> saveWaypoint(String name,
      {double? x,
      double? y,
      double theta = 0.0,
      String type = 'waypoint'}) async {
    final resp = await _send('POST', '/api/v1/waypoints', body: {
      'name': name,
      'type': type,
      if (x != null && y != null) ...{'x': x, 'y': y, 'theta': theta},
    });
    return resp['waypoint'] as Map<String, dynamic>;
  }

  Future<void> deleteWaypoint(String name) =>
      _send('DELETE', '/api/v1/waypoints/${Uri.encodeComponent(name)}');

  // -- navigation ------------------------------------------------------------

  Future<void> goToWaypoint(String name, {bool replace = false}) =>
      _send('POST', '/api/v1/navigation/goto',
          body: {'waypoint': name, if (replace) 'replace': true},
          timeout: const Duration(seconds: 20));

  Future<void> goToPose(double x, double y,
          {double theta = 0.0, bool replace = false}) =>
      _send(
        'POST',
        '/api/v1/navigation/goto',
        body: {'x': x, 'y': y, 'theta': theta, if (replace) 'replace': true},
        timeout: const Duration(seconds: 20),
      );

  Future<Map<String, dynamic>> navigationStatus() =>
      _send('GET', '/api/v1/navigation/status');

  Future<void> cancelNavigation() => _send('DELETE', '/api/v1/navigation/goal');

  /// Cancels an in-progress dock/undock goal — a separate route from
  /// [cancelNavigation] since dock/undock goals are tracked separately on
  /// the robot (handlers/docking.py's own TRACKER, distinct from
  /// navigation.py's). Used by the auto-retry loop's "Cancel" action.
  Future<void> cancelDock() => _send('DELETE', '/api/v1/dock/goal');

  /// Seeds AMCL's belief of where the robot is — the "2D Pose Estimate"
  /// equivalent. Doesn't move the robot; only corrects localization.
  Future<void> localize(double x, double y, {double theta = 0.0}) =>
      _send('POST', '/api/v1/navigation/localize',
          body: {'x': x, 'y': y, 'theta': theta});

  /// Triggers AMCL /reinitialize_global_localization to disperse particle cloud
  /// across map free space for global relocalization recovery.
  Future<void> reinitializeGlobalLocalization() =>
      _send('POST', '/api/v1/navigation/relocalize/global');

  // -- docking ---------------------------------------------------------------

  Future<void> dock({bool navigateToStaging = true}) =>
      _send('POST', '/api/v1/dock',
          body: {'navigate_to_staging': navigateToStaging});

  Future<void> undock() => _send('POST', '/api/v1/undock');

  Future<Map<String, dynamic>> dockStatus() =>
      _send('GET', '/api/v1/dock/status');

  /// Where the robot believes its dock is — used by the "Robot at Dock"
  /// localize option. 404s (as `not_found`-ish text via the SDK's
  /// `no_dock_pose` code) when no dock pose is known yet.
  Future<Map<String, dynamic>> dockPose() => _send('GET', '/api/v1/dock/pose');

  /// Set and persist the robot's dock pose in map coordinates.
  Future<void> setDockPose({
    required double x,
    required double y,
    double theta = 0.0,
  }) =>
      _send('PUT', '/api/v1/dock/pose',
          body: {'x': x, 'y': y, 'theta': theta});

  /// Permanently removes the saved dock pose from the robot.
  Future<void> deleteDockPose() => _send('DELETE', '/api/v1/dock/pose');

  // -- mode (idle / mapping / navigation) -------------------------------------

  Future<Map<String, dynamic>> modeStatus() => _send('GET', '/api/v1/mode');

  // switch_mode() on the robot (mode.py) fully awaits stopping whatever's
  // currently running (StopLaunch, up to 90s) before starting the new mode
  // (LaunchWithArgs, up to 60s) — the HTTP response doesn't come back until
  // both finish, so a short client timeout here doesn't mean "the SDK is
  // unreachable", it just means the switch is still legitimately running.
  // The earlier default 8s timeout produced exactly that false read: the
  // client gave up and reported 'unreachable' while the switch went on to
  // succeed anyway a few seconds later.
  static const _modeChangeTimeout = Duration(seconds: 170);

  /// Switches the robot's operating mode. `map` is required when switching to
  /// `navigation` with no map already loaded; ignored for `mapping`/`idle`.
  /// Mutually exclusive with whatever's currently running — mapping and
  /// navigation can't overlap (both own the map->odom transform) — so this
  /// stops the current launch first.
  Future<Map<String, dynamic>> setMode(String mode, {String? map}) => _send(
        'POST',
        '/api/v1/mode',
        body: {'mode': mode, if (map != null) 'map': map},
        timeout: _modeChangeTimeout,
      );

  /// Fetches all saved maps on the robot via the SDK.
  Future<List<String>> listMaps() async {
    final resp = await _send('GET', '/api/v1/maps');
    final maps = resp['maps'];
    if (maps is List) {
      return maps.map((e) => e.toString()).toList();
    }
    return const [];
  }

  /// Switches navigation onto a different saved map — restarts the
  /// navigation stack on it. Convenience wrapper the SDK itself provides
  /// (`POST /maps/{name}/activate`) over the equivalent `setMode('navigation', map: name)`.
  Future<Map<String, dynamic>> activateMap(String name) => _send(
        'POST',
        '/api/v1/maps/${Uri.encodeComponent(name)}/activate',
        timeout: _modeChangeTimeout,
      );

  /// Permanently deletes a saved map. The SDK itself refuses (`409
  /// map_in_use`) if navigation is currently running on it — switch modes
  /// or activate a different map first.
  Future<void> deleteMap(String name) =>
      _send('DELETE', '/api/v1/maps/${Uri.encodeComponent(name)}');

  /// Atomic "finish mapping": stops SLAM (switch_mode('idle'), up to 90s),
  /// saves the map (up to 120s, the robot's own save_map timeout), then
  /// switches navigation onto it (switch_mode('navigation'), up to 150s) —
  /// three of the SDK's own slow steps chained in one blocking call.
  Future<Map<String, dynamic>> finishMapping(String name,
          {bool overwrite = false}) =>
      _send(
        'POST',
        '/api/v1/mapping/finish',
        body: {'name': name, 'overwrite': overwrite},
        timeout: const Duration(seconds: 380),
      );

  // -- motion (teleop) ---------------------------------------------------------

  Future<void> setVelocity(double linear, double angular) =>
      _send('POST', '/api/v1/motion/velocity',
          body: {'linear': linear, 'angular': angular});

  Future<void> stopMotion() => _send('POST', '/api/v1/motion/stop');

  /// Fetches the currently loaded map name from the robot.
  Future<String?> getCurrentMap() async {
    try {
      final resp = await _send('GET', '/api/v1/maps/current');
      return resp['current'] as String?;
    } catch (_) {
      return null;
    }
  }

  // -- missions ----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listMissions({String? map}) async {
    final path = map != null && map.isNotEmpty
        ? '/api/v1/missions?map=${Uri.encodeComponent(map)}'
        : '/api/v1/missions';
    final resp = await _send('GET', path);
    return (resp['missions'] as List? ?? const []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> putMission(
      String id, String name, List<Map<String, dynamic>> steps,
      {int loopCount = 1, bool loopForever = false, String? map}) async {
    final resp = await _send('POST', '/api/v1/missions', body: {
      'id': id,
      'name': name,
      'steps': steps,
      'loop_count': loopCount,
      'loop_forever': loopForever,
      if (map != null && map.isNotEmpty) 'map': map,
    });
    return resp['mission'] as Map<String, dynamic>;
  }

  /// Saves a visual node-and-edge graph mission.
  Future<Map<String, dynamic>> putGraphMission(
      Map<String, dynamic> missionData) async {
    final resp = await _send('POST', '/api/v1/missions', body: missionData);
    return resp['mission'] as Map<String, dynamic>;
  }

  /// Fetches the catalog of all available graph node types from the robot SDK.
  Future<Map<String, dynamic>> fetchNodeTypes() async {
    final resp = await _send('GET', '/api/v1/missions/node_types');
    return (resp['node_types'] as Map? ?? const {}).cast<String, dynamic>();
  }

  /// Fetches currently active on-screen human interaction, if any.
  Future<Map<String, dynamic>?> fetchActiveUiInteraction() async {
    final resp = await _send('GET', '/api/v1/missions/active_ui_interaction');
    return resp['active_interaction'] as Map<String, dynamic>?;
  }

  /// Submits operator response for an on-screen form, choice, or kiosk prompt.
  Future<void> submitUiResponse(
    String interactionId, {
    String action = 'submit',
    String? selected,
    Map<String, dynamic>? formData,
  }) =>
      _send('POST', '/api/v1/missions/ui_response', body: {
        'interaction_id': interactionId,
        'action': action,
        if (selected != null) 'selected': selected,
        if (formData != null) 'form_data': formData,
      });

  Future<void> deleteMission(String id) =>
      _send('DELETE', '/api/v1/missions/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> missionStatus() =>
      _send('GET', '/api/v1/missions/status');

  Future<void> startMission(String id) =>
      _send('POST', '/api/v1/missions/${Uri.encodeComponent(id)}/start');
  Future<void> pauseMission(String id) =>
      _send('POST', '/api/v1/missions/${Uri.encodeComponent(id)}/pause');
  Future<void> resumeMission(String id) =>
      _send('POST', '/api/v1/missions/${Uri.encodeComponent(id)}/resume');
  Future<void> cancelMission(String id) =>
      _send('POST', '/api/v1/missions/${Uri.encodeComponent(id)}/cancel');

  /// Upload an image or video directly to the robot for on-screen mission display.
  Future<Map<String, dynamic>> uploadMedia(List<int> bytes, String filename) async {
    final uri = _uri('/api/v1/media/upload');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
    ));
    try {
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamedResponse);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } else {
        throw SdkApiException('upload_failed', 'Failed to upload media: ${resp.body}', const {}, resp.statusCode);
      }
    } catch (e) {
      if (e is SdkApiException) rethrow;
      throw SdkApiException('unreachable', 'Failed to connect to robot for upload: $e');
    }
  }

  // -- schedules ---------------------------------------------------------------

  Future<List<Map<String, dynamic>>> listSchedules() async {
    final resp = await _send('GET', '/api/v1/schedules');
    return (resp['schedules'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  /// Create or replace a schedule. [date] is required (YYYY-MM-DD) when
  /// [repeat] is 'once'; [weekdays] (0=Monday..6=Sunday) is required when
  /// [repeat] is 'weekly' — matches handlers/schedules.py's own validation
  /// exactly, so a mistake here surfaces as a real 400, not a silent no-op.
  Future<Map<String, dynamic>> putSchedule(
    String id, {
    required String missionId,
    required String name,
    required int hour,
    required int minute,
    required String repeat,
    String? date,
    List<int> weekdays = const [],
    bool enabled = true,
  }) async {
    final resp = await _send('POST', '/api/v1/schedules', body: {
      'id': id,
      'mission_id': missionId,
      'name': name,
      'hour': hour,
      'minute': minute,
      'repeat': repeat,
      if (date != null) 'date': date,
      if (weekdays.isNotEmpty) 'weekdays': weekdays,
      'enabled': enabled,
    });
    return resp['schedule'] as Map<String, dynamic>;
  }

  Future<void> deleteSchedule(String id) =>
      _send('DELETE', '/api/v1/schedules/${Uri.encodeComponent(id)}');

  /// Escape hatch for the Tools (Raw API) screen — an arbitrary path under
  /// `/api/v1`, any method, optional JSON body, returning the raw decoded
  /// body and status rather than throwing, since this screen's whole job is
  /// to show the caller exactly what came back (errors included).
  Future<({int status, Map<String, dynamic> body})> raw(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      return await _sendWithStatus(method, path,
          body: body, timeout: const Duration(seconds: 15));
    } on SdkApiException catch (exc) {
      return (
        status: exc.status,
        body: {
          'error': {
            'code': exc.code,
            'message': exc.message,
            'detail': exc.detail
          }
        },
      );
    }
  }

  // -- Software Updates (OTA) -----------------------------------------------

  Future<Map<String, dynamic>> getRobotUpdates() =>
      _send('GET', '/api/v1/system/updates');

  Future<Map<String, dynamic>> checkRobotUpdates() =>
      _send('POST', '/api/v1/system/updates/check', timeout: const Duration(seconds: 35));

  Future<Map<String, dynamic>> applyRobotUpdate() =>
      _send('POST', '/api/v1/system/updates/apply');

  Future<Map<String, dynamic>> getRobotUpdateStatus() =>
      _send('GET', '/api/v1/system/updates/status');
}
