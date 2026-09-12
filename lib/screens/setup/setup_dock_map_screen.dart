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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 768;

    return SetupScaffold(
      step: 4,
      totalSteps: 5,
      maxWidth: isDesktop ? 960 : 480,
      title: 'Place Dock & Create Map',
      subtitle: 'Position your charging station and build your first navigation map.',
      primaryLabel: 'Create Map',
      onPrimary: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CreateMapScreen(fromSetup: true),
          ),
        );
      },
      secondaryLabel: 'Skip Mapping (Go to Home)',
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
            // High-resolution visual instructional infographic (adaptive desktop/mobile)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.asset(
                  isDesktop ? 'assets/desktopDock.png' : 'assets/mobilDockInstruction.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) => const _DockPlacementDiagram(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Pre-mapping checklist
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'QUICK CHECKLIST BEFORE MAPPING',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _buildCheckItem(
                    context,
                    'Charging dock placed firmly against a flat wall with side clearance (≥ 0.5m).',
                  ),
                  _buildCheckItem(
                    context,
                    'Robot positioned on or near charger facing outwards into the room.',
                  ),
                  _buildCheckItem(
                    context,
                    'Clear open corridor in front of the dock (≥ 1.0m) for smooth departure.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckItem(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.done_rounded, size: 14, color: AppColors.success),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.35,
                  ),
            ),
          ),
        ],
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

