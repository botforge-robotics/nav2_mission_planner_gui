import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/connection_provider.dart';
import 'providers/robot_telemetry_provider.dart';
import 'providers/setup_flow_controller.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const NavProMiniApp());
}

class NavProMiniApp extends StatelessWidget {
  const NavProMiniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SetupFlowController()),
        // Lazy (Provider's default): not constructed — no connection
        // opened — until something actually reads it, so the setup flow
        // never pays for a connection it doesn't use. First real reader is
        // DashboardScreen.
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
      ],
      child: MaterialApp(
        title: 'NavPro Mini',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const SplashScreen(),
        // Wraps the Navigator itself (via `child`), not just AppShell's own
        // returned subtree — RobotTelemetryProvider used to be provided
        // inside AppShell.build(), which only covers AppShell's own
        // IndexedStack tabs. Any screen reached via Navigator.push (Map
        // View, Create Map, ...) is a *sibling* OverlayEntry to AppShell's
        // route, not a descendant of it, so it could never see a provider
        // scoped that way — a real "Provider<RobotTelemetryProvider> not
        // found" crash the moment such a screen tried to read it. Building
        // it here instead, above the Navigator, makes it visible to every
        // route, pushed or not.
        builder: (context, child) {
          final connection = context.watch<ConnectionProvider>();
          if (!connection.isConnected) return child!;
          return ChangeNotifierProvider<RobotTelemetryProvider>(
            key: ValueKey(connection.ros2),
            create: (_) => RobotTelemetryProvider(connection.ros2!),
            child: child!,
          );
        },
      ),
    );
  }
}
