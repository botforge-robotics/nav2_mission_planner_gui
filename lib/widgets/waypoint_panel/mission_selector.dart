import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../modals/mission.dart';
import '../../providers/branding_provider.dart';

/// The "MISSION" section: a dropdown of saved missions for the current map
/// (plus a "New Mission" entry) and a Save/Delete popup menu. Extracted
/// verbatim from waypoint_panel.dart's inline dropdown+popup block — pure
/// presentation over [missions]/[selectedMission]/[hasMissionItems]. The
/// caller keeps every actual decision: [onMissionChangeRequested] is handed
/// the raw selected value and still runs the full unsaved-changes-confirm
/// -> conditional-save -> proceed-with-change flow the original inline
/// `onChanged` closure did (not duplicated here), and [onSaveSelected]/
/// [onDeleteSelected] map straight onto the original popup menu's
/// `onSelected` branches.
class MissionSelector extends StatelessWidget {
  final String? selectedMission;
  final Color modeColor;
  final Iterable<MapEntry<String, Mission>> missions;
  final bool hasMissionItems;
  final void Function(String? value) onMissionChangeRequested;
  final VoidCallback onSaveSelected;
  final VoidCallback onDeleteSelected;

  const MissionSelector({
    super.key,
    required this.selectedMission,
    required this.modeColor,
    required this.missions,
    required this.hasMissionItems,
    required this.onMissionChangeRequested,
    required this.onSaveSelected,
    required this.onDeleteSelected,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor =
        Provider.of<BrandingProvider>(context, listen: false).themeColor;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: modeColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButtonFormField<String>(
                value: selectedMission,
                hint: Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      color: modeColor,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Select Mission',
                      style: TextStyle(color: Colors.grey[400]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                isExpanded: true,
                dropdownColor: Colors.grey[850],
                icon: Container(
                  decoration: BoxDecoration(
                    color: modeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: modeColor,
                    size: 20,
                  ),
                ),
                decoration: InputDecoration(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  border: InputBorder.none,
                  isDense: true,
                ),
                menuMaxHeight: 400,
                borderRadius: BorderRadius.circular(16),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: 50,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: modeColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.add_circle_outline,
                              color: modeColor,
                              size: 16,
                            ),
                          ),
                          SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'New Mission',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    height: 1.0,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                SizedBox(height: 1),
                                Text(
                                  'Create from current waypoints',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 10,
                                    height: 0.9,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ...missions.map((entry) {
                    final missionName = entry.value.missionName;
                    final waypoints = entry.value.waypoints.length;

                    return DropdownMenuItem(
                      value: missionName,
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 0),
                        constraints: BoxConstraints(
                          maxHeight: 38,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: themeColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.route,
                                color: themeColor,
                                size: 16,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    missionName,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      height: 1.0,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  SizedBox(height: 1),
                                  Text(
                                    '$waypoints waypoints',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 10,
                                      height: 0.9,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
                onChanged: onMissionChangeRequested,
              ),
            ),
          ),
          // Extended dropdown button with actions
          PopupMenuButton<String>(
            icon: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: modeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.more_horiz,
                color: modeColor,
              ),
            ),
            offset: Offset(0, 10),
            color: Colors.grey[850],
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: modeColor.withOpacity(0.2),
                width: 1,
              ),
            ),
            itemBuilder: (context) => [
              if (hasMissionItems)
                PopupMenuItem(
                  value: 'save',
                  height: 56,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: selectedMission != null
                            ? BorderSide(color: Colors.grey[700]!, width: 0.5)
                            : BorderSide.none,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: modeColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.save_outlined,
                            color: modeColor,
                            size: 22,
                          ),
                        ),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Save Mission',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Save current waypoints and settings',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (selectedMission != null)
                PopupMenuItem(
                  value: 'delete',
                  height: 56,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red[400]!.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.delete_outline,
                            color: Colors.red[400],
                            size: 22,
                          ),
                        ),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delete Mission',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Remove this mission permanently',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            onSelected: (value) {
              if (value == 'delete') {
                onDeleteSelected();
              } else if (value == 'save') {
                onSaveSelected();
              }
            },
          ),
        ],
      ),
    );
  }
}
