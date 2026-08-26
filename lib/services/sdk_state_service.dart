import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The subset of navpromini_sdk's GET /api/v1/state (doc §18's canonical
/// Robot State model) this app actually reads — mode, current map, mission
/// status, lifecycle. Everything nullable: a field missing from the
/// response, or the whole poll failing, both mean "unknown", not zero/empty.
class SdkState {
  const SdkState({this.mode, this.mapName, this.missionStatus, this.lifecycle});

  final String? mode;
  final String? mapName;
  final String? missionStatus;
  final String? lifecycle;

  factory SdkState.fromJson(Map<String, dynamic> json) => SdkState(
        mode: json['mode'] as String?,
        mapName: (json['map'] as Map?)?['name'] as String?,
        missionStatus: (json['mission'] as Map?)?['status'] as String?,
        lifecycle: json['lifecycle'] as String?,
      );

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

  Future<SdkState> fetchOnce() async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/api/v1/state'))
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) return SdkState.unknown;
      return SdkState.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    } catch (_) {
      return SdkState.unknown;
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
