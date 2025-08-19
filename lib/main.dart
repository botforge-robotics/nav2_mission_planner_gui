import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/licensing/licensing_gate.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'providers/connection_provider.dart' hide ConnectionState;
import 'providers/ros2_data_provider.dart';
import 'providers/branding_provider.dart';
import 'providers/licensing_provider.dart';
import 'services/launch_service.dart';
import 'services/mission_execution_service.dart';
import 'services/device_service.dart';
import 'services/secure_storage_service.dart';
import 'services/firebase_service.dart';
import 'widgets/branding_loading_screen.dart';
import 'screens/auth/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FocusManager.instance.primaryFocus?.unfocus();

  // Initialize Firebase
  await FirebaseService.initialize();
  debugPrint('🚀 Firebase initialized in main()');

  // Initialize device service
  await DeviceService.initialize();
  await SecureStorageService.initialize();
  debugPrint('✅ Services initialized in main()');

  // Force landscape mode
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Configure system UI and hide Android status/navigation bars for full-screen UX
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BrandingProvider()),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => LicensingProvider()),
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
      home: Consumer<BrandingProvider>(
        builder: (context, brandingProvider, child) {
          // Show loading screen until branding is initialized
          if (!brandingProvider.isInitialized) {
            return const BrandingLoadingScreen();
          }

          // Use StreamBuilder to listen to authentication state changes
          return StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, AsyncSnapshot<User?> snapshot) {
              // Show loading while checking auth state
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              // Check if user is authenticated
              final user = snapshot.data;
              if (user == null) {
                // User not authenticated - show login screen
                return const LoginScreen();
              }

              // User is authenticated - route through licensing gate
              return const LicensingGate();
            },
          );
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
