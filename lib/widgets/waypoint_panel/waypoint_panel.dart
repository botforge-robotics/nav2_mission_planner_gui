import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/modals/mission.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/ros2_data_provider.dart';
import 'package:nav2_mission_planner/services/message_parser.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import '../duration_selector.dart';
import 'header_toggle.dart';
import 'publish_form.dart';
import 'service_form.dart';
import 'action_form.dart';

class WaypointPanel extends StatefulWidget {
  final List<Waypoint> waypoints;
  final Color modeColor;
  final Function(int) onWaypointSelected;
  final Function(int) onWaypointDeleted;
  final Function(int, int) onWaypointReordered;
  final Function(List<Waypoint>) onWaypointsLoaded;
  final String? currentMap;

  const WaypointPanel({
    super.key,
    required this.waypoints,
    required this.modeColor,
    required this.onWaypointSelected,
    required this.onWaypointDeleted,
    required this.onWaypointReordered,
    required this.onWaypointsLoaded,
    this.currentMap,
  });

  @override
  State<WaypointPanel> createState() => _WaypointPanelState();
}

class _WaypointPanelState extends State<WaypointPanel> {
  String? _selectedMission;
  final TextEditingController _missionNameController = TextEditingController();
  final TextEditingController _missionDescController = TextEditingController();
  String? _missionNameError;
  bool _isLoadingWaypoints = false;
  bool _isCollapsed = false;
  bool _hasUnsavedChanges = false;
  List<MissionItem> _originalItems = [];
  List<MissionItem> _missionItems = [];

  // Add scroll controller for auto-scroll functionality
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  Timer? _dragPositionTimer;
  bool _isDragging = false;

  // Provider for ROS2 data
  ROS2DataProvider? _ros2DataProvider;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  void _initializeServices() {
    final connectionProvider =
        Provider.of<ConnectionProvider>(context, listen: false);
    if (connectionProvider.isConnected) {
      _ros2DataProvider = Provider.of<ROS2DataProvider>(context, listen: false);

      // Initialize data for any saved mission items
      _initializeSavedData();
    }
  }

