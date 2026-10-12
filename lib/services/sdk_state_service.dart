import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mode_transition_tracker.dart';

/// The subset of navpromini_sdk's GET /api/v1/state (doc §18's canonical
/// Robot State model) this app actually reads — mode, current map, mission
/// status, lifecycle. Everything nullable: a field missing from the
/// response, or the whole poll failing, both mean "unknown", not zero/empty.
class SdkState {
  const SdkState({
    this.mode,
    this.mapName,
    this.missionStatus,
    this.pauseReason,
    this.lifecycle,
    this.cpuLoadPct,
    this.cpuTempC,
    this.batteryTempC,
    this.missionId,
    this.missionName,
    this.stepIndex,
    this.stepTotal,
    this.loopIndex,
    this.loopTotal,
    this.activeNodeLabel,
    this.progressPct,
    this.missionMessage,
  });

  final String? mode;
  final String? mapName;
  final String? missionStatus;
  final String? pauseReason;
  final String? lifecycle;
  final double? cpuLoadPct;
  final double? cpuTempC;
  final double? batteryTempC;

  // Enriched mission execution fields
  final String? missionId;
  final String? missionName;
  final int? stepIndex;
  final int? stepTotal;
  final int? loopIndex;
  final int? loopTotal;
  final String? activeNodeLabel;
  final int? progressPct;
  final String? missionMessage;

  factory SdkState.fromJson(Map<String, dynamic> json) {
    final sys = json['system'] as Map?;
    final temp = json['temperature'] as Map?;
    final cpuLoad = (sys?['cpu_load_pct'] as num?)?.toDouble() ??
        (json['cpu_load_pct'] as num?)?.toDouble();
    final cpuTemp = (sys?['cpu_temperature_c'] as num?)?.toDouble() ??
        (json['cpu_temperature_c'] as num?)?.toDouble() ??
        (temp?['cpu_c'] as num?)?.toDouble();
    final battTemp = (sys?['battery_temperature_c'] as num?)?.toDouble() ??
        (json['battery_temperature_c'] as num?)?.toDouble() ??
        (temp?['battery_c'] as num?)?.toDouble();

    final missionMap = json['mission'] as Map?;
    final missionStatus = (missionMap?['status'] ?? missionMap?['state']) as String?;
    final pauseReason = missionMap?['pause_reason'] as String?;
    final missionId = missionMap?['mission_id'] as String?;
    final missionName = missionMap?['mission_name'] as String?;
    final stepIndex = (missionMap?['step_index'] as num?)?.toInt();
    final stepTotal = (missionMap?['step_total'] as num?)?.toInt() ??
        (missionMap?['step_count'] as num?)?.toInt();
    final loopIndex = (missionMap?['loop_index'] as num?)?.toInt();
    final loopTotal = (missionMap?['loop_total'] as num?)?.toInt();
    final activeNodeLabel = missionMap?['active_node_label'] as String?;
    final progressPct = (missionMap?['progress_pct'] as num?)?.toInt();
    final missionMessage = missionMap?['message'] as String?;

    return SdkState(
      mode: json['mode'] as String?,
      mapName: (json['map'] as Map?)?['name'] as String?,
      missionStatus: missionStatus,
      pauseReason: pauseReason,
      lifecycle: json['lifecycle'] as String?,
      cpuLoadPct: cpuLoad,
      cpuTempC: cpuTemp,
      batteryTempC: battTemp,
      missionId: missionId,
      missionName: missionName,
      stepIndex: stepIndex,
      stepTotal: stepTotal,
      loopIndex: loopIndex,
      loopTotal: loopTotal,
      activeNodeLabel: activeNodeLabel,
      progressPct: progressPct,
      missionMessage: missionMessage,
    );
  }

  static const unknown = SdkState();
}

/// Optional enrichment on top of the app's real connection (rosbridge) — see
/// navpromini-sdk-is-optional-not-gateway in project memory. Polls
/// navpromini_sdk's /state endpoint (built earlier this session) for the
/// product-level fields that are otherwise hard to derive from raw topics.
/// Never throws to a caller — a failed poll just emits SdkState.unknown, so
/// a Dashboard built on this still works fully when the SDK isn't running.
class SdkStateService {
  SdkStateService(this.robotIp, {this.port = 8090});

  final String robotIp;
  final int port;

  String get _baseUrl => 'http://$robotIp:$port';

  SdkState _lastState = SdkState.unknown;

  Future<SdkState> fetchOnce() async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/api/v1/state'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return _lastState;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      _lastState = SdkState.fromJson(json);
      ModeTransitionTracker.instance.onSdkModeUpdated(_lastState.mode);
      return _lastState;
    } catch (_) {
      // Network drop, timeout, or transient error: retain the last known
      // state rather than instantly wiping active map/mode to null.
      return _lastState;
    }
  }

  /// Polls indefinitely until the returned subscription is cancelled.
  Stream<SdkState> watch(
      {Duration interval = const Duration(seconds: 3)}) async* {
    while (true) {
      yield await fetchOnce();
      await Future.delayed(interval);
    }
  }
}
