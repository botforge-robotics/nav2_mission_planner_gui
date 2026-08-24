import 'package:flutter/material.dart';
import '../../modals/mission.dart';

/// The "Add Mission Item" bottom sheet listing every [MissionItemType]
/// (except captureImage — see the original's `.where` filter). Extracted
/// verbatim from waypoint_panel.dart's `_showAddItemDialog` — pure sheet
/// UI; the caller decides what happens when a type is tapped via
/// [onTypeSelected] (the original inline goto-vs-everything-else dispatch,
/// `_addMissionItem` call, and the five `_show*ItemDialog` calls all stay
/// the caller's responsibility, unchanged).
void showAddMissionItemSheet(
  BuildContext context, {
  required void Function(MissionItemType type) onTypeSelected,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    isScrollControlled: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
        maxWidth: 500,
      ),
      child: Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: 16),

            Text(
              'Add Mission Item',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),

            // Scrollable item type buttons
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: MissionItemType.values
                      .where((t) => t != MissionItemType.captureImage)
                      .map((type) => Container(
                            margin: EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              onTap: () {
                                // Close the selector sheet first
                                Navigator.pop(context);
                                onTypeSelected(type);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: type.color.withOpacity(0.1),
                                  border: Border.all(
                                      color: type.color.withOpacity(0.3)),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: type.color,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Icon(type.icon,
                                        color: type.color, size: 20),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            type.displayName,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            _typeDescription(type),
                                            style: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward_ios,
                                        color: Colors.grey[500], size: 14),
                                  ],
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),

            SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}

String _typeDescription(MissionItemType type) {
  switch (type) {
    case MissionItemType.goto:
      return 'Navigate to a specific position';
    case MissionItemType.dock:
      return "Dock at the map's charging station and charge";
    case MissionItemType.undock:
      return 'Undock from the charging station';
    case MissionItemType.wait:
      return 'Pause for a specified duration';
    case MissionItemType.publish:
      return 'Publish data to a ROS topic';
    case MissionItemType.callService:
      return 'Call a ROS service';
    case MissionItemType.callAction:
      return 'Send a goal to a ROS action';
    case MissionItemType.captureImage:
      return 'Capture an image';
    case MissionItemType.apiCall:
      return 'Make an HTTP API request';
    case MissionItemType.loop:
      return 'Repeat the mission a set number of times, or forever';
  }
}