  Future<void> _initializeSavedData() async {
    if (_missionItems.isEmpty || _ros2DataProvider == null) return;

    try {
      setState(() {
        _isLoadingWaypoints = true;
      });

      // Fetch topics, services, and actions in parallel
      await Future.wait([
        _ros2DataProvider!.fetchTopics(),
        _ros2DataProvider!.fetchServices(),
        _ros2DataProvider!.fetchActionServers(),
      ]);

      // Load message structures for saved items in parallel
      final futures = <Future>[];
      final errors = <String>[];

      for (final item in _missionItems) {
        switch (item.type) {
          case MissionItemType.publish:
            if (item.publishTopic != null && item.publishMsgType != null) {
              try {
                // Check if structure already exists
                if (_ros2DataProvider!
                        .messageStructures[item.publishMsgType!] ==
                    null) {
                  futures.add(_ros2DataProvider!.getMessageStructure(
                      item.publishTopic!, item.publishMsgType!));
                }

                // Validate the message data against the structure once loaded
                futures.add(_validatePublishMessageData(item));
              } catch (e) {
                errors.add(
                    'Error loading structure for topic ${item.publishTopic}: $e');
              }
            }
            break;
          case MissionItemType.callService:
            if (item.serviceName != null && item.serviceType != null) {
              try {
                final key = '${item.serviceType}_request';
                if (_ros2DataProvider!.messageStructures[key] == null) {
                  futures.add(_ros2DataProvider!.getServiceRequestStructure(
                      item.serviceName!, item.serviceType!));
                }

                // Validate the service request data against the structure once loaded
                futures.add(_validateServiceRequestData(item));
              } catch (e) {
                errors.add(
                    'Error loading structure for service ${item.serviceName}: $e');
              }
            }
            break;
          case MissionItemType.callAction:
            if (item.actionName != null && item.actionType != null) {
              try {
                final key = '${item.actionType}_goal';
                if (_ros2DataProvider!.messageStructures[key] == null) {
                  futures.add(_ros2DataProvider!.getActionGoalStructure(
                      item.actionName!, item.actionType!));
                }

                // Validate the action goal data against the structure once loaded
                futures.add(_validateActionGoalData(item));
              } catch (e) {
                errors.add(
                    'Error loading structure for action ${item.actionName}: $e');
              }
            }
            break;
          default:
            break;
        }
      }

      // Wait for all message structure fetches to complete
      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }

      // Show errors if any
      if (errors.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Some mission items may have outdated message structures. Check items for warnings.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error initializing saved data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading mission data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingWaypoints = false;
        });
      }
    }
  }

  // Modify the existing fetch methods to use the provider

  // Validation methods for mission item data
  Future<void> _validatePublishMessageData(MissionItem item) async {
    if (item.publishMsgType == null || item.publishMessage == null) return;

    try {
      // Get the message structure
      final structure =
          _ros2DataProvider?.messageStructures[item.publishMsgType];
      if (structure == null) return;

      // Create default structure for comparison
      final defaultStructure =
          MessageParser.getDefaultValueForStructure(structure);

      // Check if the saved message has all required fields
      bool needsUpdate = false;
      for (final field in defaultStructure.keys) {
        if (!item.publishMessage!.containsKey(field)) {
          // Missing field in saved data
          item.publishMessage![field] = defaultStructure[field];
          needsUpdate = true;
        }
      }

      // Mark item with warning if structure changed
      if (needsUpdate) {
        item.hasStructureWarning = true;
      }
    } catch (e) {
      print('Error validating publish message data: $e');
    }
  }

  Future<void> _validateServiceRequestData(MissionItem item) async {
    if (item.serviceType == null || item.serviceRequest == null) return;

    try {
      // Get the service request structure
      final key = '${item.serviceType}_request';
      final structure = _ros2DataProvider?.messageStructures[key];
      if (structure == null) return;

      // Create default structure for comparison
      final defaultStructure =
          MessageParser.getDefaultValueForStructure(structure);

      // Check if the saved request has all required fields
      bool needsUpdate = false;
      for (final field in defaultStructure.keys) {
        if (!item.serviceRequest!.containsKey(field)) {
          // Missing field in saved data
          item.serviceRequest![field] = defaultStructure[field];
          needsUpdate = true;
        }
      }

      // Mark item with warning if structure changed
      if (needsUpdate) {
        item.hasStructureWarning = true;
      }
    } catch (e) {
      print('Error validating service request data: $e');
    }
  }

  Future<void> _validateActionGoalData(MissionItem item) async {
    if (item.actionType == null || item.actionGoal == null) return;

    try {
      // Get the action goal structure
      final key = '${item.actionType}_goal';
      final structure = _ros2DataProvider?.messageStructures[key];
      if (structure == null) return;

      // Create default structure for comparison
      final defaultStructure =
          MessageParser.getDefaultValueForStructure(structure);

      // Check if the saved goal has all required fields
      bool needsUpdate = false;
      for (final field in defaultStructure.keys) {
        if (!item.actionGoal!.containsKey(field)) {
          // Missing field in saved data
          item.actionGoal![field] = defaultStructure[field];
          needsUpdate = true;
        }
      }

      // Mark item with warning if structure changed
      if (needsUpdate) {
        item.hasStructureWarning = true;
      }
    } catch (e) {
      print('Error validating action goal data: $e');
    }
  }

  @override
  void dispose() {
    _missionNameController.dispose();
    _missionDescController.dispose();
    _scrollController.dispose();
    _autoScrollTimer?.cancel();
    _dragPositionTimer?.cancel();
    super.dispose();
  }

  void _togglePanel() {
    setState(() {
      _isCollapsed = !_isCollapsed;
    });
  }

  int _missionIndexToWaypointIndex(int missionIdx) {
    int wpIdx = 0;
    for (int i = 0; i < missionIdx; i++) {
      if (_missionItems[i].type == MissionItemType.goto) {
        wpIdx++;
      }
    }
    return wpIdx;
  }

  void _handleReorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    setState(() {
      final MissionItem item = _missionItems.removeAt(oldIndex);
      _missionItems.insert(newIndex, item);
      _trackChanges();
    });

    // After any mission-item reorder, notify parent of new waypoint ordering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final orderedWaypoints = _getWaypointsInMissionOrder();
      widget.onWaypointsLoaded(List<Waypoint>.from(orderedWaypoints));
    });
  }

  void _startAutoScroll(double velocity) {
    _autoScrollTimer?.cancel();
    if (!_isDragging || !_scrollController.hasClients) return;

    _autoScrollTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      if (!_isDragging || !_scrollController.hasClients) {
        timer.cancel();
        return;
      }

      final currentPosition = _scrollController.position.pixels;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final newPosition = (currentPosition + velocity).clamp(0.0, maxScroll);

      if ((newPosition - currentPosition).abs() > 0.1) {
        _scrollController.animateTo(
          newPosition,
          duration: Duration(milliseconds: 50),
          curve: Curves.linear,
        );
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _dragPositionTimer?.cancel();
    setState(() {
      _isDragging = false;
    });
  }

  void _startDragPositionTracking() {
    _dragPositionTimer?.cancel();
    _dragPositionTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
      if (!_isDragging) {
        timer.cancel();
        return;
      }

      if (!_scrollController.hasClients) return;

      // Auto-scroll based on list position - scroll toward content
      final scrollPosition = _scrollController.position;
      const scrollSpeed = 3.0;

      // If we have items above the visible area, scroll up
      if (scrollPosition.pixels > 0) {
        _startAutoScroll(-scrollSpeed);
      }
      // If we have items below the visible area, scroll down
      else if (scrollPosition.pixels < scrollPosition.maxScrollExtent) {
        _startAutoScroll(scrollSpeed);
      }
    });
  }

  void _trackChanges() {
    final hasChanges = _missionItems.length != _originalItems.length ||
        !_areItemsEqual(_missionItems, _originalItems);

    if (_hasUnsavedChanges != hasChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
      });
    }
  }

  bool _areItemsEqual(List<MissionItem> list1, List<MissionItem> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].id != list2[i].id ||
          list1[i].type != list2[i].type ||
          list1[i].name != list2[i].name) {
        return false;
      }
    }
    return true;
  }

  void _scrollToBottom() {
    // Auto-scroll will happen automatically with ReorderableListView
  }

  @override
  void didUpdateWidget(WaypointPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waypoints.length < widget.waypoints.length) {
      _scrollToBottom();
    }
    _syncWaypointsToItems();
    _trackChanges();
  }

  void _syncWaypointsToItems() {
    // Create a set of existing waypoint IDs to track what we already have
    final existingWaypointIds = _missionItems
        .where((item) => item.type == MissionItemType.goto)
        .map((item) => item.id)
        .toSet();

    // Find new waypoints that aren't already in the mission items
    final newWaypoints = widget.waypoints
        .where((waypoint) => !existingWaypointIds.contains(waypoint.id))
        .toList();

    // Create mission items for new waypoints only
    final newGotoItems = newWaypoints
        .map((waypoint) => MissionItem(
              id: waypoint.id,
              type: MissionItemType.goto,
              name: waypoint.name,
              position: waypoint.position,
            ))
        .toList();

    // If there are new waypoints, add them to the existing list
    if (newGotoItems.isNotEmpty) {
      setState(() {
        _missionItems.addAll(newGotoItems);
      });
    }

    // Remove any GOTO items that no longer exist in waypoints
    final currentWaypointIds = widget.waypoints.map((w) => w.id).toSet();
    setState(() {
      _missionItems.removeWhere((item) =>
          item.type == MissionItemType.goto &&
          !currentWaypointIds.contains(item.id));
    });
  }

  // Returns the current waypoint list ordered according to the mission items
  List<Waypoint> _getWaypointsInMissionOrder() {
    // Build a lookup map from waypoint id to waypoint instance
    final Map<String?, Waypoint> waypointMap = {
      for (final wp in widget.waypoints) wp.id: wp,
    };

    // Extract the waypoints in the same order as the GOTO mission items
    return _missionItems
        .where((item) => item.type == MissionItemType.goto)
        .map((item) => waypointMap[item.id])
        .whereType<Waypoint>()
        .toList();
  }

  void _showSaveMissionDialog() {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

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
              mainAxisSize: MainAxisSize.min,
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
                  _selectedMission == null
                      ? 'Save New Mission'
                      : 'Update Mission',
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
                      controller: _missionNameController,
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
                          borderSide:
                              BorderSide(color: widget.modeColor, width: 2),
                        ),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                    if (_missionNameError != null) // Show error message
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          _missionNameError!,
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
                      controller: _missionDescController,
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
                          borderSide:
                              BorderSide(color: widget.modeColor, width: 2),
                        ),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                  ],
                ),

                // Map Info
                if (widget.currentMap != null) ...[
                  SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: widget.modeColor.withOpacity(0.1),
                      border:
                          Border.all(color: widget.modeColor.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.map_outlined,
                          color: widget.modeColor,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Map: ${widget.currentMap}',
                          style: TextStyle(
                            color: widget.modeColor,
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
                        onPressed: () => Navigator.pop(context),
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
                        onPressed: () {
                          if (widget.currentMap == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('No map selected for mission'),
                                backgroundColor: Colors.red[600],
                              ),
                            );
                            return;
                          }

                          // Validate mission name
                          if (_missionNameController.text.trim().isEmpty ||
                              _missionNameController.text.trim().length < 4) {
                            setState(() {
                              _missionNameError =
                                  'Mission name must be at least 4 characters long';
                            });
                            return;
                          } else {
                            setState(() {
                              _missionNameError = null; // Clear error if valid
                            });
                          }

                          final mission = Mission(
                            missionName: _missionNameController.text.trim(),
                            missionDescription:
                                _missionDescController.text.trim(),
                            mapName: widget.currentMap!,
                            items: List.from(_missionItems),
                          );
                          settingsProvider.saveMission(mission);

                          // Force mission path repaint by notifying the parent with current ordering
                          final orderedWaypoints =
                              _getWaypointsInMissionOrder();
                          if (orderedWaypoints.isNotEmpty) {
                            widget.onWaypointsLoaded(
                                List<Waypoint>.from(orderedWaypoints));
                          }

                          Navigator.pop(context);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                      'Mission "${mission.missionName}" saved successfully'),
                                ],
                              ),
                              backgroundColor: Colors.green[600],
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.modeColor,
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

  void _showAddItemDialog() {
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
            mainAxisSize: MainAxisSize.min,
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
                        .map((type) => Container(
                              margin: EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () {
                                  Navigator.pop(context);
                                  if (type == MissionItemType.goto) {
                                    _showGotoOptionsDialog();
                                  } else {
                                    _addMissionItem(type);
                                  }
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
                                          borderRadius:
                                              BorderRadius.circular(2),
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
                                              _getTypeDescription(type),
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

  void _showGotoOptionsDialog() {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final bookmarks = widget.currentMap != null
        ? settingsProvider.bookmarks[widget.currentMap!] ?? []
        : <dynamic>[];

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
            mainAxisSize: MainAxisSize.min,
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
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: widget.modeColor.withOpacity(0.1),
                            border: Border.all(
                                color: widget.modeColor.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.touch_app,
                                  color: widget.modeColor, size: 24),
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
                                  _addBookmarkAsWaypoint(bookmark);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[800],
                                    border:
                                        Border.all(color: Colors.grey[700]!),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color:
                                              widget.modeColor.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          bookmark.icon,
                                          color: widget.modeColor,
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
                                          color: widget.modeColor, size: 20),
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

  void _addBookmarkAsWaypoint(dynamic bookmark) {
    // Create a new waypoint and add it to the parent's waypoint list
    final waypoint = Waypoint(
      id: Uuid().v4(),
      events: [],
      position: Position(
        x: bookmark.positionX,
        y: bookmark.positionY,
        theta: bookmark.theta,
      ),
      name: bookmark.name,
    );

    // Add to parent's waypoint list by creating a new list with the waypoint
    final updatedWaypoints = List<Waypoint>.from(widget.waypoints)
      ..add(waypoint);
    widget.onWaypointsLoaded(updatedWaypoints);
  }

  String _getTypeDescription(MissionItemType type) {
    switch (type) {
      case MissionItemType.goto:
        return 'Navigate to a specific position';
      case MissionItemType.wait:
        return 'Pause for a specified duration';
      case MissionItemType.publish:
        return 'Publish data to a ROS topic';
      case MissionItemType.callService:
        return 'Call a ROS service';
      case MissionItemType.callAction:
        return 'Send a goal to a ROS action';
    }
  }

  void _addMissionItem(MissionItemType type) {
    // Count existing items of this specific type
    final typeCount =
        _missionItems.where((item) => item.type == type).length + 1;

    final newItem = MissionItem(
      id: Uuid().v4(),
      type: type,
      name: '${type.displayName} $typeCount',
      waitDuration: type == MissionItemType.wait ? 5.0 : null,
      publishTopic: type == MissionItemType.publish ? '/example_topic' : null,
      serviceName:
          type == MissionItemType.callService ? '/example_service' : null,
      actionName: type == MissionItemType.callAction ? '/example_action' : null,
      waitForServiceResponse: type == MissionItemType.callService ? true : null,
      waitForActionResult: type == MissionItemType.callAction ? true : null,
      publishMessage: type == MissionItemType.publish ? {} : null,
      publishMsgType: type == MissionItemType.publish ? '' : null,
    );

    setState(() {
      _missionItems.add(newItem);
      _trackChanges();
    });
  }

  void _deleteMissionItem(int index) {
    setState(() {
      _missionItems.removeAt(index);
      _trackChanges();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return AnimatedContainer(
      duration: Duration(milliseconds: 300), // Animation duration
      curve: Curves.easeInOut, // Animation curve
      width: 300,
      height:
          _isCollapsed ? 72 : screenHeight - 50, // Full height when expanded
      decoration: BoxDecoration(
        color: Colors.grey[900],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Spacer when expanded to push content to bottom
          if (!_isCollapsed)
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 16),
                      // Mission Controls
                      Text(
                        'MISSION',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.modeColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: DropdownButtonFormField<String>(
                                  value: _selectedMission,
                                  hint: Text(
                                    'Select Mission',
                                    style: TextStyle(color: Colors.grey[400]),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  isExpanded: true,
                                  dropdownColor: Colors.grey[800],
                                  icon: Icon(Icons.keyboard_arrow_down,
                                      color: widget.modeColor),
                                  decoration: InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 12),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: null,
                                      child: Row(
                                        children: [
                                          Icon(Icons.add_circle_outline,
                                              color: widget.modeColor,
                                              size: 18),
                                          SizedBox(width: 8),
                                          Text('New Mission',
                                              style: TextStyle(
                                                  color: Colors.white)),
                                        ],
                                      ),
                                    ),
                                    ...settingsProvider.missions.entries
                                        .where((entry) =>
                                            entry.value.mapName ==
                                            widget.currentMap)
                                        .map((entry) {
                                      return DropdownMenuItem(
                                        value: entry.value.missionName,
                                        child: Text(
                                          entry.value.missionName,
                                          style: TextStyle(
                                              color: Colors.white,
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                  onChanged: (value) async {
                                    if (_hasUnsavedChanges &&
                                        _selectedMission != null) {
                                      final result = await showDialog<String>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: Colors.grey[900],
                                          title: Text(
                                            'Unsaved Changes',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          content: Text(
                                            'You have unsaved changes to this mission. Do you want to save them?',
                                            style: TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(
                                                  context, 'discard'),
                                              child: Text(
                                                'Discard',
                                                style: TextStyle(
                                                  color: Colors.red[400],
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(
                                                  context, 'save'),
                                              child: Text(
                                                'Save',
                                                style: TextStyle(
                                                  color: widget.modeColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (result == 'save') {
                                        // Save the current mission first
                                        if (widget.currentMap != null &&
                                            _missionNameController.text
                                                .trim()
                                                .isNotEmpty) {
                                          final mission = Mission(
                                            missionName: _missionNameController
                                                .text
                                                .trim(),
                                            missionDescription:
                                                _missionDescController.text
                                                    .trim(),
                                            mapName: widget.currentMap!,
                                            items: List.from(_missionItems),
                                          );
                                          final settingsProvider =
                                              Provider.of<SettingsProvider>(
                                                  context,
                                                  listen: false);
                                          settingsProvider.saveMission(mission);

                                          // Force mission path repaint by notifying the parent with current ordering
                                          final orderedWaypoints =
                                              _getWaypointsInMissionOrder();
                                          if (orderedWaypoints.isNotEmpty) {
                                            widget.onWaypointsLoaded(
                                                List<Waypoint>.from(
                                                    orderedWaypoints));
                                          }
                                        }

                                        // Now proceed with the new selection
                                        _proceedWithMissionChange(value);
                                        return;
                                      } else if (result == 'discard') {
                                        // Discard changes and proceed with new selection
                                        _proceedWithMissionChange(value);
                                        return;
                                      } else {
                                        return; // Dialog was dismissed, don't change mission
                                      }
                                    }

                                    // No unsaved changes, proceed normally
                                    _proceedWithMissionChange(value);
                                  },
                                ),
                              ),
                            ),
                            if (_selectedMission != null)
                              Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: Colors.grey[700]!,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.red[600]!,
                                        Colors.red[600]!.withOpacity(0.8)
                                      ],
                                    ),
                                  ),
                                  child: IconButton(
                                    icon: Icon(Icons.delete,
                                        color: Colors.white, size: 18),
                                    onPressed: _confirmDeleteMission,
                                    tooltip: 'Delete Mission',
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints.tightFor(
                                        width: 40, height: 40),
                                  ),
                                ),
                              ),
                            if (_missionItems.isNotEmpty)
                              Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: Colors.grey[700]!,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        widget.modeColor,
                                        widget.modeColor.withOpacity(0.8)
                                      ],
                                    ),
                                    borderRadius: BorderRadius.only(
                                      topRight: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                    ),
                                  ),
                                  child: IconButton(
                                    icon: Icon(Icons.save,
                                        color: Colors.white, size: 18),
                                    onPressed: _showSaveMissionDialog,
                                    tooltip: 'Save Mission',
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints.tightFor(
                                        width: 40, height: 40),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: 20),

                      // Mission Items List
                      _missionItems.isEmpty
                          ? Center(
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
                            )
                          : ReorderableListView(
                              scrollController: _scrollController,
                              shrinkWrap: true,
                              physics: ClampingScrollPhysics(),
                              onReorder: _handleReorder,
                              buildDefaultDragHandles: false,
                              onReorderStart: (index) {
                                setState(() {
                                  _isDragging = true;
                                });
                                _startDragPositionTracking();
                              },
                              onReorderEnd: (index) {
                                _stopAutoScroll();
                              },
                              children: [
                                for (int index = 0;
                                    index < _missionItems.length;
                                    index++)
                                  Dismissible(
                                    key: Key(_missionItems[index].id!),
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
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, false),
                                                  child: Text(
                                                    'Cancel',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, true),
                                                  child: Text(
                                                    'Delete',
                                                    style: TextStyle(
                                                      color: Colors.red[400],
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ) ??
                                          false;
                                    },
                                    onDismissed: (direction) {
                                      final item = _missionItems[index];
                                      if (item.type == MissionItemType.goto) {
                                        // For GOTO items, find the corresponding waypoint index and delete it from parent
                                        final waypointIndex = widget.waypoints
                                            .indexWhere((waypoint) =>
                                                waypoint.id == item.id);
                                        if (waypointIndex != -1) {
                                          widget
                                              .onWaypointDeleted(waypointIndex);
                                        }
                                      }
                                      _deleteMissionItem(index);
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[800],
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: Colors.grey[700]!),
                                      ),
                                      child: Row(
                                        children: [
                                          // Type color bar
                                          Container(
                                            width: 4,
                                            height: 70,
                                            decoration: BoxDecoration(
                                              color: _missionItems[index]
                                                  .type
                                                  .color,
                                              borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(16),
                                                bottomLeft: Radius.circular(16),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: ListTile(
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 8),
                                              leading: Stack(
                                                children: [
                                                  Container(
                                                    width: 40,
                                                    height: 40,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          _missionItems[index]
                                                              .type
                                                              .color
                                                              .withOpacity(0.2),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    child: Center(
                                                      child: Icon(
                                                        _missionItems[index]
                                                            .type
                                                            .icon,
                                                        color:
                                                            _missionItems[index]
                                                                .type
                                                                .color,
                                                        size: 20,
                                                      ),
                                                    ),
                                                  ),
                                                  // Warning badge for structure changes
                                                  if (_missionItems[index]
                                                      .hasStructureWarning)
                                                    Positioned(
                                                      right: 0,
                                                      bottom: 0,
                                                      child: Container(
                                                        width: 16,
                                                        height: 16,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.amber,
                                                          shape:
                                                              BoxShape.circle,
                                                          border: Border.all(
                                                            color: Colors
                                                                .grey[800]!,
                                                            width: 1.5,
                                                          ),
                                                        ),
                                                        child: Center(
                                                          child: Icon(
                                                            Icons.warning,
                                                            color: Colors
                                                                .grey[900],
                                                            size: 10,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              title: Row(
                                                children: [
                                                  Text(
                                                    _missionItems[index]
                                                        .type
                                                        .displayName,
                                                    style: TextStyle(
                                                      color:
                                                          _missionItems[index]
                                                              .type
                                                              .color,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      _missionItems[index]
                                                          .displayTitle,
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  // Warning icon for structure changes
                                                  if (_missionItems[index]
                                                      .hasStructureWarning)
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
                                              subtitle: Text(
                                                _missionItems[index].subtitle,
                                                style: TextStyle(
                                                  color: Colors.grey[400],
                                                  fontSize: 12,
                                                ),
                                              ),
                                              trailing:
                                                  ReorderableDragStartListener(
                                                index: index,
                                                child: Icon(Icons.drag_handle,
                                                    color: Colors.grey[500]),
                                              ),
                                              onTap: () {
                                                switch (
                                                    _missionItems[index].type) {
                                                  case MissionItemType.wait:
                                                    _showDurationPicker(
                                                        context, index);
                                                    break;
                                                  case MissionItemType.publish:
                                                    _showPublishItemDialog(
                                                        context, index);
                                                    break;
                                                  case MissionItemType
                                                        .callService:
                                                    _showServiceItemDialog(
                                                        context, index);
                                                    break;
                                                  case MissionItemType
                                                        .callAction:
                                                    _showActionItemDialog(
                                                        context, index);
                                                    break;
                                                  default:
                                                    break;
                                                }
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                      SizedBox(height: 20),

                      // Loading Indicator
                      if (_isLoadingWaypoints) ...[
                        Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    widget.modeColor),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Loading mission...',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 20),
                      ],

                      // Add Mission Item Button
                      GestureDetector(
                        onTap: _showAddItemDialog,
                        child: Container(
                          height: 50,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: widget.modeColor.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Add Mission Item',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),

          // Fixed Header at bottom (always visible)
          HeaderToggle(
            isCollapsed: _isCollapsed,
            modeColor: widget.modeColor,
            onToggle: _togglePanel,
          ),
        ],
      ),
    );
  }

  void _proceedWithMissionChange(String? value) async {
    setState(() {
      _selectedMission = value;
      if (value == null) {
        // New Mission selected - clear everything
        _missionItems.clear();
        widget.onWaypointsLoaded([]); // Clear waypoints from map
        _missionNameController.clear();
        _missionDescController.clear();
        _originalItems = [];
        _hasUnsavedChanges = false;
      } else {
        _isLoadingWaypoints = true;
      }
    });

    if (value != null) {
      // Loading existing mission
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      final mission = settingsProvider.missions.entries
          .where((entry) =>
              entry.value.mapName == widget.currentMap &&
              entry.value.missionName == value)
          .firstOrNull
          ?.value;

      if (mission != null) {
        _missionNameController.text = mission.missionName;
        _missionDescController.text = mission.missionDescription;
        _missionItems = List<MissionItem>.from(mission.items);
        _originalItems = List<MissionItem>.from(mission.items);

        // Load waypoints to map (only GOTO items)
        final waypoints = mission.waypoints;
        widget.onWaypointsLoaded(waypoints);
        _hasUnsavedChanges = false;

        // Initialize message structures for loaded mission items
        await _initializeSavedData();
      } else {
        setState(() {
          _isLoadingWaypoints = false;
        });
      }
    }
  }

  void _confirmDeleteMission() {
    if (_selectedMission == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          'Delete Mission',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "$_selectedMission"?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMission();
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Colors.red[400]),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteMission() {
    if (_selectedMission == null || widget.currentMap == null) return;

    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    settingsProvider.deleteMission(widget.currentMap!, _selectedMission!);

    setState(() {
      _selectedMission = null;
      _missionNameController.clear();
      _missionDescController.clear();
      _originalItems = [];
      _missionItems = [];
      _hasUnsavedChanges = false;
    });

    // Clear waypoints from map
    widget.onWaypointsLoaded([]);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mission "$_selectedMission" deleted'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showDurationPicker(BuildContext context, int index) async {
    final initialDuration = Duration(
      seconds: _missionItems[index].waitDuration?.toInt() ?? 5,
    );

    Duration selectedDuration = initialDuration;

    final pickedDuration = await showDialog<Duration>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Set Wait Duration',
            style: TextStyle(color: Colors.white),
          ),
          contentPadding: EdgeInsets.all(16),
          content: SizedBox(
            width: 300,
            height: 300,
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                      primary: widget.modeColor,
                      surface: Colors.grey[800],
                    ),
              ),
              child: DurationPicker(
                duration: selectedDuration,
                baseUnit: BaseUnit.second,
                modeColor: widget.modeColor,
                onChange: (newDuration) {
                  setState(() {
                    selectedDuration = newDuration;
                  });
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, selectedDuration);
              },
              child: Text('OK', style: TextStyle(color: widget.modeColor)),
            ),
          ],
        ),
      ),
    );

    if (pickedDuration != null) {
      setState(() {
        _missionItems[index].waitDuration = pickedDuration.inSeconds.toDouble();
        _trackChanges();
      });
    }
  }

  void _showPublishItemDialog(BuildContext context, int index) {
    final item = _missionItems[index];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildExpandableItemDialog(
        'Configure Publish',
        Icons.publish,
        MissionItemType.publish.color,
        (setStateDialog) => _buildPublishForm(item, index, setStateDialog),
      ),
    );
  }

  void _showServiceItemDialog(BuildContext context, int index) {
    final item = _missionItems[index];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildExpandableItemDialog(
        'Configure Service',
        Icons.settings,
        MissionItemType.callService.color,
        (setStateDialog) => _buildServiceForm(item, index, setStateDialog),
      ),
    );
  }

  void _showActionItemDialog(BuildContext context, int index) {
    final item = _missionItems[index];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildExpandableItemDialog(
        'Configure Action',
        Icons.play_arrow,
        MissionItemType.callAction.color,
        (setStateDialog) => _buildActionForm(item, index, setStateDialog),
      ),
    );
  }

  Widget _buildExpandableItemDialog(String title, IconData icon, Color color,
      Widget Function(StateSetter) formBuilder) {
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
                  mainAxisSize: MainAxisSize.min,
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
                if (_ros2DataProvider?.isLoading ?? false)
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
                        padding: EdgeInsets.all(24),
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
                            SizedBox(height: 16),
                            Text(
                              _getLoadingMessage(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
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

  String _getLoadingMessage() {
    if (_ros2DataProvider?.isLoadingTopics ?? false) return 'Loading topics...';
    if (_ros2DataProvider?.isLoadingServices ?? false) {
      return 'Loading services...';
    }
    if (_ros2DataProvider?.isLoadingActions ?? false) {
      return 'Loading action servers...';
    }
    if (_ros2DataProvider?.isLoadingMessageStructure ?? false) {
      return 'Loading message structure...';
    }
    return 'Loading...';
  }

  Widget _buildPublishForm(
      MissionItem item, int index, StateSetter setStateDialog) {
    if (_ros2DataProvider == null) return const SizedBox();

    return PublishForm(
      item: item,
      index: index,
      provider: _ros2DataProvider!,
      modeColor: MissionItemType.publish.color,
      onChanged: () {
        _trackChanges();
        setStateDialog(() {});
      },
    );
  }

  Widget _buildServiceForm(
      MissionItem item, int index, StateSetter setStateDialog) {
    if (_ros2DataProvider == null) return const SizedBox();

    return ServiceForm(
      item: item,
      provider: _ros2DataProvider!,
      modeColor: MissionItemType.callService.color,
      onChanged: () {
        _trackChanges();
        setStateDialog(() {});
      },
    );
  }

  Widget _buildActionForm(
      MissionItem item, int index, StateSetter setStateDialog) {
    if (_ros2DataProvider == null) return const SizedBox();

    return ActionForm(
      item: item,
      provider: _ros2DataProvider!,
      modeColor: MissionItemType.callAction.color,
      onChanged: () {
        _trackChanges();
        setStateDialog(() {});
      },
    );
  }
}
