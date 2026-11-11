import 'dart:async';

import 'package:flutter/widgets.dart';
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
///
/// Lifecycle & Backgrounding Persistence:
/// Implements [WidgetsBindingObserver] to monitor app lifecycle states.
/// When the app moves to background (or screen locks/sleeps) and resumes,
/// or whenever the connection drops (e.g. Wi-Fi blip, robot reboot),
/// [ConnectionProvider] automatically and persistently schedules reconnection
/// attempts until the app is closed completely or the operator explicitly
/// disconnects via [forget].
class ConnectionProvider extends ChangeNotifier with WidgetsBindingObserver {
  ConnectionProvider({RobotConnectionStore? store})
      : _store = store ?? RobotConnectionStore() {
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  final RobotConnectionStore _store;
  Ros2? _ros2;
  StreamSubscription<Status>? _statusSub;
  Timer? _connectTimeoutTimer;
  Timer? _autoReconnectTimer;

  bool _userInitiatedDisconnect = false;
  bool _hasConnectedOnce = false;
  bool _disposed = false;

  SavedRobot? robot;
  Status status = Status.none;
  String? error;

  Ros2? get ros2 => _ros2;
  bool get isConnected => status == Status.connected;
  bool get hasConnectedOnce => _hasConnectedOnce;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // When resuming from background or screen unlock, immediately verify
      // socket health and restore connection if dropped.
      if (status != Status.connected && robot != null && !_userInitiatedDisconnect) {
        debugPrint('[ConnectionProvider] App resumed from background — immediately reconnecting');
        _scheduleAutoReconnect(immediate: true);
      }
    }
  }

  Future<void> _connect() async {
    _connectTimeoutTimer?.cancel();
    _autoReconnectTimer?.cancel();
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

    _connectTimeoutTimer = Timer(const Duration(seconds: 7), () {
      if (status == Status.connecting) {
        error = 'Unable to reach ${saved.name} at ${saved.ip}.\n'
            'Make sure the robot is powered on and on the same network.';
        notifyListeners();
        // Keep retrying automatically even after initial timeout
        _scheduleAutoReconnect();
      }
    });

    final ros2 = Ros2(url: saved.rosbridgeUrl);
    _ros2 = ros2;
    _statusSub = ros2.statusStream.listen((s) {
      status = s;
      if (s == Status.errored || s == Status.closed) {
        _connectTimeoutTimer?.cancel();
        error = 'Lost connection to ${saved.name} (${saved.ip}).';
        // Auto-reconnect persistently until connected or app is closed
        if (!_userInitiatedDisconnect && robot != null) {
          _scheduleAutoReconnect();
        }
      } else if (s == Status.connected) {
        _connectTimeoutTimer?.cancel();
        _autoReconnectTimer?.cancel();
        _hasConnectedOnce = true;
        error = null;
      }
      notifyListeners();
    });

    try {
      ros2.connect();
    } catch (e) {
      _connectTimeoutTimer?.cancel();
      error = 'Could not connect: $e';
      notifyListeners();
      if (!_userInitiatedDisconnect && robot != null) {
        _scheduleAutoReconnect();
      }
    }
  }

  void _scheduleAutoReconnect({bool immediate = false}) {
    if (_userInitiatedDisconnect || robot == null) return;
    _autoReconnectTimer?.cancel();
    final delay = immediate ? const Duration(milliseconds: 350) : const Duration(seconds: 2);
    _autoReconnectTimer = Timer(delay, () async {
      if (status == Status.connected || _userInitiatedDisconnect || robot == null) return;
      debugPrint('[ConnectionProvider] Auto-reconnecting to ${robot!.name} (${robot!.ip})...');
      await reconnect();
    });
  }

  /// Closes and reopens the connection — same robot, fresh socket. Used by
  /// a "Reconnect" affordance rather than making the caller re-derive the
  /// robot's address itself.
  Future<void> reconnect() async {
    _userInitiatedDisconnect = false;
    _autoReconnectTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    await _ros2?.close();
    await _statusSub?.cancel();
    error = null;
    notifyListeners();
    await _connect();
  }

  /// Updates the robot IP directly and connects immediately.
  Future<void> updateRobotIp(String newIp, {String? name}) async {
    _userInitiatedDisconnect = false;
    _autoReconnectTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    await _ros2?.close();
    await _statusSub?.cancel();
    final updated = SavedRobot(
      name: name ?? robot?.name ?? 'navpromini',
      ip: newIp.trim(),
    );
    await _store.save(updated);
    robot = updated;
    await _connect();
  }

  /// Disconnects and forgets the saved robot — used by Settings' "Run Setup
  /// Again". The caller is responsible for navigating to the setup flow
  /// afterwards; this only clears connection state and persisted storage.
  Future<void> forget() async {
    _userInitiatedDisconnect = true;
    _hasConnectedOnce = false;
    _autoReconnectTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    final ros2 = _ros2;
    _ros2 = null;
    robot = null;
    status = Status.none;
    error = 'No robot configured.';
    await _store.clear();
    await _statusSub?.cancel();
    _statusSub = null;
    if (ros2 != null) {
      try {
        await ros2.close().timeout(const Duration(milliseconds: 300));
      } catch (_) {}
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _autoReconnectTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _statusSub?.cancel();
    _ros2?.close();
    super.dispose();
  }
}
