import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/modals/mission.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/ros2_data_provider.dart';
import 'package:nav2_mission_planner/providers/branding_provider.dart';
import 'package:nav2_mission_planner/services/message_parser.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import '../duration_selector.dart';
// Removed header_toggle import - no longer using collapsible functionality
import 'publish_form.dart';
import 'service_form.dart';
import 'action_form.dart';
import 'api_call_form.dart';
import 'mission_item_dialogs.dart';
import 'add_mission_item_sheet.dart';
import 'goto_options_sheet.dart';
import 'mission_item_list.dart';
import 'save_mission_sheet.dart';
import 'mission_selector.dart';
import 'package:nav2_mission_planner/services/mission_execution_service.dart';

class WaypointPanel extends StatefulWidget {
  final List<Waypoint> waypoints;
  final Color modeColor;
  final Function(int) onWaypointSelected;
  final Function(int) onWaypointDeleted;
  final Function(int, int) onWaypointReordered;
  final Function(List<Waypoint>) onWaypointsLoaded;
  final String? currentMap;
  final VoidCallback? onShowMissionBanner;
  final Position? robotPosition;
  final VoidCallback? onMissionItemsChanged;

  const WaypointPanel({
    super.key,
    required this.waypoints,
    required this.modeColor,
    required this.onWaypointSelected,
    required this.onWaypointDeleted,
    required this.onWaypointReordered,
    required this.onWaypointsLoaded,
    this.currentMap,
    this.onShowMissionBanner,
    this.robotPosition,
    this.onMissionItemsChanged,
  });

  @override
  State<WaypointPanel> createState() => WaypointPanelState();
}

class WaypointPanelState extends State<WaypointPanel> {
  String? _selectedMission;
  final TextEditingController _missionNameController = TextEditingController();
  final TextEditingController _missionDescController = TextEditingController();
  String? _missionNameError;
  bool _isLoadingWaypoints = false;
  // Removed _isCollapsed - panel is now always expanded
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

