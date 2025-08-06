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
import 'services/api_service.dart';

import 'screens/license/tampering_warning_screen.dart';
import 'screens/license/license_checking_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'models/license_model.dart';
import 'widgets/branding_loading_screen.dart';

// Function to handle device registration on first installation
Future<void> _handleDeviceRegistration() async {
  try {
    // Check if device is already registered
    final isRegistered = await SecureStorageService.isDeviceRegistered();

    if (!isRegistered) {
      // Get device registration data
      final deviceData = await DeviceService.getDeviceRegistrationData();

      // Attempt to register device
      final response = await ApiService.registerDevice(deviceData);

      if (response['statusCode'] == 200 &&
          response['body']['success'] == true) {
        // Mark device as registered
        await SecureStorageService.storeDeviceRegistered(true);
      }
      // Don't throw error - app should still work even if registration fails
    }
  } catch (e) {
    // Don't throw error - app should still work even if registration fails
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FocusManager.instance.primaryFocus?.unfocus();

  // Initialize license system services
  await DeviceService.initialize();
  await SecureStorageService.initialize();

  // Handle device registration on first installation
  await _handleDeviceRegistration();

  // Force landscape mode
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Configure system UI for edge-to-edge compatibility
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // Enable edge-to-edge mode
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
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
      home: Consumer2<LicenseProvider, BrandingProvider>(
        builder: (context, licenseProvider, brandingProvider, child) {
          // Set up connection between providers
          WidgetsBinding.instance.addPostFrameCallback((_) {
            licenseProvider.setBrandingProvider(brandingProvider);
            if (licenseProvider.status == LicenseStatus.checking) {
              licenseProvider.checkLicense();
            }
          });

          // Show loading screen until branding is initialized
          if (!brandingProvider.isInitialized) {
            return const BrandingLoadingScreen();
          }

          // Always show connection screen as base
          return Stack(
            children: [
              const ConnectionScreen(),
              // Overlay license screens as dialogs (including checking)
              if (licenseProvider.status != LicenseStatus.valid &&
                  licenseProvider.status != LicenseStatus.trial)
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
            child: Consumer<BrandingProvider>(
              builder: (context, brandingProvider, child) {
                return Container(
                  constraints: const BoxConstraints(
                    maxWidth: 600,
                    maxHeight: 700,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        brandingProvider.themeColor.withValues(alpha: 0.1),
                        brandingProvider.themeColor.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: brandingProvider.themeColor.withValues(alpha: 0.3),
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
                );
              },
            ),
          ),
        )
      ],
    );
  }
}
