import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/branding_provider.dart';

class LicenseCheckingScreen extends StatelessWidget {
  const LicenseCheckingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BrandingProvider>(
      builder: (context, brandingProvider, child) {
        return Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(40),
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
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // License icon with gradient background
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        brandingProvider.themeColor.withValues(alpha: 0.2),
                        brandingProvider.themeColor.withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: brandingProvider.themeColor.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.verified_user,
                    size: 60,
                    color: brandingProvider.themeColor,
                  ),
                ),
                const SizedBox(height: 30),

                // Title
                const Text(
                  'Checking License',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // Subtitle
                const Text(
                  'Verifying your license status...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                // Loading spinner
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        brandingProvider.themeColor),
                  ),
                ),
                const SizedBox(height: 20),

                // Loading dots animation
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildLoadingDot(0, brandingProvider),
                    const SizedBox(width: 8),
                    _buildLoadingDot(1, brandingProvider),
                    const SizedBox(width: 8),
                    _buildLoadingDot(2, brandingProvider),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingDot(int index, BrandingProvider brandingProvider) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 200)),
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: brandingProvider.themeColor.withValues(alpha: value),
            shape: BoxShape.circle,
          ),
        );
      },
      onEnd: () {
        // Restart animation
      },
    );
  }
}
