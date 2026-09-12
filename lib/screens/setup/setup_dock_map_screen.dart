import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../maps/create_map_screen.dart';
import 'setup_complete_screen.dart';
import 'setup_scaffold.dart';

/// Step 4 in setup: instructs the operator to place the charging dock
/// firmly against a wall and position the robot near/on the dock, then
/// offers two clear actions:
/// 1. "Create Map" -> opens SLAM [CreateMapScreen], saves & activates the map,
///    then advances to [SetupCompleteScreen].
/// 2. "Skip Mapping" -> skips map creation and goes directly to
///    [SetupCompleteScreen] (with option to map later).
class SetupDockMapScreen extends StatelessWidget {
  const SetupDockMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      step: 4,
      totalSteps: 5,
      title: 'Place Dock & Create Map',
      subtitle: 'Position your charging station and build your first map.',
      primaryLabel: 'Create Map',
      onPrimary: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CreateMapScreen(fromSetup: true),
          ),
        );
      },
      secondaryLabel: 'Skip Mapping (Set up later)',
      onSecondary: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const SetupCompleteScreen(),
          ),
        );
      },
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DockPlacementDiagram(),
            const SizedBox(height: AppSpacing.md),
            const _InstructionCard(
              icon: Icons.dock_rounded,
              iconColor: AppColors.accent,
              title: '1. Dock Stiff Against Wall',
              description:
                  'Place the charging dock flat and firmly against a straight wall with at least 0.5m open space on each side.',
            ),
            const SizedBox(height: AppSpacing.sm),
            const _InstructionCard(
              icon: Icons.smart_toy_rounded,
              iconColor: AppColors.primary,
              title: '2. Place Robot Near Dock',
              description:
                  'Position your robot on or right in front of the dock facing outwards into the room. SLAM uses this as (0,0) origin.',
            ),
            const SizedBox(height: AppSpacing.sm),
            const _InstructionCard(
              icon: Icons.explore_rounded,
              iconColor: AppColors.success,
              title: '3. Create First Navigation Map',
              description:
                  'Drive the robot to scan boundaries, rooms, and corridors. Saving the map automatically activates it for missions.',
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 22,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Starting mapping from the dock ensures your robot knows the exact coordinates of its charger from day one for seamless auto-docking.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Visual diagram illustrating the wall, charging dock, and outward robot orientation.
class _DockPlacementDiagram extends StatelessWidget {
  const _DockPlacementDiagram();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Wall bar at the top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
                border: const Border(
                  bottom: BorderSide(color: AppColors.borderStrong, width: 2),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fence_rounded, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'SOLID WALL',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Dock placed flush against the wall
          Positioned(
            top: 28,
            child: Container(
              width: 100,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.2),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border.all(color: AppColors.accent, width: 1.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flash_on_rounded, size: 14, color: AppColors.accent),
                  SizedBox(width: 4),
                  Text(
                    'CHARGER',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Clearance arrows
          const Positioned(
            top: 36,
            left: 20,
            child: Row(
              children: [
                Icon(Icons.arrow_back_rounded, size: 14, color: AppColors.textTertiary),
                SizedBox(width: 2),
                Text(
                  '>0.5m',
                  style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const Positioned(
            top: 36,
            right: 20,
            child: Row(
              children: [
                Text(
                  '>0.5m',
                  style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                ),
                SizedBox(width: 2),
                Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textTertiary),
              ],
            ),
          ),

          // Robot in front of dock facing outwards
          Positioned(
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.smart_toy_rounded,
                      size: 32,
                      color: AppColors.textOnPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_downward_rounded,
                        size: 14, color: AppColors.primary),
                    Text(
                      'Facing Outward',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
