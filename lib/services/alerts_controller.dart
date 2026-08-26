import 'package:flutter/foundation.dart';

import 'sdk_events_service.dart';

/// Every SDK event received since the app connected to this robot, shared
/// app-wide — mirrors LocationsController's/MapLayersController's own
/// reasoning. The SDK offers no history endpoint (see SdkEventsService's own
/// doc: "an event is emitted once by definition... nothing to page back
/// through"), so a per-screen SdkEventsService instance only ever sees
/// events that happened to arrive while *that* screen was mounted. Reported
/// directly: Dashboard's alerts card — mounted continuously in AppShell's
/// IndexedStack — accumulated an alert the full Alerts screen never showed,
/// because that screen wasn't open yet when the event actually arrived and
/// started its own connection fresh, with its own empty list, the moment it
/// was opened afterward.
///
/// One shared connection + one shared history list, alive for as long as
/// the app is connected to a robot, fixes that: whichever screen mounts
/// first calls [ensureStarted] and every screen — Dashboard's card, the
/// full Alerts log — reads the same accumulated [events].
class AlertsController extends ChangeNotifier {
  AlertsController._();

  static final instance = AlertsController._();

  SdkEventsService? _service;
  String? _forIp;
  final List<SdkEvent> events = [];

  bool get isConnected => _service?.isConnected ?? false;

  void ensureStarted(String robotIp) {
    if (_forIp == robotIp) return;
    _service?.dispose();
    events.clear();
    _forIp = robotIp;
    final service = SdkEventsService(robotIp);
    _service = service;
    service.events.listen((event) {
      events.insert(0, event);
      notifyListeners();
    });
    // Without this, "Live"/"Reconnecting…" indicators built on this
    // controller would only ever refresh incidentally (i.e. when an event
    // happens to arrive), not the instant the socket's own state actually
    // changes.
    service.connectionChanges.listen((_) => notifyListeners());
    service.start();
  }
}
