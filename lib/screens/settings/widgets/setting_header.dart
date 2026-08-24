import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../theme/app_spacing.dart';

class SettingHeader extends StatelessWidget {
  final String title;
  final FaIconData icon;
  final Size screenSize;
  final Color modeColor;

  const SettingHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.screenSize,
    required this.modeColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: modeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: FaIcon(
                icon,
                size: 16,
                color: modeColor,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              title,
              style: theme.textTheme.headlineSmall,
            ),
          ],
        ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          height: 1,
          color: theme.colorScheme.outlineVariant,
        ),
      ],
    );
  }
}
