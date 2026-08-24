import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/branding_provider.dart';
import '../../theme/app_spacing.dart';

class AboutSettings extends StatelessWidget {
  final Size screenSize;
  final Color modeColor;

  const AboutSettings(
      {super.key, required this.screenSize, required this.modeColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<BrandingProvider>(
      builder: (context, branding, child) {
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Dynamic Logo
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: modeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  ),
                  child: branding.createLogoWidget(
                    width: screenSize.width * 0.22,
                    fit: BoxFit.contain,
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),
                // Dynamic Tagline
                Text(
                  branding.tagLine,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                // Contact details
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.email,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          branding.supportEmail,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () {},
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.language,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            branding.website,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: modeColor,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.xxl),
                // Dynamic Footer Credits
                Text(
                  branding.footerCredits,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
