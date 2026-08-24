import 'package:flutter/material.dart';

/// The GOTO item picker bottom sheet — "Select from Map" or pick from a
/// saved bookmark. Extracted verbatim from waypoint_panel.dart's
/// `_showGotoOptionsDialog` — pure sheet UI; the caller resolves
/// [bookmarks] itself (from `SettingsProvider.bookmarks[currentMap]`) and
/// handles both taps via the callbacks below, exactly as the original
/// inline `onTap` closures did (`widget.onShowMissionBanner?.call()` for
/// "select from map", `_addBookmarkAsWaypoint(bookmark)` for a bookmark).
void showGotoOptionsSheet(
  BuildContext context, {
  required Color modeColor,
  required List<dynamic> bookmarks,
  required VoidCallback onSelectFromMap,
  required void Function(dynamic bookmark) onBookmarkSelected,
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
              'Add GOTO Waypoint',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),

            // Scrollable content area
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Select from Map option
                    InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        onSelectFromMap();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: modeColor.withOpacity(0.1),
                          border: Border.all(color: modeColor.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.touch_app, color: modeColor, size: 24),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Select from Map',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Long press on map to select position',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios,
                                color: Colors.grey[500], size: 16),
                          ],
                        ),
                      ),
                    ),

                    if (bookmarks.isNotEmpty) ...[
                      SizedBox(height: 16),
                      Text('Or select from bookmarks:',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          )),
                      SizedBox(height: 12),

                      // Bookmarks list
                      Column(
                        children: bookmarks.map<Widget>((bookmark) {
                          return Container(
                            margin: EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                onBookmarkSelected(bookmark);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[800],
                                  border: Border.all(color: Colors.grey[700]!),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: modeColor.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        bookmark.icon,
                                        color: modeColor,
                                        size: 20,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            bookmark.name,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            'X: ${bookmark.positionX.toStringAsFixed(2)}, Y: ${bookmark.positionY.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.add_circle_outline,
                                        color: modeColor, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
