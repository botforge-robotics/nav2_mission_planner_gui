import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/licensing_provider.dart';
import '../../providers/branding_provider.dart';
import '../../services/licensing_service.dart';
import '../../services/purchase_service.dart';
import '../../services/secure_storage_service.dart';
import '../../services/device_service.dart';

class TrialOrPurchaseScreen extends StatefulWidget {
  final LicenseGateState state;
  final String? message;
  final String? linkedDeviceId;
  const TrialOrPurchaseScreen(
      {super.key, required this.state, this.message, this.linkedDeviceId});

  @override
  State<TrialOrPurchaseScreen> createState() => _TrialOrPurchaseScreenState();
}

class _TrialOrPurchaseScreenState extends State<TrialOrPurchaseScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _paymentInProgress = false; // New state for payment overlay
  String? _errorMessage; // Error message to display in UI

  String? _googleAccountId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _busy = widget.state == LicenseGateState.error;

    // Load account information
    _loadAccountInfo();

    // Automatically attempt to restore purchases if in trial expired state
    if (widget.state == LicenseGateState.trialExpired) {
      _attemptAutomaticRestore();
    }
  }

  // Load account information
  Future<void> _loadAccountInfo() async {
    try {
      // Get Google account ID
      final googleId = await SecureStorageService.getGoogleAccountId();
      if (mounted) {
        setState(() {
          _googleAccountId = googleId;
        });
      }
    } catch (e) {
      print('⚠️ Error loading account info: $e');
    }
  }

  // Automatically attempt to restore purchases
  Future<void> _attemptAutomaticRestore() async {
    if (!mounted) return;

    // Show a subtle loading indicator
    setState(() {
      _busy = true;
      _errorMessage = 'Checking for previous purchases...';
    });

    try {
      // Get Google account ID to help with restoration
      final googleId = await SecureStorageService.getGoogleAccountId();
      print('📱 Using Google account ID for automatic restore: $googleId');

      final provider = context.read<LicensingProvider>();
      final restored = await PurchaseService.restorePurchases(
        licensingProvider: provider,
      );

      if (mounted) {
        setState(() {
          _busy = false;
        });

        if (restored) {
          // Successfully restored, clear error message
          setState(() {
            _errorMessage = null;
          });
          print('\u2705 Automatically restored previous purchase');
        } else {
          // No purchases found, update message
          setState(() {
            _errorMessage = null; // Clear the "checking" message
          });
          print('\u2139️ No previous purchases found during automatic restore');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMessage = null; // Don't show error for automatic restore
        });
        print('\u26a0️ Error during automatic restore: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Reset payment state when app becomes active (user returns from payment screen)
    if (state == AppLifecycleState.resumed && _paymentInProgress) {
      setState(() => _paymentInProgress = false);
      PurchaseService.cancelCurrentPurchase();
    }
  }

  Future<void> _startTrial() async {
    if (mounted) {
      setState(() => _busy = true);
    }
    // Capture provider while this State is still mounted to avoid using context later
    final licensingProvider =
        mounted ? context.read<LicensingProvider>() : null;
    try {
      final res = await LicensingService.startTrial();
      if (mounted) {
        setState(() => _busy = false);
      }
      if (res['success'] == true) {
        // Trigger a license refresh without relying on context after potential unmount
        await licensingProvider?.refresh();
        // Do not navigate here; LicensingGate will rebuild based on provider state
      } else {
        if (mounted) {
          final errorMessage =
              res['error']?['message'] ?? 'Failed to start trial';
          _showSnack(errorMessage);
          // Show error in UI
          setState(() {
            _errorMessage = errorMessage;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        final errorMessage = 'Network error: ${e.toString()}';
        _showSnack(errorMessage);
        setState(() {
          _errorMessage = errorMessage;
        });
      }
    }
  }

  Future<void> _transferLicense() async {
    if (mounted) {
      setState(() => _busy = true);
    }
    // Capture provider while this State is still mounted to avoid using context later
    final licensingProvider =
        mounted ? context.read<LicensingProvider>() : null;
    try {
      final deviceId = await DeviceService.getDeviceId();
      final res = await LicensingService.transferLicense(newDeviceId: deviceId);
      if (mounted) {
        setState(() => _busy = false);
      }
      if (res['success'] == true) {
        // Trigger a license refresh without relying on context after potential unmount
        await licensingProvider?.refresh();
        // Do not navigate here; LicensingGate will rebuild based on provider state
      } else {
        if (mounted) {
          final errorMessage =
              res['error']?['message'] ?? 'Failed to transfer license';
          _showSnack(errorMessage);
          // Show error in UI
          setState(() {
            _errorMessage = errorMessage;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        final errorMessage = 'Network error: ${e.toString()}';
        _showSnack(errorMessage);
        setState(() {
          _errorMessage = errorMessage;
        });
      }
    }
  }

  Future<void> _buyNow() async {
    if (!mounted) return;
    setState(() => _busy = true);
    final provider = context.read<LicensingProvider>();
    try {
      await PurchaseService.buyProduct(
        'test13', // Test ID for individual
        licensingProvider: provider,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _buyProduct(String productId) async {
    if (!mounted) return;

    setState(() => _paymentInProgress = true);
    final provider = context.read<LicensingProvider>();

    print('🛒 Starting purchase for product: $productId');
    print('🔍 Current provider state: ${provider.state}');

    try {
      await PurchaseService.buyProduct(
        productId,
        licensingProvider: provider,
      );

      print('✅ Purchase completed successfully');
      print('🔍 Provider state after purchase: ${provider.state}');

      // Check if we need to manually trigger a rebuild
      if (mounted) {
        print('🔄 Manually triggering setState to ensure UI rebuilds');
        setState(() {
          // This will trigger a rebuild and check the provider state
        });
      }
    } catch (e) {
      if (!mounted) return;
      print('❌ Purchase failed with error: $e');

      // Check if this is an "already owned" error
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('already own') ||
          errorMsg.contains('already purchased') ||
          errorMsg.contains('already bought')) {
        setState(() {
          _errorMessage =
              'You already own this product. We\'re trying to restore your purchase...';
        });
        _showSnack('Attempting to restore your previous purchase');

        // Get the Google account ID to help with restoration
        final googleId = await SecureStorageService.getGoogleAccountId();
        print('📱 Using Google account ID for restore: $googleId');

        // Try to restore the purchase
        await _restorePurchases();
      } else {
        setState(() {
          _errorMessage = e.toString();
        });
        _showSnack(e.toString());
      }
    } finally {
      if (!mounted) return;
      setState(() => _paymentInProgress = false);
    }
  }

  Future<void> _restorePurchases() async {
    if (!mounted) return;
    setState(() {
      _paymentInProgress = true;
      _errorMessage = 'Checking for previous purchases...';
    });
    final provider = context.read<LicensingProvider>();

    try {
      // Get Google account ID to help with restoration
      final googleId = await SecureStorageService.getGoogleAccountId();
      print('📱 Using Google account ID for restore: $googleId');

      final restored = await PurchaseService.restorePurchases(
        licensingProvider: provider,
      );

      if (mounted) {
        if (restored) {
          setState(() {
            _errorMessage = null; // Clear error message on success
          });
          _showSnack('Purchase restored successfully!');
        } else {
          setState(() {
            _errorMessage =
                'No previous purchases found for this account. If you purchased with a different account, please sign in with that account.';
          });
          _showSnack('No purchases found to restore.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to restore purchases: ${e.toString()}';
      });
      _showSnack('Failed to restore purchases: ${e.toString()}');
    } finally {
      if (!mounted) return;
      setState(() => _paymentInProgress = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final branding = context.watch<BrandingProvider>();
    final Color brand = branding.themeColor;

    final String titleText = _titleForState(widget.state);
    final String detailText =
        _detailForState(widget.state, widget.linkedDeviceId);

    print('🎨 TrialOrPurchaseScreen.build() - State: ${widget.state}');
    print('📝 Title: $titleText');
    print('📄 Detail: $detailText');

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  brand.withOpacity(0.15),
                  Colors.black.withOpacity(0.6),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: (widget.state == LicenseGateState.noLicense ||
                      widget.state == LicenseGateState.licenseRevoked ||
                      widget.state == LicenseGateState.linkedToOtherDevice)
                  ? _buildFullHeightContent(titleText, detailText, brand)
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          // Top branding header
                          Row(
                            children: [
                              // Left: Branding logo
                              SizedBox(
                                height: 48,
                                width: 140,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: branding.createLogoWidget(height: 48),
                                ),
                              ),
                              // Center: App title and subtitle
                              Expanded(
                                child: Center(
                                  child: Column(
                                    children: [
                                      Text(
                                        'NAV2 Mission Planner',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 0.5),
                                      Text(
                                        branding.tagLine,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Right: Empty space for balance
                              const SizedBox(width: 140),
                            ],
                          ),
                          const SizedBox(height: 40),
                          // Main content
                          // Title and details
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              titleText,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              detailText,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.85),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (widget.message != null &&
                              widget.message!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.redAccent.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _shortMessage(widget.message!),
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          _buildActionsForState(
                              widget.state, brand, titleText, detailText),
                          const SizedBox(height: 22),
                          // Show account information for trial expired
                          if (widget.state == LicenseGateState.trialExpired &&
                              _googleAccountId != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Account Information',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Logged in as: $_googleAccountId',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
          // Full-screen payment loading overlay
          if (_paymentInProgress)
            Container(
              color: Colors.black.withOpacity(0.8),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(brand),
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Processing Payment...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Please complete the payment in the store',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      onPressed: () {
                        PurchaseService.cancelCurrentPurchase();
                        setState(() => _paymentInProgress = false);
                      },
                      child: const Text('Cancel Payment'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _titleForState(LicenseGateState s) {
    switch (s) {
      case LicenseGateState.noLicense:
        return 'Trail Available';
      case LicenseGateState.trialExpired:
        return 'Trial expired';
      case LicenseGateState.linkedToOtherDevice:
        return 'This license is linked to another device';
      case LicenseGateState.licenseRevoked:
        return 'License revoked';
      case LicenseGateState.error:
        return 'We couldn\'t verify your license';
      case LicenseGateState.loading:
      case LicenseGateState.trialActive:
      case LicenseGateState.licenseActive:
        return 'Checking license';
    }
  }

  String _detailForState(LicenseGateState s, String? deviceId) {
    switch (s) {
      case LicenseGateState.noLicense:
        return 'Start a free trial to continue.';
      case LicenseGateState.trialExpired:
        return 'Your trial has ended. Purchase a license to continue using all features.';
      case LicenseGateState.linkedToOtherDevice:
        return 'Your license or trial is linked to another device. You can transfer it to this device.';
      case LicenseGateState.licenseRevoked:
        return 'This license is no longer valid. Contact support if you believe this is a mistake.';
      case LicenseGateState.error:
        return 'Unable to verify your license. Please check your internet connection and try again.';
      case LicenseGateState.loading:
      case LicenseGateState.trialActive:
      case LicenseGateState.licenseActive:
        return '';
    }
  }

  String _shortMessage(String input) {
    final max = 140;
    if (input.length <= max) return input;
    return input.substring(0, max) + '…';
  }

  Widget _buildFullHeightContent(
      String titleText, String detailText, Color brand) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // Top branding header
            Row(
              children: [
                // Left: Branding logo
                SizedBox(
                  height: 48,
                  width: 140,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: context
                        .watch<BrandingProvider>()
                        .createLogoWidget(height: 48),
                  ),
                ),
                // Center: App title and subtitle
                Expanded(
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          'NAV2 Mission Planner',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 0.5),
                        Text(
                          context.watch<BrandingProvider>().tagLine,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 15,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Right: Empty space for balance
                const SizedBox(width: 140),
              ],
            ),
            // Use remaining height for content
            Expanded(
              child: (widget.state == LicenseGateState.licenseRevoked ||
                      widget.state == LicenseGateState.linkedToOtherDevice)
                  ? _buildActionsForState(
                      widget.state, brand, titleText, detailText)
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Redesigned title and details for clear differentiation from app title/subtitle
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 18),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  titleText,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.1,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  detailText,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white.withOpacity(0.82),
                                    fontWeight: FontWeight.w400,
                                    height: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                          // Error message if any
                          if (_errorMessage != null) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.redAccent.withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // Action buttons
                          _buildActionsForState(
                              widget.state, brand, titleText, detailText),
                          const SizedBox(height: 22),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionsForState(LicenseGateState state, Color brand,
      [String? titleText, String? detailText]) {
    switch (state) {
      case LicenseGateState.noLicense:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_busy)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: brand.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Starting Trial...',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              )
            else
              _PrimaryButton(
                label: 'Start 7-day Trial',
                color: brand,
                onPressed: () => _startTrial(),
              ),
          ],
        );
      case LicenseGateState.trialExpired:
        // For trial expired state, we only show Buy Now option (no Start Trial)
        return _buildPlansRow(brand);
      case LicenseGateState.linkedToOtherDevice:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Main warning icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.amber.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.phone_android_rounded,
                  size: 48,
                  color: Colors.amber.shade400,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                titleText ?? 'Transfer License',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Main message
              Text(
                'Transferring will remove access on the existing device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 20),

              // Action button
              if (_busy)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: brand.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.black),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Transferring...',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                )
              else
                _PrimaryButton(
                  label: 'Transfer to This Device',
                  color: brand,
                  onPressed: _transferLicense,
                ),
            ],
          ),
        );
      case LicenseGateState.licenseRevoked:
        return SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Main warning icon and title
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.red.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.gpp_bad_rounded,
                    size: 56,
                    color: Colors.red.shade400,
                  ),
                ),
                const SizedBox(height: 16),

                // Main title
                Text(
                  'License Revoked',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  'This license has been deactivated and is no longer valid.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Support section
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.05),
                        Colors.white.withOpacity(0.02),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Need help? ',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      SelectableText(
                        context.watch<BrandingProvider>().supportEmail,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: brand,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      case LicenseGateState.error:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PrimaryButton(
              label: 'Retry',
              color: brand,
              onPressed: () async {
                await context.read<LicensingProvider>().refresh();
              },
            ),
          ],
        );
      case LicenseGateState.loading:
      case LicenseGateState.trialActive:
      case LicenseGateState.licenseActive:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PrimaryButton(
              label: 'Start 7-day Trial',
              color: brand,
              onPressed: _startTrial,
            ),
            const SizedBox(width: 12),
            _GhostButton(
              label: 'Buy Now',
              color: brand,
              onPressed: _buyNow,
            ),
          ],
        );
    }
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _PrimaryButton(
      {required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _GhostButton(
      {required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.7), width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

Widget _planFeature(String text) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.check, size: 14, color: Colors.white70),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ),
    ],
  );
}

extension on _TrialOrPurchaseScreenState {
  Widget _buildPlansRow(Color brand) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;
        final children = [
          Flexible(
            flex: 1,
            child: _planCard(
              title: 'Individual',
              priceNote: 'One-time purchase',
              color: brand,
              features: const [
                'All features & future updates',
                'Single-device license',
                'Standard support',
              ],
              ctaLabel: 'Buy Individual',
              productId: 'test13',
              onPressed: () => _buyProduct('test13'),
            ),
          ),
          const SizedBox(width: 12, height: 12),
          Flexible(
            flex: 1,
            child: _planCard(
              title: 'Enterprise',
              priceNote: 'One-time purchase',
              color: brand,
              features: const [
                'All features in Individual license',
                'Custom branding (logos, app title, about, support, website, email, colors)',
                'Priority support',
              ],
              ctaLabel: 'Buy Enterprise',
              productId: 'test23',
              onPressed: () => _buyProduct('test23'),
            ),
          ),
        ];
        return isNarrow
            ? Column(mainAxisSize: MainAxisSize.min, children: children)
            : Row(children: children);
      },
    );
  }

  Widget _planCard({
    required String title,
    required String priceNote,
    required Color color,
    required List<String> features,
    required String ctaLabel,
    required String productId,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            priceNote,
            style:
                TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _planFeature(f),
              )),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FutureBuilder<String?>(
              future: PurchaseService.getPriceString(productId),
              builder: (context, snapshot) {
                final price = snapshot.data;
                final buttonText =
                    price != null ? '$ctaLabel - $price' : ctaLabel;
                return OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withOpacity(0.7), width: 1.2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: onPressed,
                  child: Text(
                    buttonText,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
