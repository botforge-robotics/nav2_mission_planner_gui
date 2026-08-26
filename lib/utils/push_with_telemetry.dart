import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/robot_telemetry_provider.dart';

/// Pushes [screen] carrying along the shell's existing RobotTelemetryProvider
/// instance. Needed because Navigator.push inserts the new route as a
/// sibling of the *whole* current route in the widget tree, not a descendant
/// of AppShell's ChangeNotifierProvider — so a plain push leaves screens
/// like RobotStatusScreen/DockChargeScreen unable to find that provider.
/// `.value(...)` reuses the live instance (not a fresh one), so the pushed
/// screen keeps receiving the same real-time updates. Shared by every screen
/// that opens one of those two detail screens (Dashboard, Settings' robot
/// summary card) rather than each duplicating the same six lines.
void pushWithTelemetry(BuildContext context, Widget screen) {
  final telemetry = context.read<RobotTelemetryProvider>();
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) =>
        ChangeNotifierProvider.value(value: telemetry, child: screen),
  ));
}
