import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/license_provider.dart';
import '../../providers/branding_provider.dart';
import '../../theme/app_theme.dart';

class NoInternetScreen extends StatelessWidget {
  const NoInternetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkTheme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // No Internet Icon
              Consumer<BrandingProvider>(
                builder: (context, brandingProvider, child) {
                  return Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: brandingProvider.themeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(60),
                    ),
                    child: Icon(
                      Icons.wifi_off,
                      size: 60,
                      color: brandingProvider.themeColor,
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),

              // Title
              Text(
                'No Internet Connection',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Message
              Consumer<LicenseProvider>(
                builder: (context, licenseProvider, child) {
                  return Text(
                    licenseProvider.errorMessage ??
                        'Internet is required for first-time setup',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[400],
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  );
                },
              ),
              const SizedBox(height: 40),

              // Instructions
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[800]!.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: Column(
                  children: [
                    Consumer<BrandingProvider>(
                      builder: (context, brandingProvider, child) {
                        return Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: brandingProvider.themeColor, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'What you need to do:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 15),
                    _buildInstructionItem(
                      '1. Connect to Wi-Fi or mobile data',
                      Icons.wifi,
                    ),
                    const SizedBox(height: 10),
                    _buildInstructionItem(
                      '2. Make sure you have a stable connection',
                      Icons.signal_cellular_4_bar,
                    ),
                    const SizedBox(height: 10),
                    _buildInstructionItem(
                      '3. Tap "Retry" to continue',
                      Icons.refresh,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Action Buttons
              Consumer<BrandingProvider>(
                builder: (context, brandingProvider, child) {
                  return Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // Retry license check
                            context.read<LicenseProvider>().checkLicense();
                          },
                          icon: Icon(Icons.refresh),
                          label: Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandingProvider.themeColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // Check connection settings
                            _showConnectionHelp(context);
                          },
                          icon: Icon(Icons.help_outline),
                          label: Text('Help'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: brandingProvider.themeColor,
                            side:
                                BorderSide(color: brandingProvider.themeColor),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),

              // Support Info
              Text(
                'Need help? Contact support',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
              Consumer<BrandingProvider>(
                builder: (context, brandingProvider, child) {
                  return TextButton(
                    onPressed: () {
                      // Open support email or website
                      _openSupport(context);
                    },
                    child: Text(
                      'support@yourcompany.com',
                      style: TextStyle(
                        color: brandingProvider.themeColor,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionItem(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[400], size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
            ),
          ),
        ),
      ],
    );
  }

  void _showConnectionHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text(
          'Connection Help',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To connect to the internet:',
              style: TextStyle(color: Colors.grey[300]),
            ),
            const SizedBox(height: 10),
            Text('• Go to Settings > Wi-Fi',
                style: TextStyle(color: Colors.grey[400])),
            Text('• Turn on Wi-Fi and select a network',
                style: TextStyle(color: Colors.grey[400])),
            Text('• Or enable mobile data',
                style: TextStyle(color: Colors.grey[400])),
            Text('• Make sure you have a stable connection',
                style: TextStyle(color: Colors.grey[400])),
          ],
        ),
        actions: [
          Consumer<BrandingProvider>(
            builder: (context, brandingProvider, child) {
              return TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK',
                    style: TextStyle(color: brandingProvider.themeColor)),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openSupport(BuildContext context) {
    // In a real app, this would open email or support website
    final brandingProvider =
        Provider.of<BrandingProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Support email: support@yourcompany.com'),
        backgroundColor: brandingProvider.themeColor,
      ),
    );
  }
}
