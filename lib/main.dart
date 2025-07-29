import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/connection_screen.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'providers/connection_provider.dart';
import 'providers/ros2_data_provider.dart';
import 'providers/license_provider.dart';
import 'providers/branding_provider.dart';
import 'services/launch_service.dart';
import 'services/mission_execution_service.dart';
import 'services/device_service.dart';
import 'services/secure_storage_service.dart';

import 'screens/license/tampering_warning_screen.dart';
import 'screens/license/license_checking_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'models/license_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FocusManager.instance.primaryFocus?.unfocus();

  // Initialize license system services
  await DeviceService.initialize();
  await SecureStorageService.initialize();

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
        ChangeNotifierProvider(create: (_) => BrandingProvider()),
        ChangeNotifierProvider(create: (_) => LicenseProvider()),
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
      home: Consumer2<LicenseProvider, BrandingProvider>(
        builder: (context, licenseProvider, brandingProvider, child) {
          // Set up connection between providers
          WidgetsBinding.instance.addPostFrameCallback((_) {
            licenseProvider.setBrandingProvider(brandingProvider);
            if (licenseProvider.status == LicenseStatus.checking) {
              licenseProvider.checkLicense();
            }
            // Load cached branding on app start
            brandingProvider.loadCachedBranding();
          });

          // Always show connection screen as base
          return Stack(
            children: [
              const ConnectionScreen(),
              // Overlay license screens as dialogs (including checking)
              if (licenseProvider.status != LicenseStatus.valid)
                _buildLicenseOverlay(context, licenseProvider),
            ],
          );
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }

  Widget _buildLicenseOverlay(
      BuildContext context, LicenseProvider licenseProvider) {
    // Determine which license screen to show
    Widget licenseScreen;
    bool isDismissible = false;

    switch (licenseProvider.status) {
      case LicenseStatus.checking:
        licenseScreen = const LicenseCheckingScreen();
        isDismissible = false; // Cannot dismiss while checking
        break;
      case LicenseStatus.trial:
        licenseScreen = const WelcomeScreen();
        isDismissible = false; // Cannot dismiss welcome screen
        break;
      case LicenseStatus.expired:
        licenseScreen = const WelcomeScreen();
        isDismissible = false; // Cannot dismiss welcome screen
        break;
      case LicenseStatus.noInternet:
        licenseScreen = const WelcomeScreen();
        isDismissible = false; // Cannot dismiss no internet screen
        break;
      case LicenseStatus.error:
        if (licenseProvider.errorMessage?.contains('Time tampering detected') ==
            true) {
          licenseScreen = const TamperingWarningScreen();
          isDismissible = false; // Cannot dismiss tampering warning
        } else {
          licenseScreen = const WelcomeScreen();
          isDismissible = false; // Cannot dismiss welcome screen
        }
        break;
      case LicenseStatus.welcome:
        licenseScreen = const WelcomeScreen();
        isDismissible = false; // Cannot dismiss welcome screen
        break;
      default:
        return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Semi-transparent backdrop - makes connection screen barely visible
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.3),
          ),
        ),
        // Dialog content
        Center(
          child: Container(
            padding: const EdgeInsets.all(0),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 600,
                maxHeight: 700,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF9800).withValues(alpha: 0.1),
                    const Color(0xFFFFC107).withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    licenseScreen,
                    // Close button (only if dismissible)
                    if (isDismissible)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: GestureDetector(
                          onTap: () {
                            // Close the dialog
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        )
      ],
    );
  }
}
