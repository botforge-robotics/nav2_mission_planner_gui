import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/modals/bookmark.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner/services/docking_service.dart';
import 'package:provider/provider.dart';

class BookmarkTooltip extends StatelessWidget {
  final Bookmark bookmark;
  final Color modeColor;
  final VoidCallback onSendGoal;
  final VoidCallback? onAddWaypoint;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  final bool isMissionMode;
  final VoidCallback? onEditDetails;
  final VoidCallback? onReposition;
  // Only used when bookmark.isDock — trigger the actual dock/undock action
  // servers (dock_manager_node), as opposed to onSendGoal which just drives
  // to this pose with a plain nav goal.
  final VoidCallback? onDock;
  final VoidCallback? onUndock;

  const BookmarkTooltip({
    super.key,
    required this.bookmark,
    required this.modeColor,
    required this.onSendGoal,
    this.onAddWaypoint,
    required this.onDelete,
    required this.onCancel,
    this.isMissionMode = false,
    this.onEditDetails,
    this.onReposition,
    this.onDock,
    this.onUndock,
  });

  String _statusLabel(String status) {
    switch (status) {
      case 'undocked':
        return 'Undocked';
      case 'staging':
        return 'Docking… (staging)';
      case 'detecting':
        return 'Docking… (detecting)';
      case 'docking':
        return 'Docking… (approaching)';
      case 'waiting_for_charge':
        return 'Docking… (confirming charge)';
      case 'charging':
        return 'Docked — charging';
      case 'full':
        return 'Docked — full charge';
      case 'undocking':
        return 'Undocking…';
      case 'error':
        return 'Dock error';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    if (status == 'charging' || status == 'full') return Colors.green;
    if (status == 'error') return Colors.red;
    if (status == 'undocked') return Colors.grey[400]!;
    return Colors.amber;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCancel, // Dismiss on outside tap
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent dismissal when tapping on the dialog
            child: Container(
              width: 300,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top section with bookmark details
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(
                          bookmark.icon,
                          size: 50,
                          color: modeColor,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          bookmark.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (bookmark.isDock) ...[
                          const SizedBox(height: 4),
                          AnimatedBuilder(
                            animation: DockingService.instance,
                            builder: (context, _) {
                              final status = DockingService.instance.status;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: _statusColor(status)),
                                ),
                                child: Text(
                                  'Charging dock — ${_statusLabel(status)}',
                                  style: TextStyle(
                                      color: _statusColor(status),
                                      fontSize: 11),
                                ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          'Position: (${bookmark.positionX.toStringAsFixed(2)}, '
                          '${bookmark.positionY.toStringAsFixed(2)})',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Orientation: ${((bookmark.theta < 0 ? -bookmark.theta : bookmark.theta) * 180 / 3.14159).toStringAsFixed(2)}°',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Edit buttons (details / reposition)
                  if (onEditDetails != null || onReposition != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        children: [
                          if (onEditDetails != null)
                            Expanded(
                              child: TextButton.icon(
                                onPressed: onEditDetails,
                                icon: const Icon(Icons.edit,
                                    color: Colors.white70, size: 18),
                                label: const Text('Edit',
                                    style: TextStyle(color: Colors.white70)),
                              ),
                            ),
                          if (onReposition != null)
                            Expanded(
                              child: TextButton.icon(
                                onPressed: onReposition,
                                icon: const Icon(Icons.open_with,
                                    color: Colors.white70, size: 18),
                                label: const Text('Move',
                                    style: TextStyle(color: Colors.white70)),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Dock/Undock — only for the bookmark marked as the dock.
                  // Distinct from "Send Goal": this calls the actual dock
                  // action server (staging, detection, seat-nudge, charge
                  // confirmation), not a plain drive-there nav goal.
                  if (bookmark.isDock && (onDock != null || onUndock != null))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: AnimatedBuilder(
                        animation: DockingService.instance,
                        builder: (context, _) {
                          final docking = DockingService.instance;
                          final busy = docking.isBusy;
                          final docked = docking.isDocked;
                          return SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: busy
                                  ? null
                                  : (docked ? onUndock : onDock),
                              icon: busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : Icon(docked
                                      ? Icons.eject
                                      : Icons.ev_station),
                              label: Text(busy
                                  ? 'Working…'
                                  : (docked ? 'Undock' : 'Dock')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    docked ? Colors.orange[800] : Colors.green[700],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed:
                                isMissionMode ? onAddWaypoint : onSendGoal,
                            icon: Icon(
                              isMissionMode
                                  ? Icons.add_location
                                  : Icons.navigation,
                              color: Colors.white,
                            ),
                            label: Text(
                              isMissionMode ? 'Add Waypoint' : 'Send Goal',
                              style: TextStyle(color: Colors.white),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: modeColor,
                              padding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.delete),
                            label: const Text('Delete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.withOpacity(0.8),
                              foregroundColor: Colors.white.withOpacity(0.8),
                            ),
                            onPressed: () {
                              // Show confirmation dialog
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Confirm Deletion'),
                                  content: Text(
                                    'Are you sure you want to delete the bookmark "${bookmark.name}" and all its associations?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('Cancel',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16)),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.of(context)
                                            .pop(); // Close confirmation dialog
                                        // Show loading indicator
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (context) => AlertDialog(
                                            backgroundColor: Colors.transparent,
                                            elevation: 0,
                                            content: Center(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CircularProgressIndicator(
                                                      color: modeColor),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    'Deleting bookmark...',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );

                                        // Get the settings provider
                                        final settingsProvider =
                                            Provider.of<SettingsProvider>(
                                                context,
                                                listen: false);
                                        // Delete the bookmark from all associated missions
                                        settingsProvider
                                            .removeBookmarkFromAllMissions(
                                                bookmark);

                                        // Close loading dialog
                                        Navigator.of(context)
                                            .pop(); // Close loading dialog
                                        Navigator.of(context)
                                            .pop(); // Close tooltip dialog
                                      },
                                      child: const Text('Delete',
                                          style: TextStyle(
                                              color: Colors.red, fontSize: 16)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Cancel button spanning full width
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[800],
                          foregroundColor: Colors.white,
                        ),
                        onPressed: onCancel,
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
