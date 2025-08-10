import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/licensing_provider.dart';
import '../../providers/branding_provider.dart';
import '../../services/licensing_service.dart';
import '../../services/purchase_service.dart';

class TrialOrPurchaseScreen extends StatefulWidget {
  final LicenseGateState state;
  final String? message;
  final String? linkedDeviceId;
  const TrialOrPurchaseScreen(
      {super.key, required this.state, this.message, this.linkedDeviceId});

  @override
  State<TrialOrPurchaseScreen> createState() => _TrialOrPurchaseScreenState();
}

class _TrialOrPurchaseScreenState extends State<TrialOrPurchaseScreen> {
  bool _busy = false;

  Future<void> _startTrial() async {
    if (mounted) {
      setState(() => _busy = true);
    }
    // Capture provider while this State is still mounted to avoid using context later
    final licensingProvider =
        mounted ? context.read<LicensingProvider>() : null;
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
        _showSnack(res['error']?['message'] ?? 'Failed to start trial');
      }
    }
  }

  Future<void> _buyNow() async {
    if (!mounted) return;
    setState(() => _busy = true);
    final provider = context.read<LicensingProvider>();
    try {
      await PurchaseService.buyProduct(
        'n2mp_individual_lifetime',
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
    setState(() => _busy = true);
    final provider = context.read<LicensingProvider>();
    try {
      await PurchaseService.buyProduct(
        productId,
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
      body: Container(
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Card(
              color: const Color(0xFF161616),
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: brand.withOpacity(0.25), width: 1),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          branding.createLogoWidget(height: 40),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  branding.appTitle,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  branding.tagLine,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
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
                      if (widget.message != null &&
                          widget.message!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _shortMessage(widget.message!),
                            style: TextStyle(
                              color: Colors.orange.shade300,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      // Actions
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: CircularProgressIndicator(),
                        )
                      else
                        _buildActionsForState(widget.state, brand),
                      const SizedBox(height: 22),
                      // Footer note
                      Text(
                        'Your device will be linked to your license. You can transfer once every 30 days.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _titleForState(LicenseGateState s) {
    switch (s) {
      case LicenseGateState.noLicense:
        return 'License required';
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
        return 'Start a free trial or purchase a license to continue.';
      case LicenseGateState.trialExpired:
        return 'Your trial has ended. Purchase a license to continue using all features.';
      case LicenseGateState.linkedToOtherDevice:
        return deviceId == null
            ? 'Your license is linked to another device.'
            : 'Your license is currently linked to: $deviceId';
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

  Widget _buildActionsForState(LicenseGateState state, Color brand) {
    switch (state) {
      case LicenseGateState.noLicense:
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
      case LicenseGateState.trialExpired:
        return _buildPlansRow(brand);
      case LicenseGateState.linkedToOtherDevice:
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
      case LicenseGateState.licenseRevoked:
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
          Expanded(
            child: _planCard(
              title: 'Individual',
              priceNote: 'One-time purchase',
              color: brand,
              features: const [
                'Single-device license',
                'All core navigation features',
                'Email support',
              ],
              ctaLabel: 'Buy Individual',
              onPressed: () => _buyProduct('n2mp_individual_lifetime'),
            ),
          ),
          const SizedBox(width: 12, height: 12),
          Expanded(
            child: _planCard(
              title: 'Enterprise',
              priceNote: 'One-time purchase',
              color: brand,
              features: const [
                'Multi-device licensing',
                'Enterprise features & branding',
                'Priority support',
              ],
              ctaLabel: 'Buy Enterprise',
              onPressed: () => _buyProduct('n2mp_enterprise_lifetime'),
            ),
          ),
        ];
        return isNarrow ? Column(children: children) : Row(children: children);
      },
    );
  }

  Widget _planCard({
    required String title,
    required String priceNote,
    required Color color,
    required List<String> features,
    required String ctaLabel,
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
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withOpacity(0.7), width: 1.2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onPressed,
              child: Text(
                ctaLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
