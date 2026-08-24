import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_msgs/msg.dart' as std_msgs;

import '../modals/mission.dart';
import '../providers/connection_provider.dart';

/// Mirrors every saved mission to the robot's app_data_store_node
/// (`/missions`, reliable + transient_local) — same pattern as
/// WaypointSyncService for bookmarks, and DockingService's dock pose before
/// that: the robot holds the durable, shared copy instead of each client
/// (this app, another device, a future web API) carrying its own
/// local-only one.
///
/// Singleton, same shape as WaypointSyncService/DockingService/TFService.
class MissionSyncService extends ChangeNotifier {
  static MissionSyncService? _instance;
  static MissionSyncService get instance =>
      _instance ??= MissionSyncService._();
  MissionSyncService._();

  static const String topicName = '/missions';

  Ros2? _ros2;
  Publisher<std_msgs.StringMessage>? _pub;
  Subscriber<std_msgs.StringMessage>? _sub;

  /// The last full mission set received FROM the robot — distinct from
  /// whatever SettingsProvider currently holds locally. Callers decide how
  /// (or whether) to reconcile the two; this service only mirrors, it
  /// doesn't overwrite local state on its own.
  Map<String, Mission>? _fromRobot;
  Map<String, Mission>? get fromRobot => _fromRobot;

  void initialize(BuildContext context) {
    final ros2 =
        Provider.of<ConnectionProvider>(context, listen: false).ros2Client;
    if (identical(_ros2, ros2)) return; // already wired to this connection
    _teardown();
    _ros2 = ros2;

    _pub = Publisher<std_msgs.StringMessage>(
      name: topicName,
      type: std_msgs.StringMessage().fullType,
      ros2: ros2,
    );

    try {
      _sub = Subscriber<std_msgs.StringMessage>(
        name: topicName,
        type: std_msgs.StringMessage().fullType,
        ros2: ros2,
        prototype: std_msgs.StringMessage(),
        callback: _onMissions,
      );
    } catch (e) {
      debugPrint('MissionSyncService: /missions subscribe failed: $e');
    }
  }

  void _onMissions(std_msgs.StringMessage msg) {
    if (msg.data.isEmpty) return;
    try {
      final decoded = jsonDecode(msg.data) as Map<String, dynamic>;
      _fromRobot = {
        for (final entry in decoded.entries)
          entry.key: Mission.fromJson(entry.value as Map<String, dynamic>),
      };
      notifyListeners();
    } catch (e) {
      debugPrint('MissionSyncService: failed to parse /missions: $e');
    }
  }

  /// Pushes the FULL mission set to the robot — a whole-blob replace,
  /// matching app_data_store_node.py's contract (no per-mission
  /// add/remove endpoint; the caller already has the complete map in
  /// memory via SettingsProvider, so sending it all costs nothing extra).
  /// Call after every mission save/delete.
  void pushAll(Map<String, Mission> missionsByKey) {
    final pub = _pub;
    if (pub == null) return;
    final json = jsonEncode({
      for (final entry in missionsByKey.entries)
        entry.key: entry.value.toJson(),
    });
    pub.publish(std_msgs.StringMessage(data: json));
  }

  void _teardown() {
    _sub?.shutdown();
    _sub = null;
    _pub?.shutdown();
    _pub = null;
  }

  void shutdown() {
    _teardown();
    _ros2 = null;
    _fromRobot = null;
  }
}
