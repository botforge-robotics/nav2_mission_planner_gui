import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map/occupancy_grid_view.dart';

/// A full-screen "tap and drag on the map to set a position and heading"
/// picker, returning `(x, y, theta)` via `Navigator.pop` — or null if
/// cancelled. Reused by Mission Editor's "Add Position" step (the
/// reference mockup's own option) rather than duplicating Map View's own
/// pose-picking UI a second time.
class PickMapPositionScreen extends StatefulWidget {
  const PickMapPositionScreen({super.key});

  @override
  State<PickMapPositionScreen> createState() => _PickMapPositionScreenState();
}

class _PickMapPositionScreenState extends State<PickMapPositionScreen> {
  ({double x, double y, double theta})? _draft;

  @override
  Widget build(BuildContext context) {
    final ros2 = context.watch<ConnectionProvider>().ros2;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Position')),
      body: ros2 == null
          ? const Center(child: Text('Not connected.'))
          : Stack(
              children: [
                Positioned.fill(
                  child: OccupancyGridView(
                    ros2: ros2,
                    interactive: true,
                    posePicking: true,
                    onDraftPose: (x, y, theta) =>
                        setState(() => _draft = (x: x, y: y, theta: theta)),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _draft != null
                                ? 'Drag to fine-tune the heading, then confirm.'
                                : "Tap and drag on the map to set the step's position and heading.",
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _draft == null
                                      ? null
                                      : () => Navigator.of(context).pop(_draft),
                                  child: const Text('Use This Position'),
                                ),
                              ),
                            ],
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
