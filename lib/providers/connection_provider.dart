import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ros2_api/ros2_api.dart';

import '../services/robot_connection_store.dart';

/// Owns the app's one live rosbridge connection — shared by Dashboard and
/// every future live screen (Teleop, Navigation, Mapping), not reconnected
/// per screen. Lazily created (Provider's default): Setup never pays for a
/// connection it doesn't use, since nothing in that flow reads this.
///
/// This is the app's *primary* connection path, unconditionally — it does
/// not depend on navpromini_sdk being reachable (see
/// navpromini-sdk-is-optional-not-gateway in project memory). SDK-backed
/// data (mode, current map, mission status) is a separate, optional
/// enrichment — see SdkStateService.
class ConnectionProvider extends ChangeNotifier {
  ConnectionProvider({RobotConnectionStore? store})
      : _store = store ?? RobotConnectionStore() {
    _connect();
  }

  final RobotConnectionStore _store;
  Ros2? _ros2;
  StreamSubscription<Status>? _statusSub;

  SavedRobot? robot;
  Status status = Status.none;
  String? error;

  Ros2? get ros2 => _ros2;
  bool get isConnected => status == Status.connected;

  Future<void> _connect() async {
    error = null;
    status = Status.connecting;
    notifyListeners();

    final saved = await _store.load();
    robot = saved;
    if (saved == null) {
      error = 'No robot configured.';
      status = Status.none;
      notifyListeners();
      return;
    }

    final ros2 = Ros2(url: saved.rosbridgeUrl);
    _ros2 = ros2;
    _statusSub = ros2.statusStream.listen((s) {
      status = s;
      if (s == Status.errored || s == Status.closed) {
        error = 'Lost connection to ${saved.name}.';
      } else if (s == Status.connected) {
        error = null;
      }
      notifyListeners();
    });

    try {
      ros2.connect();
    } catch (e) {
      error = 'Could not connect: $e';
      notifyListeners();
    }
  }

  /// Closes and reopens the connection — same robot, fresh socket. Used by
  /// a "Reconnect" affordance rather than making the caller re-derive the
  /// robot's address itself.
  Future<void> reconnect() async {
    await _ros2?.close();
    await _statusSub?.cancel();
    error = null;
    notifyListeners();
    await _connect();
  }

  /// Disconnects and forgets the saved robot — used by Settings' "Run Setup
  /// Again". The caller is responsible for navigating to the setup flow
  /// afterwards; this only clears connection state and persisted storage.
  Future<void> forget() async {
    await _ros2?.close();
    await _statusSub?.cancel();
    await _store.clear();
    _ros2 = null;
    robot = null;
    status = Status.none;
    error = 'No robot configured.';
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _ros2?.close();
    super.dispose();
  }
}
