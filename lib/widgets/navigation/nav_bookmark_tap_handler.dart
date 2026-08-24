import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/modals/bookmark.dart';
import 'package:nav2_mission_planner/widgets/bookmarks/bookmark_dialog.dart';
import 'package:nav2_mission_planner/widgets/bookmarks/bookmark_tooltip.dart';

/// Opens the bookmark tooltip (and, from its "Edit" action, the bookmark
/// edit dialog) for a map-marker tap. Extracted verbatim from
/// navigation_screen.dart's `_buildMapWidget`'s `onBookmarkTap` closure —
/// this function owns only the dialog-opening/closing plumbing (every
/// `Navigator.pop()` call that used to live inline). All actual state
/// mutation (removing/updating a bookmark, arming reposition mode) stays
/// the caller's responsibility via the callbacks below, exactly as it did
/// before extraction — this file never touches `setState`,
/// `SettingsProvider`, or `_localBookmarks` directly.
void showBookmarkTapDialog({
  required BuildContext context,
  required Bookmark bookmark,
  required Color modeColor,
  required bool missionMode,
  required VoidCallback onSendGoal,
  required VoidCallback onDock,
  required VoidCallback onUndock,
  required VoidCallback onAddWaypoint,
  required VoidCallback onDelete,
  required void Function(IconData icon, String name, bool isDock) onEditDone,
  required VoidCallback onReposition,
}) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    barrierDismissible: true,
    builder: (context) => BookmarkTooltip(
      bookmark: bookmark,
      modeColor: modeColor,
      isMissionMode: missionMode,
      onSendGoal: () {
        Navigator.of(context).pop();
        onSendGoal();
      },
      onDock: () {
        Navigator.of(context).pop();
        onDock();
      },
      onUndock: () {
        Navigator.of(context).pop();
        onUndock();
      },
      onAddWaypoint: () {
        Navigator.of(context).pop();
        onAddWaypoint();
      },
      onDelete: () {
        Navigator.of(context).pop();
        onDelete();
      },
      onCancel: () {
        Navigator.of(context).pop();
      },
      onEditDetails: () {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => BookmarkDialog(
            isEdit: true,
            initialName: bookmark.name,
            initialIcon: bookmark.icon,
            initialIsDock: bookmark.isDock,
            onDone: (icon, name, isDock) {
              Navigator.pop(context);
              onEditDone(icon, name, isDock);
            },
            onCancel: () => Navigator.pop(context),
          ),
        );
      },
      onReposition: () {
        Navigator.of(context).pop();
        onReposition();
      },
    ),
  );
}
