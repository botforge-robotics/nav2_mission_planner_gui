import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/screens.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'providers/connection_provider.dart';
import 'providers/ros2_data_provider.dart';
import 'services/launch_service.dart';
import 'services/topic_service.dart';
import 'services/service_action_service.dart';

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
        ChangeNotifierProxyProvider<ConnectionProvider, ROS2DataProvider>(
          create: (context) => ROS2DataProvider(
            Provider.of<ConnectionProvider>(context, listen: false),
          ),
          update: (context, connectionProvider, previous) {
            // If previous provider exists, return it since it already has the connection provider
            return previous ?? ROS2DataProvider(connectionProvider);
          },
        ),
        // Provide the service classes that use the centralized ROS2DataProvider
        ProxyProvider2<ConnectionProvider, ROS2DataProvider, TopicService>(
          update: (context, connectionProvider, ros2DataProvider, previous) {
            return TopicService(connectionProvider, ros2DataProvider);
          },
        ),
        ProxyProvider2<ConnectionProvider, ROS2DataProvider,
            ServiceActionService>(
          update: (context, connectionProvider, ros2DataProvider, previous) {
            return ServiceActionService(connectionProvider, ros2DataProvider);
          },
        ),
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
