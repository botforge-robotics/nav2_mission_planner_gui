import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/license_provider.dart';
import '../../providers/branding_provider.dart';
import '../../theme/app_theme.dart';

class TamperingWarningScreen extends StatelessWidget {
  const TamperingWarningScreen({Key? key}) : super(key: key);

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
              // Warning Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 60,
                  color: Colors.red,
                ),
              ),

              const SizedBox(height: 32),

              // Title
              Text(
                'Time Tampering Detected',
                style: AppTheme.titleTextStyle.copyWith(
                  color: Colors.red,
                  fontSize: 28,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Description
              Text(
                'We detected that the device time has been modified. This is not allowed and may indicate an attempt to bypass the trial or license system.',
                style: AppTheme.statusTextStyle.copyWith(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // Possible causes
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
                          'Possible Causes:',
                          style: AppTheme.titleTextStyle.copyWith(
                            color: brandingProvider.themeColor,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildCauseItem('• Device time was manually changed'),
                        _buildCauseItem('• Device was restored from backup'),
                        _buildCauseItem('• System clock was modified'),
                        _buildCauseItem(
                            '• Device was reset to factory settings'),
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
                    child: Consumer<BrandingProvider>(
                      builder: (context, brandingProvider, child) {
                        return ElevatedButton(
                          onPressed: () async {
                            final provider = context.read<LicenseProvider>();
                            await provider.checkLicense();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandingProvider.themeColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Retry Verification',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Contact Support Button
                  SizedBox(
                    width: double.infinity,
                    child: Consumer<BrandingProvider>(
                      builder: (context, brandingProvider, child) {
                        return OutlinedButton(
                          onPressed: () {
                            // TODO: Implement contact support
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Contact support feature coming soon'),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: brandingProvider.themeColor,
                            side:
                                BorderSide(color: brandingProvider.themeColor),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Contact Support',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Reset App Button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Reset App'),
                            content: const Text(
                              'This will clear all app data and reset to initial state. Are you sure?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Reset'),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true) {
                          final provider = context.read<LicenseProvider>();
                          await provider.clearLicenseData();
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Reset App Data',
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

  Widget _buildCauseItem(String text) {
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
