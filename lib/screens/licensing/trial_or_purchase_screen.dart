import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../providers/licensing_provider.dart';
import '../../providers/branding_provider.dart';
import '../../services/licensing_service.dart';
import '../../services/purchase_service.dart';
import '../../services/secure_storage_service.dart';
import '../../services/device_service.dart';
import '../../widgets/background_feature_cards.dart';

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
  bool _showMainScreen = true; // Whether to show main screen or payment status
  // Removed verification loading state - now only checking payment status
  String? _errorMessage; // Error message to display
  Map<String, dynamic>? _latestPayment; // Latest payment data from server
  // Add timer for automatic payment status checking
  Timer? _paymentStatusTimer;
  String? _googleAccountId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _busy = widget.state == LicenseGateState.error;

    // Initialize purchase listener early as recommended by in_app_purchase documentation
    // We'll get the provider from context when needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = context.read<LicensingProvider>();
        PurchaseService.initializePurchaseListener(provider);

        // Add listener for purchase state changes
        PurchaseService.addStateChangeListener(() {
          if (mounted) {
            setState(() {
              // Trigger rebuild when purchase state changes
            });
          }
        });

        // Add listener for licensing provider state changes
        provider.addListener(() {
          if (mounted) {
            if (provider.state == LicenseGateState.paymentPending) {
              debugPrint('⏳ Provider state changed to paymentPending');
              setState(() {
                _paymentInProgress = false; // Don't show overlay automatically
                _showMainScreen = false; // Show payment status screen
              });
              // Start automatic payment status checking every 15 seconds
              _startAutomaticPaymentStatusChecking();
            } else if (_paymentInProgress &&
                provider.state != LicenseGateState.paymentPending) {
              debugPrint(
                  '🔄 Provider state changed from paymentPending to: ${provider.state}');
              setState(() {
                _paymentInProgress = false;
                _showMainScreen = true;
              });
              // Stop automatic payment status checking since payment is no longer pending
              _stopAutomaticPaymentStatusChecking();
            }
          }
        });

        // Start timer to refresh UI for payment status updates
        // _paymentStatusTimer =
        //     Timer.periodic(const Duration(seconds: 2), (timer) {
        //   if (mounted && _shouldShowPaymentStatus()) {
        //     setState(() {
        //       // Trigger rebuild to show updated payment status
        //     });
        //   }
        // });
      }
    });

    // Load account information
    _loadAccountInfo();

    // Check if there's already a pending payment
    _checkExistingPaymentStatus();

    // No automatic restore on init to prevent race conditions
    // Let the user manually trigger restore if needed
  }

  /// Starts automatic payment status checking every 15 seconds
  void _startAutomaticPaymentStatusChecking() {
    debugPrint('⏰ Starting automatic payment status checking every 15 seconds');
    debugPrint('⏰ Current _paymentStatusTimer: $_paymentStatusTimer');
    _stopAutomaticPaymentStatusChecking(); // Stop any existing timer first

    _paymentStatusTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        debugPrint(
            '⏰ Timer triggered - calling _checkPaymentStatusAutomatically');
        _checkPaymentStatusAutomatically();
      } else {
        debugPrint('⏰ Widget not mounted, stopping timer');
        timer.cancel();
      }
    });
    debugPrint('⏰ New _paymentStatusTimer created: $_paymentStatusTimer');
  }

  /// Stops automatic payment status checking
  void _stopAutomaticPaymentStatusChecking() {
    if (_paymentStatusTimer != null) {
      debugPrint('⏰ Stopping automatic payment status checking');
      debugPrint('⏰ Timer was: $_paymentStatusTimer');
      _paymentStatusTimer!.cancel();
      _paymentStatusTimer = null;
      debugPrint('⏰ Timer stopped and set to null');
    } else {
      debugPrint('⏰ No timer to stop - _paymentStatusTimer is null');
    }
  }

  /// Automatically checks payment status without user interaction
  Future<void> _checkPaymentStatusAutomatically() async {
    try {
      debugPrint('🔄 Background payment status check started');
      final result = await LicensingService.checkPaymentStatus();
      debugPrint('🔄 Background check result: ${result['success']}');

      if (result['success'] == true) {
        final paymentStatus = LicensingService.getPaymentStatus(result);
        final latestPayment = LicensingService.getLatestPayment(result);

        debugPrint('🔄 Background check - Payment status: $paymentStatus');
        debugPrint('🔄 Background check - Latest payment: $latestPayment');
        debugPrint('🔄 Current _latestPayment: $_latestPayment');

        // Only update UI if there's an actual change in payment status
        if (mounted && _latestPayment != null) {
          final currentStatus = _latestPayment!['status'];
          debugPrint(
              '🔄 Comparing status: current=$currentStatus, new=$paymentStatus');

          if (currentStatus != paymentStatus) {
            debugPrint(
                '🔄 Payment status changed: $currentStatus → $paymentStatus');

            setState(() {
              _latestPayment = latestPayment;
            });
            debugPrint('🔄 Updated _latestPayment to: $_latestPayment');

            // If payment is no longer pending, stop automatic checking
            if (paymentStatus != 'pending') {
              debugPrint(
                  '✅ Payment completed (status: $paymentStatus), stopping automatic checks');
              _stopAutomaticPaymentStatusChecking();

              // Refresh the licensing provider to update the overall state
              final provider = context.read<LicensingProvider>();
              provider.refresh();
              debugPrint('🔄 Refreshed licensing provider');
            }
          } else {
            debugPrint(
                '⏳ Payment status unchanged: $paymentStatus - continuing checks');
          }
        } else if (mounted && _latestPayment == null && latestPayment != null) {
          // First time getting payment data
          debugPrint('🔄 First time getting payment data: $latestPayment');
          setState(() {
            _latestPayment = latestPayment;
          });
          debugPrint('🔄 Set _latestPayment for first time: $_latestPayment');
        } else {
          debugPrint(
              '🔄 No UI update needed - _latestPayment: $_latestPayment, latestPayment: $latestPayment');
        }

        // Note: Timer is only stopped when payment status changes to non-pending
        // This happens in the status change check above
      } else {
        debugPrint('⚠️ Background check failed: ${result['error']}');
      }
    } catch (e) {
      // Silent error handling - don't show debug messages for background checks
      // Only log critical errors
      if (e.toString().contains('network') ||
          e.toString().contains('timeout')) {
        debugPrint('⚠️ Network error in background payment check: $e');
      }
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
      debugPrint('⚠️ Error loading account info: $e');
    }
  }

  // Check if there's already a pending payment
  Future<void> _checkExistingPaymentStatus() async {
    try {
      debugPrint('🔍 _checkExistingPaymentStatus called');

      // Check if the widget state indicates payment pending
      if (widget.state == LicenseGateState.paymentPending) {
        setState(() {
          _paymentInProgress = false; // Don't show overlay automatically
          _showMainScreen = true; // Show main screen with loading spinner
        });
        // Start automatic payment status checking every 15 seconds
        _startAutomaticPaymentStatusChecking();
        return;
      }

      final currentStatus = PurchaseService.getCurrentPaymentStatus();
      debugPrint('📱 Local payment status: $currentStatus');

      if (currentStatus == 'pending') {
        debugPrint('⚠️ Found existing pending payment on screen load');
        setState(() {
          _showMainScreen = false; // Show payment status screen
        });
        // Start automatic payment status checking for local pending payment
        _startAutomaticPaymentStatusChecking();
      } else {
        // Also check with the server for any payments
        try {
          final result = await LicensingService.checkPaymentStatus();
          debugPrint('📡 Server response: $result');

          if (result['success'] == true) {
            final paymentStatus = LicensingService.getPaymentStatus(result);
            final latestPayment = LicensingService.getLatestPayment(result);

            debugPrint('📊 Payment status from server: $paymentStatus');
            debugPrint('📊 Latest payment data: $latestPayment');

            if (LicensingService.isPaymentPending(result)) {
              debugPrint('⏳ Found pending payment on server');
              setState(() {
                _showMainScreen = false; // Show payment status screen
                _latestPayment = latestPayment;
              });
              // Start automatic payment status checking for existing pending payment
              _startAutomaticPaymentStatusChecking();
            } else if (LicensingService.isPaymentCancelled(result)) {
              debugPrint('❌ Last payment was cancelled');
              // Show trial screen with cancellation info
              setState(() {
                _showMainScreen = true;
                _errorMessage =
                    'Your last payment was cancelled. Try purchase again.';
                _latestPayment = latestPayment;
              });
              // Stop automatic payment status checking since payment is completed
              _stopAutomaticPaymentStatusChecking();
            } else if (paymentStatus == 'failed') {
              debugPrint('❌ Last payment failed');
              // Show trial screen with failure info
              setState(() {
                _showMainScreen = true;
                _errorMessage = 'Your last payment failed. Try purchase again.';
                _latestPayment = latestPayment;
              });
              // Stop automatic payment status checking since payment is completed
              _stopAutomaticPaymentStatusChecking();
            } else if (LicensingService.isPaymentSuccessful(result)) {
              debugPrint('✅ Payment was successful - license should be active');

              setState(() {
                _latestPayment = latestPayment;
              });

              // Stop automatic payment status checking since payment is completed
              _stopAutomaticPaymentStatusChecking();
            } else if (LicensingService.hasNoPayments(result)) {
              debugPrint('💳 No payments found - show regular buy screen');
              setState(() {
                _showMainScreen = true;
                _errorMessage = null;
                _latestPayment = null;
              });
              // Stop automatic payment status checking since no payments
              _stopAutomaticPaymentStatusChecking();
            } else {
              debugPrint('❓ Unknown payment status: $paymentStatus');
              // Default to showing buy screen for unknown statuses
              setState(() {
                _showMainScreen = true;
                _errorMessage = null;
                _latestPayment = latestPayment;
              });
              // Stop automatic payment status checking for unknown status
              _stopAutomaticPaymentStatusChecking();
            }
          } else {
            debugPrint('❌ Server check failed: ${result['error']}');
          }
        } catch (e) {
          debugPrint('⚠️ Error checking server for payments: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error checking existing payment status: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Clean up purchase service
    PurchaseService.dispose();
    // Remove purchase state change listener
    PurchaseService.removeStateChangeListener(() {});
    // Stop automatic payment status checking timer
    _stopAutomaticPaymentStatusChecking();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Reset payment state when app becomes active (user returns from payment screen)
    if (state == AppLifecycleState.resumed) {
      if (_paymentInProgress) {
        setState(() => _paymentInProgress = false);
        PurchaseService.cancelCurrentPurchase();
      }

      // Always check server for payment status when app resumes
      // This ensures we show the correct screen even if the app was closed during a payment
      _checkExistingPaymentStatus();
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

  Future<void> _buyProduct(String productId) async {
    if (!mounted) return;

    // Check if there's already a pending payment
    final currentStatus = PurchaseService.getCurrentPaymentStatus();
    if (currentStatus == 'pending') {
      debugPrint('⚠️ Purchase blocked - payment already pending');
      _showSnack('Payment already in progress. Please wait for confirmation.');
      return;
    }

    setState(() {
      _paymentInProgress = true;
      _showMainScreen = false; // Show payment status screen
    });
    final provider = context.read<LicensingProvider>();

    debugPrint('🛒 Starting purchase for product: $productId');
    debugPrint('🔍 Current provider state: ${provider.state}');

    try {
      await PurchaseService.buyProduct(
        productId,
        licensingProvider: provider,
      );

      // Check if the purchase is pending
      final paymentStatus = PurchaseService.getCurrentPaymentStatus();
      if (paymentStatus == 'pending') {
        debugPrint('⏳ Purchase is pending - waiting for payment confirmation');
        debugPrint(
            '🔍 Provider state after pending purchase: ${provider.state}');

        // Don't show completion message - purchase is still pending
        // User should see pending status in UI
      } else {
        debugPrint('✅ Purchase completed successfully');
        debugPrint('🔍 Provider state after purchase: ${provider.state}');
      }

      // Check if we need to manually trigger a rebuild
      if (mounted) {
        debugPrint('🔄 Manually triggering setState to ensure UI rebuilds');
        setState(() {
          // This will trigger a rebuild and check the provider state
        });
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('❌ Purchase failed with error: $e');

      setState(() {
        _errorMessage = e.toString();
      });
      _showSnack(e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _paymentInProgress = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Display payment information in a user-friendly format
  Widget _buildPaymentInfo(Map<String, dynamic> payment) {
    final amount = LicensingService.getPaymentAmount(payment);
    final date = LicensingService.getPaymentDate(payment);
    final status = payment['status'] as String? ?? 'unknown';
    final productId = payment['productId'] as String? ?? 'Unknown Product';

    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
      case 'paid':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status == 'cancelled'
                      ? 'Payment Cancelled'
                      : 'Payment Information',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (status == 'cancelled')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'CANCELLED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Product:',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              Text(
                productId,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Amount:',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Date:',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Status:',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Get the current payment status for UI display
  String _getCurrentPaymentStatus() {
    // If we have a latest payment, we need to check if it's still current
    // Always prioritize server data over local cached data
    if (_latestPayment != null) {
      // Return the status from the latest payment data
      final status = _latestPayment!['status'];
      debugPrint('🔍 Using latest payment status from data: $status');
      return status;
    }

    // Fallback to PurchaseService
    return PurchaseService.getCurrentPaymentStatus();
  }

  /// Check if we should show payment status in the UI
  bool _shouldShowPaymentStatus() {
    debugPrint('🔍 _shouldShowPaymentStatus called');
    debugPrint('🔍 _showMainScreen: $_showMainScreen');

    // If user explicitly wants to see main screen, don't show payment status
    if (_showMainScreen) {
      debugPrint('🔍 User wants main screen, not showing payment status');
      return false;
    }

    final status = _getCurrentPaymentStatus();
    debugPrint('🔍 Current payment status: $status');

    // Don't show payment status for completed payments (paid, failed, cancelled)
    // Only show for pending payments
    if (status == 'paid' || status == 'failed' || status == 'cancelled') {
      debugPrint(
          '🔍 Payment completed ($status), not showing payment status screen');
      // Stop automatic payment status checking since payment is completed
      _stopAutomaticPaymentStatusChecking();
      return false;
    }

    // Show payment status if there's an active pending payment
    final shouldShow = status == 'pending';
    debugPrint('🔍 Should show payment status: $shouldShow (status: $status)');
    return shouldShow;
  }

  /// Get the payment status text for display
  String _getPaymentStatusText() {
    final status = _getCurrentPaymentStatus();
    switch (status) {
      case 'pending':
        return 'Payment Processing...';
      case 'paid':
        return 'Payment Confirmed!';
      case 'failed':
        return 'Payment Failed';
      case 'cancelled':
        return 'Payment Cancelled';
      default:
        return 'Unknown Status';
    }
  }

  /// Get the payment status color for display
  Color _getPaymentStatusColor() {
    final status = _getCurrentPaymentStatus();
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'paid':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  /// Get the main content based on purchase and payment status
  Widget _getMainContent(String titleText, String detailText, Color brand) {
    final paymentStatus = _getCurrentPaymentStatus();
    debugPrint('🔍 Building main content with payment status: $paymentStatus');
    debugPrint('🔍 _showMainScreen: $_showMainScreen');
    debugPrint('🔍 _shouldShowPaymentStatus: ${_shouldShowPaymentStatus()}');

    // Simplified: Only check payment status, no complex verification logic
    // If payment is pending, show the unified processing screen

    // If payment is pending, show the unified processing screen
    if (paymentStatus == 'pending') {
      debugPrint('🔄 Showing unified pending payment screen');
      return _buildUnifiedPaymentProcessingScreen();
    }

    // If payment is completed (paid, failed, cancelled), show appropriate message
    if (paymentStatus == 'paid' ||
        paymentStatus == 'failed' ||
        paymentStatus == 'cancelled') {
      final isPaid = paymentStatus == 'paid';
      final isCancelled = paymentStatus == 'cancelled';

      debugPrint('🔍 Payment completion screen - Status: $paymentStatus');
      if (_latestPayment != null) {
        debugPrint('🔍 Latest payment data: ${_latestPayment}');
      }

      return Container(
        width: double.infinity, // Ensure full width
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 0), // Add horizontal padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment
              .stretch, // Ensure children stretch to full width
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPaid
                  ? Icons.check_circle
                  : (isCancelled ? Icons.cancel : Icons.error),
              size: 64,
              color: isPaid
                  ? Colors.green
                  : (isCancelled ? Colors.grey : Colors.red),
            ),
            const SizedBox(height: 24),
            Text(
              isPaid
                  ? 'Payment Confirmed!'
                  : (isCancelled ? 'Payment Cancelled' : 'Payment Failed'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: isPaid
                        ? Colors.green
                        : (isCancelled ? Colors.grey : Colors.red),
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              isPaid
                  ? 'Your purchase has been confirmed! You now have access to premium features.'
                  : (isCancelled
                      ? 'Your payment was cancelled. You can try purchasing again.'
                      : 'There was an issue processing your payment. Please try again.'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Show different buttons based on the payment status
            if (isPaid) ...[
              // For successful payments, show Continue to App button
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Navigate directly to connection screen
                    debugPrint(
                        '🚀 Continue to App button pressed - navigating to connection');

                    // Navigate to connection screen
                    Navigator.of(context).pushReplacementNamed('/connection');
                  },
                  icon:
                      Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                  label: Text(
                    'Continue to App',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    minimumSize: Size(0, 36),
                  ),
                ),
              ),
            ] else ...[
              // For failed/cancelled payments, show the regular Buy Again button
              Center(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Reset payment status and go back to main screen
                    debugPrint(
                        '🔄 Buy again button pressed - resetting payment status');
                    PurchaseService.resetPaymentStatus();
                    debugPrint(
                        '🔄 Payment status reset, going back to main screen');
                    // Stop automatic payment status checking since we're resetting
                    _stopAutomaticPaymentStatusChecking();
                    setState(() {
                      _showMainScreen = true;
                      _latestPayment = null; // Clear the latest payment data
                    });
                  },
                  icon:
                      Icon(Icons.arrow_back, color: Colors.grey[600], size: 16),
                  label: Text(
                    'Buy again',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    side: BorderSide(color: Colors.grey[400]!),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    minimumSize: Size(0, 36), // Reduce minimum height
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Default content for no payment status
    return _buildDefaultContent(titleText, detailText, brand);
  }

  // Removed verification failure screen - now only checking payment status

  /// Builds the default content for the main screen (no active payment)
  Widget _buildDefaultContent(
      String titleText, String detailText, Color brand) {
    return Container(
      width: double.infinity, // Ensure full width
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 0), // Add horizontal padding
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment
              .stretch, // Ensure children stretch to full width
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
            if (widget.message != null && widget.message!.isNotEmpty) ...[
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

            // Error message if any
            if (_errorMessage != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _latestPayment != null &&
                          _latestPayment!['status'] == 'cancelled'
                      ? Colors.red.withOpacity(0.2)
                      : Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _latestPayment != null &&
                            _latestPayment!['status'] == 'cancelled'
                        ? Colors.red.withOpacity(0.5)
                        : Colors.redAccent.withOpacity(0.4),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _latestPayment != null &&
                                  _latestPayment!['status'] == 'cancelled'
                              ? Icons.cancel_outlined
                              : Icons.error_outline,
                          color: _latestPayment != null &&
                                  _latestPayment!['status'] == 'cancelled'
                              ? Colors.red
                              : Colors.redAccent,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: _latestPayment != null &&
                                      _latestPayment!['status'] == 'cancelled'
                                  ? Colors.red.shade300
                                  : Colors.redAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            _buildActionsForState(widget.state, brand, titleText, detailText),
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
    );
  }

  /// Shorten message for display
  String _shortMessage(String message) {
    if (message.length <= 100) return message;
    return '${message.substring(0, 97)}...';
  }

  /// Check if a timestamp value is valid and can be parsed
  bool _isValidTimestamp(dynamic timestamp) {
    if (timestamp == null) return false;

    try {
      if (timestamp is String) {
        DateTime.parse(timestamp);
        return true;
      } else if (timestamp is int) {
        // Handle Unix timestamp in milliseconds
        DateTime.fromMillisecondsSinceEpoch(timestamp);
        return true;
      } else if (timestamp is DateTime) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ Invalid timestamp format: $timestamp, error: $e');
      return false;
    }
  }

  /// Parse a timestamp value safely, returning current time if parsing fails
  DateTime _parseTimestamp(dynamic timestamp) {
    try {
      if (timestamp is String) {
        return DateTime.parse(timestamp);
      } else if (timestamp is int) {
        // Handle Unix timestamp in milliseconds
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is DateTime) {
        return timestamp;
      } else {
        debugPrint('⚠️ Unknown timestamp type: ${timestamp.runtimeType}');
        return DateTime.now();
      }
    } catch (e) {
      debugPrint('⚠️ Error parsing timestamp: $timestamp, error: $e');
      return DateTime.now();
    }
  }

  // Manual refresh payment status (no automatic polling per spec)
  Future<void> _refreshPaymentStatus() async {
    if (mounted) {
      setState(() => _busy = true);
    }

    try {
      debugPrint('🔄 Manually refreshing payment status...');

      // Call cloud function to check payment status
      final result = await LicensingService.checkPaymentStatus();

      debugPrint('📊 Payment status response: $result');

      // Update UI with new status
      if (mounted) {
        setState(() {
          // Trigger rebuild to show updated status
        });
      }

      // Check if payment is now complete
      if (result['data']?['status'] == 'paid') {
        debugPrint('✅ Payment confirmed as paid!');

        // Complete the purchase flow since payment is now confirmed
        PurchaseService.completePurchaseWhenPaymentConfirmed();

        // Refresh license status
        final provider = context.read<LicensingProvider>();
        await provider.refresh();
      } else if (result['data']?['status'] == 'pending') {
        debugPrint('⏳ Payment still pending - user should continue waiting');

        // Show a helpful message to the user
        if (mounted) {
          setState(() {
            _errorMessage =
                'Payment is still being processed by Google Play. Please wait a few minutes and try again.';
          });
        }

        // Don't complete purchase - let it wait for final status
      } else {
        // Payment is not pending (failed, cancelled, no_payments, etc.)
        debugPrint(
            '❌ Payment status: ${result['data']?['status']} - going back to buy screen');

        // Clear payment status since payment is no longer pending
        PurchaseService.clearPaymentStatus();

        // Go back to buy screen
        if (mounted) {
          setState(() {
            _showMainScreen = true;
            _errorMessage = null; // Clear any error messages
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error refreshing payment status: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to refresh payment status: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = context.watch<BrandingProvider>();
    final Color brand = branding.themeColor;

    final String titleText = _titleForState(widget.state);
    final String detailText =
        _detailForState(widget.state, widget.linkedDeviceId);

    // Check payment status for UI updates
    final currentPaymentStatus = _getCurrentPaymentStatus();
    debugPrint(
        '🎨 TrialOrPurchaseScreen.build() - State: ${widget.state}, Payment Status: $currentPaymentStatus');
    debugPrint('🎨 TrialOrPurchaseScreen.build() - State: ${widget.state}');
    debugPrint('📝 Title: $titleText');
    debugPrint('📄 Detail: $detailText');

    return Scaffold(
      body: Stack(
        children: [
          // Background feature cards
          const BackgroundFeatureCards(
            cardCount: 12,
            opacity: 0.25,
            maxRotation: 30.0,
          ),
          Container(
            padding: const EdgeInsets.all(16),
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
            child: (widget.state == LicenseGateState.noLicense ||
                    widget.state == LicenseGateState.licenseRevoked ||
                    widget.state == LicenseGateState.linkedToOtherDevice)
                ? _buildFullHeightContent(titleText, detailText, brand)
                : _getMainContent(titleText, detailText, brand),
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
                      widget.state == LicenseGateState.paymentPending
                          ? 'Payment Processing...'
                          : 'Processing Payment...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.state == LicenseGateState.paymentPending
                          ? 'Your payment is being processed by Google Play. Don\'t close the app.'
                          : 'Please complete the payment in the store',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
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
      case LicenseGateState.paymentPending:
        return 'Payment Processing';
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
      case LicenseGateState.paymentPending:
        return 'Your payment is being processed. Please wait for confirmation.';
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
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _latestPayment != null &&
                                        _latestPayment!['status'] == 'cancelled'
                                    ? Colors.red.withOpacity(0.2)
                                    : Colors.redAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _latestPayment != null &&
                                          _latestPayment!['status'] ==
                                              'cancelled'
                                      ? Colors.red.withOpacity(0.5)
                                      : Colors.redAccent.withOpacity(0.4),
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _latestPayment != null &&
                                                _latestPayment!['status'] ==
                                                    'cancelled'
                                            ? Icons.cancel_outlined
                                            : Icons.error_outline,
                                        color: _latestPayment != null &&
                                                _latestPayment!['status'] ==
                                                    'cancelled'
                                            ? Colors.red
                                            : Colors.redAccent,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: TextStyle(
                                            color: _latestPayment != null &&
                                                    _latestPayment!['status'] ==
                                                        'cancelled'
                                                ? Colors.red.shade300
                                                : Colors.redAccent,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_latestPayment != null &&
                                      _latestPayment!['status'] ==
                                          'cancelled') ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'You can try purchasing again or start a free trial to continue.',
                                      style: TextStyle(
                                        color: Colors.red.shade200,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],

                          // Payment information if available
                          if (_latestPayment != null) ...[
                            _buildPaymentInfo(_latestPayment!),
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
      case LicenseGateState.paymentPending:
        // Use the unified payment processing screen for consistency
        return _buildUnifiedPaymentProcessingScreen();
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: Size(0, 40), // Reduce minimum height
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
              title: 'Lifetime License',
              priceNote: 'One-time purchase',
              color: brand,
              features: const [
                'All features & future updates',
                'Single-device license',
                'Included support',
              ],
              ctaLabel: 'Buy',
              productId: 'n2mp_tetsing_id',
              onPressed: () => _buyProduct('n2mp_tetsing_id'),
            ),
          ),
          // const SizedBox(width: 12, height:W 12),
          // Flexible(
          //   flex: 1,
          //   child: _planCard(
          //     title: 'Enterprise',
          //     priceNote: 'One-time purchase',
          //     color: brand,
          //     features: const [
          //       'All features in Individual license',
          //       'Custom branding (logos, app title, about, support, website, email, colors)',
          //       'Priority support',
          //     ],
          //     ctaLabel: 'Buy Enterprise',
          //     productId: 'test23',
          //     onPressed: () => _buyProduct('test23'),
          //   ),
          // ),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              // Product availability indicator
              FutureBuilder<Map<String, dynamic>>(
                future: PurchaseService.getProductInfo(productId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                      ),
                    );
                  }

                  if (snapshot.hasError || !snapshot.data!['available']) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'UNAVAILABLE',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }

                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'AVAILABLE',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ],
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
            child: FutureBuilder<Map<String, dynamic>>(
              future: PurchaseService.getProductInfo(productId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.grey),
                        ),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError || !snapshot.data!['available']) {
                  // Product not found or error occurred
                  final errorMessage =
                      snapshot.data?['error'] ?? 'Product not available';
                  return Column(
                    children: [
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              errorMessage,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: const Text(
                          'This product may not be configured in the store yet. Please check with the development team.',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  );
                }

                // Product found, show buy button or payment status
                final productInfo = snapshot.data!;

                // Check if we should show payment status instead of buy button
                if (_shouldShowPaymentStatus()) {
                  final statusText = _getPaymentStatusText();
                  final statusColor = _getPaymentStatusColor();

                  return Column(
                    children: [
                      // Status display
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: statusColor.withOpacity(0.3)),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (statusColor ==
                                  Colors.orange) // Show spinner for pending
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        statusColor),
                                  ),
                                ),
                              if (statusColor == Colors.orange) // Add spacing
                                const SizedBox(width: 8),
                              Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Manual refresh button (no automatic polling per spec)
                      const SizedBox(height: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(0.7),
                          side:
                              BorderSide(color: Colors.white.withOpacity(0.3)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _busy ? null : _refreshPaymentStatus,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_busy)
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white.withOpacity(0.7)),
                                ),
                              )
                            else
                              Icon(Icons.refresh, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              _busy ? 'Checking...' : 'Refresh Status',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                // Show buy button if no payment in progress
                final price = productInfo['price'];
                final buttonText = '$ctaLabel - $price';
                return Center(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      minimumSize: Size(120, 36), // Reduce width to 120px
                    ),
                    onPressed: onPressed,
                    child: Text(
                      buttonText,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Unified payment processing screen used in both scenarios
  Widget _buildUnifiedPaymentProcessingScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.pending_actions,
          size: 64,
          color: Colors.orange,
        ),
        const SizedBox(height: 24),
        Text(
          'Payment Processing...',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Your purchase was initiated, but we\'re waiting for Google Play to confirm the payment. Please don\'t close the app.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.orange.withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Payment Status: Processing',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'This usually takes a few minutes.',
                style: TextStyle(
                  color: Colors.orange[700],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
