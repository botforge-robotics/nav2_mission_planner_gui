import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/modals/bookmark.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:provider/provider.dart';

class BookmarkTooltip extends StatelessWidget {
  final Bookmark bookmark;
  final Color modeColor;
  final VoidCallback onSendGoal;
  final VoidCallback? onAddWaypoint;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  final bool isMissionMode;

  const BookmarkTooltip({
    super.key,
    required this.bookmark,
    required this.modeColor,
    required this.onSendGoal,
    this.onAddWaypoint,
    required this.onDelete,
    required this.onCancel,
    this.isMissionMode = false,
  });

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
