import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/license_provider.dart';
import '../../providers/branding_provider.dart';
import '../../theme/app_theme.dart';

class MandatoryVerificationScreen extends StatelessWidget {
  const MandatoryVerificationScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Consumer<BrandingProvider>(
                builder: (context, brandingProvider, child) {
                  return Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          brandingProvider.themeColor,
                          brandingProvider.themeColor.withValues(alpha: 0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: brandingProvider.themeColor
                              .withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.cloud_sync,
                      size: 60,
                      color: Colors.white,
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),

              // Title
              Consumer<BrandingProvider>(
                builder: (context, brandingProvider, child) {
                  return Text(
                    'Online Verification Required',
                    style: AppTheme.titleTextStyle.copyWith(
                      color: brandingProvider.themeColor,
                      fontSize: 28,
                    ),
                    textAlign: TextAlign.center,
                  );
                },
              ),

              const SizedBox(height: 16),

              // Description
              Text(
                'Your app requires a mandatory online verification every 30 days to ensure security and prevent unauthorized use.',
                style: AppTheme.statusTextStyle.copyWith(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // Information box
              Consumer<BrandingProvider>(
                builder: (context, brandingProvider, child) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: brandingProvider.themeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            brandingProvider.themeColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Why is this required?',
                          style: AppTheme.titleTextStyle.copyWith(
                            color: brandingProvider.themeColor,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildInfoItem('• Ensures license/trial validity'),
                        _buildInfoItem('• Prevents unauthorized usage'),
                        _buildInfoItem('• Updates security measures'),
                        _buildInfoItem('• Syncs with server data'),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),

              // Action Buttons
              Column(
                children: [
                  // Retry Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final provider = context.read<LicenseProvider>();
                        await provider.checkLicense();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Connect & Verify',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Check Connection Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        final provider = context.read<LicenseProvider>();
                        await provider.checkLicense();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Check Connection',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Help Button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        // TODO: Implement help/support
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Help feature coming soon'),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Need Help?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: AppTheme.statusTextStyle.copyWith(
          fontSize: 14,
          color: Colors.white.withOpacity(0.7),
        ),
      ),
    );
  }
}
