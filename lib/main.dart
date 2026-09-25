import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/connection_provider.dart';
import 'providers/robot_telemetry_provider.dart';
import 'providers/setup_flow_controller.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
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
        // Provides RobotTelemetryProvider globally across the entire app and all routes
        // (including Navigator.push targets) without rebuilding/tearing down the provider
        // element when the connection status changes.
        ChangeNotifierProxyProvider<ConnectionProvider, RobotTelemetryProvider>(
          create: (_) => RobotTelemetryProvider(null),
          update: (_, connection, telemetry) {
            final ros2 = connection.isConnected ? connection.ros2 : null;
            return (telemetry ?? RobotTelemetryProvider(null))..updateRos2(ros2);
          },
        ),
      ],
      child: MaterialApp(
        title: 'NavPro Mini',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const SplashScreen(),
      ),
    );
  }
}
