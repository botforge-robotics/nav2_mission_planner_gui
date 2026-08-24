import 'package:flutter/material.dart';
import '../../modals/mission.dart';

/// The mission-item list: empty state, or a reorderable, swipe-to-delete
/// list of mission-item cards. Extracted verbatim from waypoint_panel.dart's
/// build() — pure render over [items]; drag state (`_isDragging`,
/// auto-scroll-while-dragging) stays owned by the caller and is only
/// notified via [onReorderStart]/[onReorderEnd], same as the original
/// inline `ReorderableListView` callbacks. Tapping a card and confirming a
/// swipe-delete both report back through a single index-taking callback
/// ([onItemTap]/[onDeleteConfirmed]) rather than duplicating the
/// dispatch/deletion logic here — the caller still owns exactly what
/// happens (which `_show*ItemDialog` opens, the goto-item
/// waypoint-index-lookup on delete), unchanged.
class MissionItemList extends StatelessWidget {
  final List<MissionItem> items;
  final ScrollController scrollController;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onReorderStart;
  final VoidCallback onReorderEnd;
  final void Function(int index) onItemTap;
  final void Function(int index) onDeleteConfirmed;

  const MissionItemList({
    super.key,
    required this.items,
    required this.scrollController,
    required this.onReorder,
    required this.onReorderStart,
    required this.onReorderEnd,
    required this.onItemTap,
    required this.onDeleteConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        height: 200, // Fixed height for empty state
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.list_alt,
                size: 48,
                color: Colors.grey[600],
              ),
              SizedBox(height: 12),
              Text(
                'No mission items yet',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Add items to build your mission',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ReorderableListView(
      scrollController: scrollController,
      shrinkWrap: true,
      physics: ClampingScrollPhysics(),
      onReorder: onReorder,
      buildDefaultDragHandles: false,
      onReorderStart: (index) => onReorderStart(),
      onReorderEnd: (index) => onReorderEnd(),
      children: [
        for (int index = 0; index < items.length; index++)
          Dismissible(
            key: Key(items[index].id!),
            direction: DismissDirection.endToStart,
            background: Container(
              decoration: BoxDecoration(
                color: Colors.red[600],
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.centerRight,
              padding: EdgeInsets.only(right: 20),
              child: Icon(
                Icons.delete,
                color: Colors.white,
              ),
            ),
            confirmDismiss: (direction) async {
              return await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: Colors.grey[900],
                      title: Text(
                        'Confirm Deletion',
                        style: TextStyle(
                          color: Colors.white,
                        ),
                      ),
                      content: Text(
                        'Are you sure you want to delete this mission item?',
                        style: TextStyle(
                          color: Colors.white70,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(
                            'Delete',
                            style: TextStyle(
                              color: Colors.red[400],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            },
            onDismissed: (direction) => onDeleteConfirmed(index),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: Row(
                children: [
                  // Type color bar
                  Container(
                    width: 4,
                    height: 60,
                    decoration: BoxDecoration(
                      color: items[index].type.color,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding:
                          EdgeInsets.only(left: 0, right: 8, top: 8, bottom: 8),
                      child: GestureDetector(
                        onTap: () => onItemTap(index),
                        child: Container(
                          height: 60,
                          child: Row(
                            children: [
                              SizedBox(width: 8),
                              // Icon with warning badge
                              Stack(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: items[index]
                                          .type
                                          .color
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        items[index].type.icon,
                                        color: items[index].type.color,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  // Warning badge for structure changes
                                  if (items[index].hasStructureWarning)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: Colors.amber,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.grey[800]!,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.warning,
                                            color: Colors.grey[900],
                                            size: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              SizedBox(width: 12),
                              // Text content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        // Item type with color
                                        Text(
                                          items[index].type.displayName,
                                          style: TextStyle(
                                            color: items[index].type.color,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            items[index].displayTitle,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Warning icon for structure changes
                                        if (items[index].hasStructureWarning)
                                          Tooltip(
                                            message:
                                                'Message structure has changed since last save',
                                            child: Icon(
                                              Icons.warning_amber,
                                              color: Colors.amber,
                                              size: 16,
                                            ),
                                          ),
                                      ],
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      items[index].subtitle,
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Drag handle
                              ReorderableDragStartListener(
                                index: index,
                                child: Icon(
                                  Icons.drag_handle,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
