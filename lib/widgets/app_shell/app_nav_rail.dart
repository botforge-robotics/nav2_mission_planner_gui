import 'package:flutter/material.dart';
import '../../constants/modes.dart';
import '../../theme/app_breakpoints.dart';
import '../../services/alert_log_service.dart';

/// Persistent navigation surface for the app shell, replacing the dropdown
/// menu previously buried inside the top bar (`TopStatusModeSelector`,
/// retired). A `NavigationRail` rather than a bottom nav bar: native builds
/// are landscape-locked end to end (see `main.dart`'s
/// `SystemChrome.setPreferredOrientations`) — a bottom bar eats vertical
/// height, the scarce dimension there, whereas a rail spends width, which
/// landscape has more of.
///
/// Destinations mirror `AppModes` today (Home/Mapping/Navigation/Status/
/// Dock/Settings — teleop stays folded into mapping, matching existing
/// behavior in `home_screen.dart`). New destinations (Alerts, Tools) are
/// added here as their screens are built in later phases, not stubbed
/// ahead of time.
class AppNavRail extends StatelessWidget {
  final AppModes currentMode;

  /// Called when the user taps a destination. The caller (`HomeScreen`)
  /// owns the session-active guard (blocking/confirming a switch away from
  /// an in-progress mapping/navigation session) — this widget is purely
  /// presentational and always reports the raw tap.
  final ValueChanged<AppModes> onDestinationTapped;

  const AppNavRail({
    super.key,
    required this.currentMode,
    required this.onDestinationTapped,
  });

  static const List<(AppModes, IconData, IconData, String)> _destinations = [
    (AppModes.dashboard, Icons.dashboard_outlined, Icons.dashboard, 'Home'),
    (AppModes.mapping, Icons.map_outlined, Icons.map, 'Maps'),
    (AppModes.navigation, Icons.route_outlined, Icons.route, 'Navigate'),
    (
      AppModes.robotStatus,
      Icons.monitor_heart_outlined,
      Icons.monitor_heart,
      'Status'
    ),
    (AppModes.dock, Icons.ev_station_outlined, Icons.ev_station, 'Dock'),
    (
      AppModes.alerts,
      Icons.notifications_outlined,
      Icons.notifications,
      'Alerts'
    ),
    (AppModes.tools, Icons.terminal_outlined, Icons.terminal, 'Tools'),
    (AppModes.settings, Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final sizeClass = WindowSizeClass.of(context);
    final labelType = sizeClass.isExpandedOrWider
        ? NavigationRailLabelType.all
        : NavigationRailLabelType.none;

    // currentMode can be `teleop` transiently (see home_screen.dart's
    // teleop-redirect handling) or `settings` while a previous mode is
    // remembered — resolve to the nearest real destination rather than
    // showing nothing selected.
    var selectedIndex = _destinations.indexWhere((d) => d.$1 == currentMode);
    if (selectedIndex < 0) selectedIndex = 0;

    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) => onDestinationTapped(_destinations[i].$1),
      labelType: labelType,
      destinations: [
        for (final d in _destinations)
          NavigationRailDestination(
            icon: d.$1 == AppModes.alerts
                ? _AlertsIcon(icon: d.$2)
                : Icon(d.$2),
            selectedIcon: d.$1 == AppModes.alerts
                ? _AlertsIcon(icon: d.$3)
                : Icon(d.$3),
            label: Text(d.$4),
          ),
      ],
    );
  }
}

/// Alerts destination icon with a live count badge — listens to
/// [AlertLogService] directly (same singleton-`Listenable` pattern as
/// `DockingService` elsewhere) so the rail reflects new alerts without the
/// whole shell needing to rebuild.
class _AlertsIcon extends StatelessWidget {
  final IconData icon;

  const _AlertsIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AlertLogService.instance,
      builder: (context, _) {
        final errorCount = AlertLogService.instance.events
            .where((e) => e.severity == AlertSeverity.error)
            .length;
        if (errorCount == 0) return Icon(icon);
        return Badge(
          label: Text(errorCount > 9 ? '9+' : '$errorCount'),
          child: Icon(icon),
        );
      },
    );
  }
}
