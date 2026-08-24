import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/modals/bookmark.dart';
import 'package:nav2_mission_planner/services/docking_service.dart';

/// Dock/undock FAB — always reachable here rather than only via the dock
/// bookmark's map tooltip. Reflects DockingService's own state, which
/// mirrors dock_manager_node's /dock_status — that topic is the actual
/// source of truth (robot-side, survives an app restart or a different
/// client entirely), this button is just a reactive view onto it, same as
/// the bookmark tooltip's own Dock/Undock button.
///
/// Extracted verbatim from navigation_screen.dart's build() — reads
/// DockingService.instance directly (same AnimatedBuilder pattern already
/// used by BookmarkTooltip elsewhere in the app), takes the dock bookmark
/// and the two action callbacks from the caller.
class DockUndockFab extends StatelessWidget {
  final Bookmark? dockBookmark;
  final VoidCallback onDock;
  final VoidCallback onUndock;

  const DockUndockFab({
    super.key,
    required this.dockBookmark,
    required this.onDock,
    required this.onUndock,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DockingService.instance,
      builder: (context, _) {
        final docking = DockingService.instance;
        // Nothing to dock at yet, and nothing to undock from (in-place
        // undock doesn't need a bookmark) — hide rather than show a button
        // that can only fail.
        if (dockBookmark == null && !docking.isDocked) {
          return const SizedBox.shrink();
        }
        final busy = docking.isBusy;
        final docked = docking.isDocked;
        return FloatingActionButton(
          mini: true,
          tooltip: busy ? 'Docking…' : (docked ? 'Undock' : 'Dock'),
          backgroundColor: docked ? Colors.orange[800] : Colors.green[700],
          onPressed: busy
              ? null
              : (docked ? onUndock : (dockBookmark != null ? onDock : null)),
          child: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(docked ? Icons.eject : Icons.ev_station,
                  color: Colors.white),
        );
      },
    );
  }
}
