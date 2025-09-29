import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/licensing_provider.dart';
import '../../providers/branding_provider.dart';
import '../connection_screen.dart';
import 'trial_or_purchase_screen.dart';
import '../../services/device_service.dart';
import '../../services/app_usage_tracker.dart';
import '../../services/migration_service.dart';

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

  /// Flag indicating whether this is the first app launch
  bool _isFirstAppLaunch = false;

  /// Flag indicating whether user has ever reached teleop screen
  bool _hasEverReachedTeleop = false;

  /// Flag indicating whether to show trial reset popup
  bool _shouldShowTrialResetPopup = false;

  /// Flag indicating whether migration check is in progress
  bool _isCheckingMigration = false;

  /// Flag indicating whether trial reset is in progress
  bool _isResettingTrial = false;

  /// Flag indicating whether user just completed trial reset
  bool _justCompletedTrialReset = false;

  @override
  void initState() {
    super.initState();
    // Initialize the new flow logic asynchronously
    Future.microtask(() async {
      debugPrint('🔍 Starting LicensingGate initialization');

      _isFirstAppLaunch = await AppUsageTracker.isFirstAppLaunch();
      debugPrint('🔍 _isFirstAppLaunch: $_isFirstAppLaunch');

      _hasEverReachedTeleop = await AppUsageTracker.hasEverReachedTeleop();
      debugPrint('🔍 _hasEverReachedTeleop: $_hasEverReachedTeleop');

      // Check migration status to determine if popup should be shown
      if (!_isCheckingMigration) {
        _isCheckingMigration = true;
        _shouldShowTrialResetPopup =
            await MigrationService.checkMigrationStatus();
        debugPrint(
            '🔍 Migration check result: _shouldShowTrialResetPopup=$_shouldShowTrialResetPopup');
        _isCheckingMigration = false;
      }

      final provider = context.read<LicensingProvider>();

      // Only initialize license check if user has reached teleop before
      // This implements the new flow: skip license check on first launch
      if (_hasEverReachedTeleop) {
        debugPrint('🔍 Initializing license provider');
        await provider.initialize();
      } else {
        debugPrint(
            '🔍 Skipping license provider initialization (first launch or never reached teleop)');
      }

      debugPrint('🔍 Setting _didInitialCheck = true');
      _didInitialCheck = true;

      if (mounted) {
        setState(() {
          // Trigger rebuild with final state
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<LicensingProvider, BrandingProvider>(
      builder: (context, lp, brandingProvider, _) {
        debugPrint(
            '🔍 Build called: _didInitialCheck=$_didInitialCheck, _shouldShowTrialResetPopup=$_shouldShowTrialResetPopup, _isFirstAppLaunch=$_isFirstAppLaunch, _hasEverReachedTeleop=$_hasEverReachedTeleop');

        // Show loading while initializing
        if (!_didInitialCheck) {
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

        // NEW FLOW: Show trial reset popup if needed
        if (_shouldShowTrialResetPopup) {
          debugPrint('🔍 Showing trial reset popup');
          return _buildTrialResetPopup(context);
        }

        // NEW FLOW: Direct to connection screen on first app launch, if never reached teleop, or if just completed trial reset
        if (_isFirstAppLaunch ||
            !_hasEverReachedTeleop ||
            _justCompletedTrialReset) {
          debugPrint(
              '🔍 Going to connection screen: _isFirstAppLaunch=$_isFirstAppLaunch, _hasEverReachedTeleop=$_hasEverReachedTeleop, _justCompletedTrialReset=$_justCompletedTrialReset');
          return const ConnectionScreen();
        }

        // Handle error state (only for users who have reached teleop before)
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

        // Handle different license states (only for users who have reached teleop before)
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

  /// Builds the trial reset popup shown after migration
  ///
  /// This popup informs users that their trial has been reset and explains
  /// the new flow where trial starts after robot connection.
  Widget _buildTrialResetPopup(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[700]!, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                size: 64,
                color: context.read<BrandingProvider>().themeColor,
              ),
              const SizedBox(height: 16),
              Text(
                'Trial Reset',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Your trial has been reset. You will get a fresh 14-day trial after successfully connecting to a robot for the first time.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[300],
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isResettingTrial
                      ? null
                      : () async {
                          if (mounted) {
                            setState(() {
                              _isResettingTrial = true;
                            });
                          }

                          try {
                            debugPrint('🔄 Starting trial reset process...');
                            // Mark popup as shown in cloud and locally
                            await MigrationService.markMigrationPopupShown();
                            debugPrint('✅ Trial reset completed successfully');

                            // Reset teleop flag so user can experience new flow
                            debugPrint(
                                '🔄 Resetting teleop flag for new flow...');
                            await AppUsageTracker.resetAllTracking();
                            debugPrint(
                                '✅ Teleop flag reset - user can experience new flow');

                            // Refresh license provider to get updated status
                            debugPrint(
                                '🔄 Refreshing license provider after trial reset...');
                            final provider = context.read<LicensingProvider>();
                            await provider.refresh();
                            debugPrint('✅ License provider refreshed');

                            if (mounted) {
                              setState(() {
                                _shouldShowTrialResetPopup = false;
                                _isResettingTrial = false;
                                _justCompletedTrialReset = true;
                                _hasEverReachedTeleop =
                                    false; // Reset for new flow
                              });
                            }
                          } catch (e) {
                            debugPrint('❌ Error during trial reset: $e');
                            if (mounted) {
                              setState(() {
                                _isResettingTrial = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isResettingTrial
                        ? Colors.grey[600]
                        : context.read<BrandingProvider>().themeColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isResettingTrial
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Resetting...',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'OK',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
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
