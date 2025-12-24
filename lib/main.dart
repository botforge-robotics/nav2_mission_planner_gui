import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'providers/connection_provider.dart' hide ConnectionState;
import 'providers/ros2_data_provider.dart';
import 'services/launch_service.dart';
import 'services/mission_execution_service.dart';
import 'services/device_service.dart';
import 'services/secure_storage_service.dart';
import 'providers/branding_provider.dart';
import 'screens/connection_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FocusManager.instance.primaryFocus?.unfocus();

  // Initialize device service
  await DeviceService.initialize();
  await SecureStorageService.initialize();
  debugPrint('✅ Services initialized in main()');

  // Enable modern edge-to-edge for Android 15+ while allowing system bars
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Keep UX locked to landscape (left or right) on handsets/tablets
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BrandingProvider()),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => LaunchManager()),
        ChangeNotifierProxyProvider<ConnectionProvider, SettingsProvider>(
          create: (context) => SettingsProvider('default'),
          update: (context, connectionProvider, previous) {
            // Update settings provider when active robot changes
            final robotId =
                connectionProvider.activeRobot?.settingsId ?? 'default';

            // Return the existing provider immediately to avoid null errors
            if (previous == null) {
              return SettingsProvider(robotId);
            }

            // Schedule the update to happen after this build cycle
            if (previous.robotId != robotId) {
              Future.microtask(() async {
                await previous.updateRobotId(robotId);
              });
            }

            return previous;
          },
        ),
        ChangeNotifierProxyProvider2<ConnectionProvider, SettingsProvider,
            ROS2DataProvider>(
          create: (context) => ROS2DataProvider(
            Provider.of<ConnectionProvider>(context, listen: false),
            Provider.of<SettingsProvider>(context, listen: false),
          ),
          update: (context, connectionProvider, settingsProvider, previous) {
            // Recreate provider if dependencies changed
            return previous ??
                ROS2DataProvider(connectionProvider, settingsProvider);
          },
        ),
        ChangeNotifierProvider(create: (_) => MissionExecutionService()),
        // ROS2DataProvider already exposes topics/services/actions; thin wrappers removed.
      ],
      child: const Nav2MissionPlanner(),
    ),
  );
}

class Nav2MissionPlanner extends StatelessWidget {
  const Nav2MissionPlanner({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nav2 Mission Planner',
      theme: AppTheme.darkTheme,
      home: const ConnectionScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
