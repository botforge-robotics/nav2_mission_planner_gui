import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/licensing_provider.dart';
import '../../providers/branding_provider.dart';
import '../connection_screen.dart';
import 'trial_or_purchase_screen.dart';
import '../../services/device_service.dart';

/// A gate component that controls access to the main application based on license status.
///
/// The LicensingGate acts as a router that determines which screen to show based on
/// the user's current license state. It handles:
/// - Initial license status checking
/// - Routing users to appropriate screens based on their license
/// - Managing the transition between different license states
/// - Handling device linking and license transfer scenarios
///
/// The gate ensures that only users with valid licenses or active trials can access
/// the main application features, while providing appropriate UI for users without
/// licenses or with expired trials.
class LicensingGate extends StatefulWidget {
  const LicensingGate({super.key});

  @override
  State<LicensingGate> createState() => _LicensingGateState();
}

/// State class for the LicensingGate widget.
///
/// This class manages the initialization of the licensing provider and handles
/// the routing logic based on license status. It ensures that the license
/// status is checked before rendering any UI components.
class _LicensingGateState extends State<LicensingGate> {
  /// Flag indicating whether the initial license check has been completed.
  ///
  /// This prevents the UI from showing before the license status is determined,
  /// ensuring a smooth user experience without flickering between states.
  bool _didInitialCheck = false;

  @override
  void initState() {
    super.initState();
    // Initialize the licensing provider asynchronously
    Future.microtask(() async {
      final provider = context.read<LicensingProvider>();
      await provider.initialize();
      _didInitialCheck = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<LicensingProvider, BrandingProvider>(
      builder: (context, lp, brandingProvider, _) {
        // Show loading while initializing
        if (!_didInitialCheck || lp.state == LicenseGateState.loading) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Checking license status...'),
                ],
              ),
            ),
          );
        }

        // Handle error state
        if (lp.state == LicenseGateState.error) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${lp.statusMessage ?? "Unknown error"}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Colors.redAccent, // Button background color
                      foregroundColor: Colors.white, // Text/icon color
                    ),
                    onPressed: () => lp.refresh(),
                    child: const Text(
                      'Retry',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Handle different license states
        switch (lp.state) {
          case LicenseGateState.noLicense:
          case LicenseGateState.trialExpired:
          case LicenseGateState.paymentPending:
            return TrialOrPurchaseScreen(
              state: lp.state,
              message: lp.statusMessage,
              linkedDeviceId: lp.linkedDeviceId,
            );
          case LicenseGateState.trialActive:
          case LicenseGateState.licenseActive:
            // Show connection screen for active license/trial
            return const ConnectionScreen();
          case LicenseGateState.linkedToOtherDevice:
            return _buildLinkedToOtherDeviceScreen(lp);
          case LicenseGateState.licenseRevoked:
            return _buildLicenseRevokedScreen(lp);
          default:
            return TrialOrPurchaseScreen(
              state: lp.state,
              message: lp.statusMessage,
              linkedDeviceId: lp.linkedDeviceId,
            );
        }
      },
    );
  }

  /// Builds the screen shown when a license is linked to another device.
  ///
  /// This screen allows users to transfer their license to the current device
  /// or refresh their license status. It's shown when the backend detects
  /// that the user's license is currently active on a different device.
  ///
  /// Parameters:
  /// - `lp`: The licensing provider containing current license state
  ///
  /// Returns a Scaffold widget with transfer options and status information.
  Widget _buildLinkedToOtherDeviceScreen(LicensingProvider lp) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('License on Other Device'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.devices_other, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'License Linked to Another Device',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This license is currently active on another device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.read<BrandingProvider>().themeColor,
              ),
              onPressed: () async {
                final deviceId = await DeviceService.getDeviceId();
                await lp.transferLicense(deviceId);
              },
              child: const Text('Transfer to This Device'),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the screen shown when a license has been revoked.
  ///
  /// This screen informs users that their license has been revoked and
  /// provides options to check their current status. It's shown when
  /// the backend determines that the user's license is no longer valid
  /// due to policy violations or other administrative actions.
  ///
  /// Parameters:
  /// - `lp`: The licensing provider containing current license state
  ///
  /// Returns a Scaffold widget with revocation information and status check options.
  Widget _buildLicenseRevokedScreen(LicensingProvider lp) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('License Revoked'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'License Revoked',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Your license has been revoked. Please contact support.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ...(() {
              final supportEmail =
                  context.read<BrandingProvider>().supportEmail;
              if (supportEmail.isNotEmpty) {
                return [
                  Text(
                    'Support: $supportEmail',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ];
              }
              return <Widget>[];
            })(),
          ],
        ),
      ),
    );
  }
}
