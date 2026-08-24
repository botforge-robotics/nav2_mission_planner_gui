import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/modals/mission.dart';
import 'package:nav2_mission_planner/providers/branding_provider.dart';
import 'package:nav2_mission_planner/services/docking_service.dart';
import 'package:nav2_mission_planner/services/mission_execution_service.dart';

/// Full-height right-side panel shown while a mission is executing, listing
/// every mission item with live per-item progress (distance remaining for a
/// goto, countdown for a wait, dock status for dock/undock). Extracted
/// verbatim from navigation_screen.dart's build() (the panel body) and its
/// `_buildMissionExecutionItem` helper — both are pure render over
/// `MissionExecutionService`, which this widget still reads directly via
/// `Consumer`, same as the screen did.
class MissionExecutionPanel extends StatelessWidget {
  final Color modeColor;

  const MissionExecutionPanel({super.key, required this.modeColor});

  @override
  Widget build(BuildContext context) {
    return Consumer<MissionExecutionService>(
      builder: (context, missionService, _) {
        if (!missionService.isRunning ||
            missionService.currentMission == null) {
          return const SizedBox.shrink();
        }

        return Positioned(
          right: 0,
          top: 0,
          bottom: 0, // extend to bottom edge
          child: Container(
            width: 300,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(-2, 0),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[700]!, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: modeColor.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child:
                            Icon(Icons.play_arrow, color: modeColor, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mission In Progress',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              missionService.currentMission!.missionName,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red[400]!.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: GestureDetector(
                          onTap: () => missionService.cancel(),
                          child: const Icon(Icons.stop,
                              color: Colors.red, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),

                // Mission items scroll list fills remaining space
                Expanded(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Column(
                      children: [
                        for (int i = 0;
                            i < missionService.currentMission!.items.length;
                            i++)
                          _buildMissionExecutionItem(
                            context,
                            missionService.currentMission!.items[i],
                            i,
                            missionService.currentIndex,
                            missionService,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMissionExecutionItem(BuildContext context, MissionItem item,
      int index, int currentIndex, MissionExecutionService missionService) {
    final bool isActive = index == currentIndex;
    final bool isCompleted = index < currentIndex;

    // Get item-specific feedback for active items
    String? feedbackText;
    if (isActive) {
      switch (item.type) {
        case MissionItemType.goto:
          final distance = missionService.distanceRemaining;
          if (distance != null && distance > 0) {
            feedbackText = '${distance.toStringAsFixed(1)}m remaining';
          }
          break;
        case MissionItemType.wait:
          final remaining = missionService.waitTimeRemaining;
          if (remaining != null && remaining > 0) {
            feedbackText = '${remaining.toStringAsFixed(1)}s remaining';
          }
          break;
        case MissionItemType.dock:
        case MissionItemType.undock:
          feedbackText = DockingService.instance.status.replaceAll('_', ' ');
          break;
        default:
          break;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive ? Colors.grey[800] : Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? item.type.color : Colors.grey[700]!,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 4,
            height: 60,
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green
                  : (isActive ? item.type.color : Colors.grey[600]),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Item icon with status
                  Stack(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? Colors.green.withValues(alpha: 0.2)
                              : item.type.color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Icon(
                            isCompleted ? Icons.check : item.type.icon,
                            color: isCompleted ? Colors.green : item.type.color,
                            size: 20,
                          ),
                        ),
                      ),
                      if (isActive)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Provider.of<BrandingProvider>(context,
                                      listen: false)
                                  .themeColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.grey[800]!,
                                width: 2,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // Item details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${index + 1}. ',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              item.type.displayName,
                              style: TextStyle(
                                color: isCompleted
                                    ? Colors.green
                                    : item.type.color,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.displayTitle,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isActive && feedbackText != null)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: item.type.color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              feedbackText,
                              style: TextStyle(
                                color: item.type.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
