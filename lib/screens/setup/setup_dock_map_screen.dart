import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/setup_flow_controller.dart';
import '../../services/sdk_api_service.dart';
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
class SetupDockMapScreen extends StatefulWidget {
  const SetupDockMapScreen({super.key});

  @override
  State<SetupDockMapScreen> createState() => _SetupDockMapScreenState();
}

class _SetupDockMapScreenState extends State<SetupDockMapScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSetupStep();
    });
  }

  void _syncSetupStep() {
    try {
      final ip = context.read<ConnectionProvider>().robot?.ip ??
          context.read<SetupFlowController>().selectedRobot?.ip;
      if (ip != null && ip.isNotEmpty) {
        SdkApiService(ip).updateSetupStatus(step: 2).catchError((_) => <String, dynamic>{});
      }
    } catch (_) {}
  }

  void _dismissRobotSetup() {
    try {
      final ip = context.read<ConnectionProvider>().robot?.ip ??
          context.read<SetupFlowController>().selectedRobot?.ip;
      if (ip != null && ip.isNotEmpty) {
        SdkApiService(ip).dismissSetup().catchError((_) => <String, dynamic>{});
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
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
        _dismissRobotSetup();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const SetupCompleteScreen(),
          ),
        );
      },
      onBack: () => Navigator.of(context).maybePop(),
      backLabel: 'Back',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // High-resolution visual instructional infographic (adaptive desktop/mobile)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
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
                color: colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, size: 18, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'QUICK CHECKLIST BEFORE MAPPING',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.bold,
                              color: colors.textSecondary,
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
    final colors = AppColors.of(context);
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
                    color: colors.textPrimary,
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
    final colors = AppColors.of(context);
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
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
                color: colors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
                border: Border(
                  bottom: BorderSide(color: colors.borderStrong, width: 2),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fence_rounded, size: 14, color: colors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'SOLID WALL',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                            color: colors.textSecondary,
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
                color: colors.accent.withValues(alpha: 0.2),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                border: Border.all(color: colors.accent, width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flash_on_rounded, size: 14, color: colors.accent),
                  const SizedBox(width: 4),
                  Text(
                    'CHARGER',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Clearance arrows
          Positioned(
            top: 36,
            left: 20,
            child: Row(
              children: [
                Icon(Icons.arrow_back_rounded, size: 14, color: colors.textTertiary),
                const SizedBox(width: 2),
                Text(
                  '>0.5m',
                  style: TextStyle(fontSize: 10, color: colors.textTertiary),
                ),
              ],
            ),
          ),
          Positioned(
            top: 36,
            right: 20,
            child: Row(
              children: [
                Text(
                  '>0.5m',
                  style: TextStyle(fontSize: 10, color: colors.textTertiary),
                ),
                const SizedBox(width: 2),
                Icon(Icons.arrow_forward_rounded, size: 14, color: colors.textTertiary),
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
                    color: colors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.smart_toy_rounded,
                      size: 32,
                      color: colors.textOnPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_downward_rounded,
                        size: 14, color: colors.primary),
                    Text(
                      'Facing Outward',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
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

