import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map/micro_adjustment_hud.dart';
import '../../widgets/map/occupancy_grid_view.dart';

/// Redesigned Robot Location Picker Screen with 5mm D-Pad precision
/// and 1-degree orientation controls.
class PickMapPositionScreen extends StatefulWidget {
  const PickMapPositionScreen({
    super.key,
    this.initialPose,
    this.title = 'Select Robot Position',
  });

  final ({double x, double y, double theta})? initialPose;
  final String title;

  @override
  State<PickMapPositionScreen> createState() => _PickMapPositionScreenState();
}

class _PickMapPositionScreenState extends State<PickMapPositionScreen> {
  ({double x, double y, double theta})? _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialPose;
  }

  void _onNudge(double dx, double dy) {
    if (_draft == null) return;
    setState(() {
      _draft = (
        x: _draft!.x + dx,
        y: _draft!.y + dy,
        theta: _draft!.theta,
      );
    });
  }

  void _onRotate(double dTheta) {
    if (_draft == null) return;
    var newTheta = _draft!.theta + dTheta;
    // Normalize to [-pi, pi]
    while (newTheta > pi) {
      newTheta -= 2 * pi;
    }
    while (newTheta < -pi) {
      newTheta += 2 * pi;
    }
    setState(() {
      _draft = (
        x: _draft!.x,
        y: _draft!.y,
        theta: newTheta,
      );
    });
  }

  void _snapToRobot(RobotTelemetryProvider telemetry) {
    final p = telemetry.rawPose?.pose.pose;
    if (p == null) return;
    final yaw = atan2(
      2 * (p.orientation.w * p.orientation.z + p.orientation.x * p.orientation.y),
      1 - 2 * (p.orientation.y * p.orientation.y + p.orientation.z * p.orientation.z),
    );
    setState(() {
      _draft = (
        x: p.position.x,
        y: p.position.y,
        theta: yaw,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ros2 = context.watch<ConnectionProvider>().ros2;
    final telemetry = context.watch<RobotTelemetryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (telemetry.rawPose != null)
            TextButton.icon(
              onPressed: () => _snapToRobot(telemetry),
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('Snap to Robot'),
            ),
        ],
      ),
      body: ros2 == null
          ? const Center(child: Text('Not connected to robot.'))
          : Stack(
              children: [
                Positioned.fill(
                  child: OccupancyGridView(
                    ros2: ros2,
                    interactive: true,
                    posePicking: true,
                    showLaserScan: true,
                    draftPoseOverride: _draft,
                    onDraftPose: (x, y, theta) =>
                        setState(() => _draft = (x: x, y: y, theta: theta)),
                  ),
                ),

                // Top Floating Telemetry Readout Pill
                if (_draft != null)
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    child: Center(
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        color: AppColors.surface.withValues(alpha: 0.95),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 8,
                          ),
                          child: Wrap(
                            spacing: 16,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.place_rounded,
                                      size: 16, color: AppColors.accent),
                                  const SizedBox(width: 4),
                                  Text(
                                    'X: ${_draft!.x.toStringAsFixed(3)} m',
                                    style: const TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.place_rounded,
                                      size: 16, color: AppColors.accent),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Y: ${_draft!.y.toStringAsFixed(3)} m',
                                    style: const TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.navigation_rounded,
                                      size: 16, color: AppColors.accent),
                                  const SizedBox(width: 4),
                                  Text(
                                    'θ: ${(_draft!.theta * 180 / pi).toStringAsFixed(1)}°',
                                    style: const TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Floating 5mm & 1° Micro-Adjustment D-Pad HUD
                if (_draft != null)
                  Positioned(
                    bottom: 84,
                    right: AppSpacing.md,
                    child: MicroAdjustmentHud(
                      title: 'Nudge (5mm / 1°)',
                      showRotation: true,
                      onNudge: _onNudge,
                      onRotate: _onRotate,
                    ),
                  ),

                // Bottom Action Bar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: _draft == null
                                  ? null
                                  : () => Navigator.of(context).pop(_draft),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Use This Position'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
