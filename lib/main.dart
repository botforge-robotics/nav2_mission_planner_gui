import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/screens.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'providers/connection_provider.dart';
import 'providers/ros2_data_provider.dart';
import 'services/launch_service.dart';
import 'services/mission_execution_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FocusManager.instance.primaryFocus?.unfocus();

  // Force landscape mode
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Hide system UI bars
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => LaunchManager()),
        ChangeNotifierProxyProvider<ConnectionProvider, SettingsProvider>(
          create: (context) => SettingsProvider('default'),
          update: (context, connectionProvider, previous) {
            // Update settings provider when active robot changes
            final robotId =
                connectionProvider.activeRobot?.settingsId ?? 'default';
            if (previous?.robotId != robotId) {
              return SettingsProvider(robotId);
            }
            return previous!;
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
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
