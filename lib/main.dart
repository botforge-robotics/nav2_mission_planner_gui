import 'services/sdk_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/connection_provider.dart';
import 'providers/fleet_provider.dart';
import 'providers/robot_telemetry_provider.dart';
import 'providers/setup_flow_controller.dart';
import 'services/gamepad_service.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GamepadService.instance.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
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
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => FleetProvider()),
        ChangeNotifierProxyProvider<ConnectionProvider, RobotTelemetryProvider>(
          create: (_) => RobotTelemetryProvider(null),
          update: (_, connection, telemetry) {
            final ros2 = connection.isConnected ? connection.ros2 : null;
            final robot = connection.robot;
            final sdkApi = robot != null ? SdkApiService(robot.ip, port: 8090) : null;
            GamepadService.instance.updateConnection(
              ros2: ros2,
              sdkApi: sdkApi,
            );
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
