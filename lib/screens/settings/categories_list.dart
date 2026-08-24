import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../theme/app_spacing.dart';

class CategoriesList extends StatelessWidget {
  final String selectedCategory;
  final Function(String) onCategorySelected;
  final Size screenSize;

  const CategoriesList({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.screenSize,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Read-only locked-config summary — safe to show for the locked
        // NavProMini deployment (see _RobotDefaults in settings_content.dart:
        // it displays fixed topics/frames, nothing editable). Was hidden
        // pending this redesign; re-enabled here.
        _buildCategoryTile(
          context,
          icon: FontAwesomeIcons.robot,
          title: 'Robot',
        ),
        _buildCategoryTile(
          context,
          icon: FontAwesomeIcons.gamepad,
          title: 'Teleop',
        ),
        _buildCategoryTile(
          context,
          icon: FontAwesomeIcons.camera,
          title: 'Sensor',
        ),
        _buildCategoryTile(
          context,
          icon: FontAwesomeIcons.circleInfo,
          title: 'About',
        ),
      ],
    );
  }

  Widget _buildCategoryTile(
    BuildContext context, {
    required FaIconData icon,
    required String title,
  }) {
    final theme = Theme.of(context);
    final isSelected = selectedCategory == title;
    final color = theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
      ),
      child: InkWell(
        onTap: () => onCategorySelected(title),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              FaIcon(
                icon,
                size: 14,
                color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        isSelected ? color : theme.colorScheme.onSurfaceVariant,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
