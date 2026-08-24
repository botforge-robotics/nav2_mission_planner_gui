import 'dart:async';
// `ConnectionState` here is the app's connection-lifecycle enum
// (`connection_provider.dart`), not Flutter's async-snapshot one — same
// hide/show split `main.dart` uses for the same reason.
import 'package:flutter/material.dart' hide ConnectionState;
import '../providers/connection_provider.dart'
    show ConnectionProvider, ConnectionState;
import 'docking_service.dart';
import 'mission_execution_service.dart';

/// How serious an [AlertEvent] is — drives the icon/color used to render it
/// in [AlertLogService] consumers (the Alerts & Log screen, Dashboard's
/// banner).
enum AlertSeverity { info, warning, error }

class AlertEvent {
  final DateTime time;
  final String title;
  final String? detail;
  final AlertSeverity severity;
  final IconData icon;

  AlertEvent({
    required this.title,
    this.detail,
    required this.severity,
    required this.icon,
    DateTime? time,
  }) : time = time ?? DateTime.now();
}

/// App-wide event log — deliberately scoped to what the app can actually
/// observe (connection drops/restores, mission failures, dock/undock
/// faults). Per the redesign plan's §7/§12: this is NOT a general
/// fault/diagnostics feed — no E-STOP, obstacle-detection, or hardware
/// fault topic is subscribed anywhere in the app, so none of those can
/// appear here. Wiring those in is a ROS-integration task, not a UI one,
/// and needs the actual topic names for this robot stack first.
///
/// Singleton + `ChangeNotifier`, same pattern as [DockingService] — reached
/// directly via `.instance` rather than through `Provider`, since it has no
/// per-robot-connection lifecycle of its own (it outlives any single
/// connection so a reconnect's "Connection lost" entry from moments ago
/// stays in the log).
class AlertLogService extends ChangeNotifier {
  static AlertLogService? _instance;
  static AlertLogService get instance => _instance ??= AlertLogService._();
  AlertLogService._();

  static const int _maxEvents = 200;
  final List<AlertEvent> _events = [];
  List<AlertEvent> get events => List.unmodifiable(_events);

  bool _observing = false;
  MissionExecutionService? _mission;
  StreamSubscription<ConnectionState>? _connSub;
  String? _lastMissionError;
  String _lastDockStatus = 'undocked';
  bool _hadConnectedOnce = false;

  /// Starts watching the real signal sources. Safe to call on every
  /// `AppShell`/`HomeScreen` build — idempotent, only wires listeners once.
  void observe({
    required ConnectionProvider connection,
    required MissionExecutionService mission,
  }) {
    if (_observing) return;
    _observing = true;
    _mission = mission;
    _lastMissionError = mission.errorMessage;
    _lastDockStatus = DockingService.instance.status;
    _hadConnectedOnce = connection.isConnected;

    _connSub = connection.connectionStream.listen(_onConnectionState);
    mission.addListener(_onMissionChanged);
    DockingService.instance.addListener(_onDockChanged);
  }

  void _onConnectionState(ConnectionState state) {
    if (state == ConnectionState.connected) {
      if (_hadConnectedOnce) {
        _add(AlertEvent(
          title: 'Reconnected',
          severity: AlertSeverity.info,
          icon: Icons.wifi,
        ));
      }
      _hadConnectedOnce = true;
    } else if (state == ConnectionState.disconnected && _hadConnectedOnce) {
      _add(AlertEvent(
        title: 'Connection lost',
        severity: AlertSeverity.error,
        icon: Icons.wifi_off,
      ));
    }
  }

  void _onMissionChanged() {
    final err = _mission?.errorMessage;
    if (err != null && err != _lastMissionError) {
      _add(AlertEvent(
        title: 'Mission failed',
        detail: err,
        severity: AlertSeverity.error,
        icon: Icons.error_outline,
      ));
    }
    _lastMissionError = err;
  }

  void _onDockChanged() {
    final status = DockingService.instance.status;
    if (status != _lastDockStatus) {
      if (status == 'error') {
        _add(AlertEvent(
          title: 'Dock error',
          detail: 'Dock/undock action failed — safe to retry',
          severity: AlertSeverity.error,
          icon: Icons.ev_station,
        ));
      }
      _lastDockStatus = status;
    }
  }

  void _add(AlertEvent e) {
    _events.insert(0, e);
    if (_events.length > _maxEvents) _events.removeLast();
    notifyListeners();
  }

  /// Clears the log. Local-only (nothing server-side to reconcile) — same
  /// scope as the rest of this service.
  void clear() {
    if (_events.isEmpty) return;
    _events.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _mission?.removeListener(_onMissionChanged);
    DockingService.instance.removeListener(_onDockChanged);
    super.dispose();
  }
}
