import 'package:flutter/material.dart';
import '../../providers/ros2_data_provider.dart';

/// Shared bottom-sheet chrome (handle bar, header, scrollable form area,
/// loading overlay) for the publish/service/action/API-call item editors.
/// Extracted verbatim from waypoint_panel.dart's `_buildExpandableItemDialog`
/// + `_getLoadingMessage` — the caller still builds the actual form content
/// via [formBuilder] and passes in whichever `ROS2DataProvider` it already
/// resolved (the loading overlay reads its `isLoading`/`isLoadingTopics`/
/// `isLoadingServices`/`isLoadingActions`/`isLoadingMessageStructure` flags,
/// same as before).
Widget buildExpandableItemDialog({
  required String title,
  required IconData icon,
  required Color color,
  required Widget Function(StateSetter) formBuilder,
  required ROS2DataProvider? provider,
}) {
  return StatefulBuilder(
    builder: (context, setStateDialog) {
      return Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: 700,
          ),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  // Handle bar
                  Container(
                    margin: EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[500],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header with gradient background
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.grey[700]!,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: color.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Icon(icon, color: color, size: 24),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Configure your mission item settings',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.close, color: Colors.grey[400]),
                            tooltip: 'Close',
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Form content with better background
                  Expanded(
                    child: Container(
                      color: Colors.grey[900],
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(24),
                        child: formBuilder(setStateDialog),
                      ),
                    ),
                  ),
                ],
              ),
              // Enhanced loading overlay
              if (provider?.isLoading ?? false)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      margin: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                            strokeWidth: 3,
                          ),
                          SizedBox(height: 12),
                          Text(
                            _loadingMessage(provider),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
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

String _loadingMessage(ROS2DataProvider? provider) {
  if (provider?.isLoadingTopics ?? false) return 'Loading topics...';
  if (provider?.isLoadingServices ?? false) {
    return 'Loading services...';
  }
  if (provider?.isLoadingActions ?? false) {
    return 'Loading action servers...';
  }
  if (provider?.isLoadingMessageStructure ?? false) {
    return 'Loading message structure...';
  }
  return 'Loading...';
}
