import 'package:flutter/material.dart';

/// The "Save Mission" bottom sheet: name/description fields, a current-map
/// info chip, Cancel/Save actions. Extracted verbatim from
/// waypoint_panel.dart's `_showSaveMissionDialog` — pure sheet UI; the
/// caller ([onCancel]/[onSave]) still owns all of the actual behavior
/// (name-length validation + setting the error message, constructing and
/// saving the `Mission`, notifying the parent of reordered waypoints,
/// popping the sheet, showing the result snackbar), unchanged.
///
/// [missionNameError] is a snapshot taken when the sheet opens, not a live
/// binding — this matches the original: `_showSaveMissionDialog`'s
/// `builder` closure read `_missionNameError` directly on a `State` field,
/// but `showModalBottomSheet`'s `builder` isn't rebuilt by the parent's
/// `setState()` calls (it's pushed as its own route), so the error text
/// already didn't live-update after a failed validation in the original
/// code either. Preserved as-is rather than "fixed" as a side effect of
/// this extraction — worth revisiting deliberately, not silently, if it
/// should actually update live (e.g. by wrapping this in a
/// `StatefulBuilder` the way `mission_item_dialogs.dart`'s chrome does).
void showSaveMissionSheet(
  BuildContext context, {
  required TextEditingController nameController,
  required TextEditingController descController,
  required String? missionNameError,
  required String? currentMap,
  required Color modeColor,
  required bool isUpdate,
  required VoidCallback onCancel,
  required VoidCallback onSave,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        width: 400,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: EdgeInsets.all(24),
        child: SingleChildScrollView(
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
              SizedBox(height: 20),

              // Title
              Text(
                isUpdate ? 'Update Mission' : 'Save New Mission',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 24),

              // Mission Name Field
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mission Name',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Enter mission name',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: modeColor, width: 2),
                      ),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                  ),
                  if (missionNameError != null) // Show error message
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        missionNameError,
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 20),

              // Description Field
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Description',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    style: TextStyle(color: Colors.white),
                    maxLines: 2, // Decrease height by limiting lines
                    decoration: InputDecoration(
                      hintText: 'Enter mission description (optional)',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: modeColor, width: 2),
                      ),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                  ),
                ],
              ),

              // Map Info
              if (currentMap != null) ...[
                SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: modeColor.withOpacity(0.1),
                    border: Border.all(color: modeColor.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.map_outlined,
                        color: modeColor,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Map: $currentMap',
                        style: TextStyle(
                          color: modeColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: onCancel,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[600]!),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: modeColor,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        'Save Mission',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  );
}