    // Listen for mission execution status changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final missionService =
          Provider.of<MissionExecutionService>(context, listen: false);
      missionService.addListener(_handleMissionStateChange);
    });
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
                if (item.actionType!.isEmpty) {
                  errors.add(
                      'Action type is empty for action ${item.actionName}');
                } else {
                  final key = '${item.actionType}_goal';
                  if (_ros2DataProvider!.messageStructures[key] == null) {
                    futures.add(_ros2DataProvider!.getActionGoalStructure(
                        item.actionName!, item.actionType!));
                  }

                  // Validate the action goal data against the structure once loaded
                  futures.add(_validateActionGoalData(item));
                }
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
            backgroundColor: Colors.yellow.withOpacity(0.9),
            duration: Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      // Error initializing saved data handled silently
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading mission data: $e'),
            backgroundColor: Colors.red.withOpacity(0.9),
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
      // Error validating publish message data handled silently
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
      // Error validating service request data handled silently
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
      // Error validating action goal data handled silently
    }
  }

  @override
  void dispose() {
    // Remove mission execution listener
    try {
      Provider.of<MissionExecutionService>(context, listen: false)
          .removeListener(_handleMissionStateChange);
    } catch (e) {
      // Ignore if provider is not available during disposal
    }

    _missionNameController.dispose();
    _missionDescController.dispose();
    _scrollController.dispose();
    _autoScrollTimer?.cancel();
    _dragPositionTimer?.cancel();
    super.dispose();
  }

  // Removed _togglePanel method - panel is now always expanded

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

  // Dispatches a mission-item card tap to the right per-type editor sheet.
  // Extracted out of the ReorderableListView's inline onTap when the list
  // itself moved into MissionItemList.
  void _handleMissionItemTap(int index) {
    switch (_missionItems[index].type) {
      case MissionItemType.wait:
        _showDurationPicker(context, index);
        break;
      case MissionItemType.publish:
        _showPublishItemDialog(context, index);
        break;
      case MissionItemType.callService:
        _showServiceItemDialog(context, index);
        break;
      case MissionItemType.callAction:
        _showActionItemDialog(context, index);
        break;
      case MissionItemType.apiCall:
        _showApiCallItemDialog(context, index);
        break;
      case MissionItemType.loop:
        _showLoopItemDialog(context, index);
        break;
      default:
        break;
    }
  }

  // Extracted out of the Dismissible's inline onDismissed for the same
  // reason as above — goto items also need their corresponding parent
  // waypoint removed.
  void _handleMissionItemDeleteConfirmed(int index) {
    final item = _missionItems[index];
    if (item.type == MissionItemType.goto) {
      // For GOTO items, find the corresponding waypoint index and delete it from parent
      final waypointIndex =
          widget.waypoints.indexWhere((waypoint) => waypoint.id == item.id);
      if (waypointIndex != -1) {
        widget.onWaypointDeleted(waypointIndex);
      }
    }
    _deleteMissionItem(index);
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
    showSaveMissionSheet(
      context,
      nameController: _missionNameController,
      descController: _missionDescController,
      missionNameError: _missionNameError,
      currentMap: widget.currentMap,
      modeColor: widget.modeColor,
      isUpdate: _selectedMission != null,
      onCancel: () => Navigator.pop(context),
      onSave: _handleSaveMission,
    );
  }

  void _handleSaveMission() {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

    if (widget.currentMap == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No map selected for mission'),
          backgroundColor: Colors.red.withOpacity(0.9),
        ),
      );
      return;
    }

    // Validate mission name
    if (_missionNameController.text.trim().isEmpty ||
        _missionNameController.text.trim().length < 4) {
      setState(() {
        _missionNameError = 'Mission name must be at least 4 characters long';
      });
      return;
    } else {
      setState(() {
        _missionNameError = null; // Clear error if valid
      });
    }

    final mission = Mission(
      missionName: _missionNameController.text.trim(),
      missionDescription: _missionDescController.text.trim(),
      mapName: widget.currentMap!,
      items: List.from(_missionItems),
    );
    settingsProvider.saveMission(mission);

    // Force mission path repaint by notifying the parent with current ordering
    final orderedWaypoints = _getWaypointsInMissionOrder();
    if (orderedWaypoints.isNotEmpty) {
      widget.onWaypointsLoaded(List<Waypoint>.from(orderedWaypoints));
    }

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Mission "${mission.missionName}" saved successfully'),
          ],
        ),
        backgroundColor: Colors.green.withOpacity(0.9),
      ),
    );
  }

  void _showAddItemDialog() {
    showAddMissionItemSheet(context, onTypeSelected: _handleAddItemType);
  }

  Future<void> _handleAddItemType(MissionItemType type) async {
    if (type == MissionItemType.goto) {
      // Special handling for GOTO
      _showGotoOptionsDialog();
      return;
    }
    // Delay until the sheet is closed before opening the config sheet
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    final newIndex = _addMissionItem(type);

    // Open the appropriate configuration sheet immediately
    switch (type) {
      case MissionItemType.publish:
        _showPublishItemDialog(context, newIndex);
        break;
      case MissionItemType.callService:
        _showServiceItemDialog(context, newIndex);
        break;
      case MissionItemType.callAction:
        _showActionItemDialog(context, newIndex);
        break;
      case MissionItemType.apiCall:
        _showApiCallItemDialog(context, newIndex);
        break;
      case MissionItemType.loop:
        _showLoopItemDialog(context, newIndex);
        break;
      default:
        break;
    }
  }

  void _showGotoOptionsDialog() {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final bookmarks = widget.currentMap != null
        ? settingsProvider.bookmarks[widget.currentMap!] ?? []
        : <dynamic>[];

    showGotoOptionsSheet(
      context,
      modeColor: widget.modeColor,
      bookmarks: bookmarks,
      onSelectFromMap: () {
        // Show mission banner when selecting from map
        widget.onShowMissionBanner?.call();
      },
      onBookmarkSelected: _addBookmarkAsWaypoint,
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

  /// Adds a new [MissionItem] and returns the index at which it was inserted.
  int _addMissionItem(MissionItemType type) {
    // Count existing items of this specific type to give incremental names
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
      apiUrl: type == MissionItemType.apiCall ? 'https://' : null,
      apiMethod: type == MissionItemType.apiCall ? 'POST' : null,
      apiBody: type == MissionItemType.apiCall ? '{}' : null,
      apiWaitForResponse: type == MissionItemType.apiCall ? true : null,
      loopCount: type == MissionItemType.loop ? 1 : null,
      loopForever: type == MissionItemType.loop ? false : null,
    );

    final int insertIndex =
        _missionItems.length; // index where the item will be inserted

    setState(() {
      _missionItems.add(newItem);
      _trackChanges();
    });

    // Notify parent that mission items have changed
    widget.onMissionItemsChanged?.call();

    return insertIndex;
  }

  void _deleteMissionItem(int index) {
    setState(() {
      _missionItems.removeAt(index);
      _trackChanges();
    });

    // Notify parent that mission items have changed
    widget.onMissionItemsChanged?.call();
  }

  bool hasMissionItems() {
    return _missionItems.isNotEmpty;
  }

  Widget _buildClearAllButton() {
    if (_missionItems.isEmpty) return SizedBox.shrink();

    return Container(
      alignment: Alignment.centerRight,
      child: IconButton(
        onPressed: _showClearAllConfirmation,
        icon: Icon(
          Icons.clear_all,
          color:
              Provider.of<BrandingProvider>(context, listen: false).themeColor,
          size: 24,
        ),
        tooltip: 'Clear All Mission Items',
        padding: EdgeInsets.zero,
      ),
    );
  }

  void _showClearAllConfirmation() {
    showDialog(
      context: context,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400, // Much more compact width
        ),
        child: AlertDialog(
          backgroundColor: Colors.grey[850],
          title: Text(
            'Clear All Items',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: Text(
            'Remove all mission items?',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // Clear all mission items
                setState(() {
                  _missionItems.clear();
                  _originalItems.clear();
                  _hasUnsavedChanges = false;
                });
                // Clear all waypoints from map
                widget.onWaypointsLoaded([]);
                // Notify parent that mission items have changed
                widget.onMissionItemsChanged?.call();
              },
              child: Text(
                'Clear All',
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        AnimatedContainer(
          duration: Duration(milliseconds: 300), // Animation duration
          curve: Curves.easeInOut, // Animation curve
          width: 300,
          height: screenHeight -
              20, // Full height - using space from removed bottom button
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
              // Always show content - no collapse functionality
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
                        MissionSelector(
                          selectedMission: _selectedMission,
                          modeColor: widget.modeColor,
                          missions: settingsProvider.missions.entries.where(
                              (entry) =>
                                  entry.value.mapName == widget.currentMap),
                          hasMissionItems: _missionItems.isNotEmpty,
                          onMissionChangeRequested:
                              _handleMissionChangeRequested,
                          onSaveSelected: _showSaveMissionDialog,
                          onDeleteSelected: _confirmDeleteMission,
                        ),
                        // Clear All button
                        _buildClearAllButton(),

                        // Mission Items List
                        MissionItemList(
                          items: _missionItems,
                          scrollController: _scrollController,
                          onReorder: _handleReorder,
                          onReorderStart: () {
                            setState(() {
                              _isDragging = true;
                            });
                            _startDragPositionTracking();
                          },
                          onReorderEnd: _stopAutoScroll,
                          onItemTap: _handleMissionItemTap,
                          onDeleteConfirmed: _handleMissionItemDeleteConfirmed,
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
                      ],
                    ),
                  ),
                ),
              ),

              // Sticky Add Mission Item Button at bottom
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  border: Border(
                    top: BorderSide(
                      color: Colors.grey[700]!,
                      width: 1,
                    ),
                  ),
                ),
                child: GestureDetector(
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
              ),

              // Removed HeaderToggle - panel is now always expanded
            ],
          ),
        ),
      ],
    );
  }

  // The mission-selector dropdown's onChanged, extracted out of that inline
  // closure when the dropdown itself moved into MissionSelector. Owns the
  // full unsaved-changes-confirm -> conditional-save -> proceed decision
  // tree, unchanged from the original.
  void _handleMissionChangeRequested(String? value) async {
    if (_hasUnsavedChanges && _selectedMission != null) {
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
              onPressed: () => Navigator.pop(context, 'discard'),
              child: Text(
                'Discard',
                style: TextStyle(
                  color: Colors.red[400],
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'save'),
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
            _missionNameController.text.trim().isNotEmpty) {
          final mission = Mission(
            missionName: _missionNameController.text.trim(),
            missionDescription: _missionDescController.text.trim(),
            mapName: widget.currentMap!,
            items: List.from(_missionItems),
          );
          final settingsProvider =
              Provider.of<SettingsProvider>(context, listen: false);
          settingsProvider.saveMission(mission);

          // Force mission path repaint by notifying the parent with current ordering
          final orderedWaypoints = _getWaypointsInMissionOrder();
          if (orderedWaypoints.isNotEmpty) {
            widget.onWaypointsLoaded(List<Waypoint>.from(orderedWaypoints));
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
        backgroundColor: Colors.green.withOpacity(0.9),
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

  /// Configures a LOOP item: repeat the whole mission a set number of times,
  /// or forever. Placing this as the last item is the normal use, but the
  /// engine only ever jumps back to index 0 — it doesn't care where the
  /// item sits.
  void _showLoopItemDialog(BuildContext context, int index) async {
    bool forever = _missionItems[index].loopForever ?? false;
    int count = (_missionItems[index].loopCount ?? 1).clamp(1, 999);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text('Configure Loop', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'When execution reaches this item, the mission restarts from '
                'the beginning.',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
              ),
              SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: widget.modeColor,
                title: Text('Repeat forever',
                    style: TextStyle(color: Colors.white)),
                value: forever,
                onChanged: (v) => setStateDialog(() => forever = v),
              ),
              if (!forever) ...[
                SizedBox(height: 8),
                Row(
                  children: [
                    Text('Repeat count',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    Spacer(),
                    IconButton(
                      icon: Icon(Icons.remove_circle_outline,
                          color: widget.modeColor),
                      onPressed: count > 1
                          ? () => setStateDialog(() => count--)
                          : null,
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '$count',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add_circle_outline,
                          color: widget.modeColor),
                      onPressed: count < 999
                          ? () => setStateDialog(() => count++)
                          : null,
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('OK', style: TextStyle(color: widget.modeColor)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() {
        _missionItems[index].loopForever = forever;
        _missionItems[index].loopCount = count;
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
      builder: (context) => buildExpandableItemDialog(
        title: 'Configure Publish',
        icon: Icons.publish,
        color: MissionItemType.publish.color,
        formBuilder: (setStateDialog) =>
            _buildPublishForm(item, index, setStateDialog),
        provider: _ros2DataProvider,
      ),
    );
  }

  void _showServiceItemDialog(BuildContext context, int index) {
    final item = _missionItems[index];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => buildExpandableItemDialog(
        title: 'Configure Service',
        icon: Icons.settings,
        color: MissionItemType.callService.color,
        formBuilder: (setStateDialog) =>
            _buildServiceForm(item, index, setStateDialog),
        provider: _ros2DataProvider,
      ),
    );
  }

  void _showActionItemDialog(BuildContext context, int index) {
    final item = _missionItems[index];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => buildExpandableItemDialog(
        title: 'Configure Action',
        icon: Icons.play_arrow,
        color: MissionItemType.callAction.color,
        formBuilder: (setStateDialog) =>
            _buildActionForm(item, index, setStateDialog),
        provider: _ros2DataProvider,
      ),
    );
  }

  void _showApiCallItemDialog(BuildContext context, int index) {
    final item = _missionItems[index];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => buildExpandableItemDialog(
        title: 'Configure API Call',
        icon: Icons.http,
        color: MissionItemType.apiCall.color,
        formBuilder: (setStateDialog) =>
            _buildApiCallForm(item, index, setStateDialog),
        provider: _ros2DataProvider,
      ),
    );
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
        setState(() {});
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
        setState(() {});
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
        setState(() {});
        setStateDialog(() {});
      },
    );
  }

  Widget _buildApiCallForm(
      MissionItem item, int index, StateSetter setStateDialog) {
    return ApiCallForm(
      item: item,
      modeColor: MissionItemType.apiCall.color,
      onChanged: () {
        _trackChanges();
        setState(() {});
        setStateDialog(() {});
      },
    );
  }

  void startMissionExecution() {
    if (widget.currentMap == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No map selected for mission'),
          backgroundColor: Colors.red.withOpacity(0.9),
        ),
      );
      return;
    }

    if (_missionItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Mission has no items to execute'),
          backgroundColor: Colors.red.withOpacity(0.9),
        ),
      );
      return;
    }

    final mission = Mission(
      missionName: _missionNameController.text.trim().isEmpty
          ? 'Mission ${DateTime.now().millisecondsSinceEpoch}'
          : _missionNameController.text.trim(),
      missionDescription: _missionDescController.text.trim(),
      mapName: widget.currentMap!,
      items: List<MissionItem>.from(_missionItems),
    );

    // Mission execution started - panel remains visible but read-only

    Provider.of<MissionExecutionService>(context, listen: false)
        .startMission(context, mission);
  }

  // Handle changes in mission execution state
  void _handleMissionStateChange() {
    if (!mounted) return;
    final missionService =
        Provider.of<MissionExecutionService>(context, listen: false);

    // Mission execution state changed - panel remains visible
  }
}
