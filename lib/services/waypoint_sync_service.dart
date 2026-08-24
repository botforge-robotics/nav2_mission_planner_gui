import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_msgs/msg.dart' as std_msgs;

import '../modals/bookmark.dart';
import '../providers/connection_provider.dart';

/// Mirrors every bookmark, across every map, to the robot's own
/// waypoint_store_node (`/waypoints`, reliable + transient_local) — the
/// same "robot is the durable copy" pattern DockingService already uses for
/// the single dock pose, generalized to all named bookmarks.
///
/// Without this, bookmarks only ever lived in this device's
/// SharedPreferences (see SettingsProvider) — invisible to a fresh device,
/// another client, or a future web API's `goto by name`.
///
/// Singleton, same shape as DockingService/TFService.
class WaypointSyncService extends ChangeNotifier {
  static WaypointSyncService? _instance;
  static WaypointSyncService get instance =>
      _instance ??= WaypointSyncService._();
  WaypointSyncService._();

  static const String topicName = '/waypoints';

  Ros2? _ros2;
  Publisher<std_msgs.StringMessage>? _pub;
  Subscriber<std_msgs.StringMessage>? _sub;

  /// The last full bookmark set received FROM the robot — distinct from
  /// whatever SettingsProvider currently holds locally. Callers decide how
  /// (or whether) to reconcile the two; this service only mirrors, it
  /// doesn't overwrite local state on its own.
  Map<String, List<Bookmark>>? _fromRobot;
  Map<String, List<Bookmark>>? get fromRobot => _fromRobot;

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
        callback: _onWaypoints,
      );
    } catch (e) {
      debugPrint('WaypointSyncService: /waypoints subscribe failed: $e');
    }
  }

  void _onWaypoints(std_msgs.StringMessage msg) {
    if (msg.data.isEmpty) return;
    try {
      final decoded = jsonDecode(msg.data) as Map<String, dynamic>;
      _fromRobot = {
        for (final entry in decoded.entries)
          entry.key: (entry.value as List)
              .map((j) => Bookmark.fromJson(j as Map<String, dynamic>))
              .toList(),
      };
      notifyListeners();
    } catch (e) {
      debugPrint('WaypointSyncService: failed to parse /waypoints: $e');
    }
  }

  /// Pushes the FULL bookmark set (every map) to the robot — a whole-blob
  /// replace, matching waypoint_store_node.py's contract (no per-waypoint
  /// add/remove endpoint; the caller already has the complete map in memory
  /// via SettingsProvider, so sending it all costs nothing extra). Call
  /// after any bookmark add/edit/delete.
  void pushAll(Map<String, List<Bookmark>> bookmarksByMap) {
    final pub = _pub;
    if (pub == null) return;
    final json = jsonEncode({
      for (final entry in bookmarksByMap.entries)
        entry.key: entry.value.map((b) => b.toJson()).toList(),
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
