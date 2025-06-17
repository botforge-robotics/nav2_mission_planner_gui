import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/modals/mission.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/ros2_data_provider.dart';
import 'package:nav2_mission_planner/services/form_generator.dart';
import 'package:nav2_mission_planner/services/message_parser.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:ui' show lerpDouble;
import 'duration_selector.dart';
import 'package:flutter/services.dart';

class NumericalRangeFormatter extends TextInputFormatter {
  final int min;
  final int max;

  NumericalRangeFormatter({required this.min, required this.max});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final value = int.tryParse(newValue.text);
    if (value == null) return oldValue;

    if (value < min) return TextEditingValue(text: min.toString());
    if (value > max) return TextEditingValue(text: max.toString());

    return newValue;
  }
}

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
      print('Error initializing saved data: $e');
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
  Future<void> _fetchTopics(bool forceRefresh) async {
    if (_ros2DataProvider == null) return;
    try {
      await _ros2DataProvider!.fetchTopics(forceRefresh: forceRefresh);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fetch topics: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fetchServices(bool forceRefresh) async {
    if (_ros2DataProvider == null) return;
    try {
      await _ros2DataProvider!.fetchServices(forceRefresh: forceRefresh);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fetch services: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fetchActionServers(bool forceRefresh) async {
    if (_ros2DataProvider == null) return;
    try {
      await _ros2DataProvider!.fetchActionServers(forceRefresh: forceRefresh);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fetch action servers: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fetchMessageStructure(
      String topicName, String messageType) async {
    if (_ros2DataProvider == null) return;
    try {
      await _ros2DataProvider!.getMessageStructure(topicName, messageType);
    } catch (e) {
      print('Failed to fetch message structure for $messageType: $e');
    }
  }

  Future<void> _fetchServiceStructure(
      String serviceName, String serviceType, bool isRequest) async {
    if (_ros2DataProvider == null) return;

    try {
      if (isRequest) {
        await _ros2DataProvider!
            .getServiceRequestStructure(serviceName, serviceType);
      } else {
        await _ros2DataProvider!
            .getServiceResponseStructure(serviceName, serviceType);
      }
    } catch (e) {
      print('Failed to fetch service structure for $serviceType: $e');
    }
  }

  Future<void> _fetchActionStructure(
      String actionName, String actionType) async {
    if (_ros2DataProvider == null) return;
    try {
      await _ros2DataProvider!.getActionGoalStructure(actionName, actionType);
    } catch (e) {
      print('Failed to fetch action structure for $actionType: $e');
    }
  }

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

  void _handleReorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    setState(() {
      final MissionItem item = _missionItems.removeAt(oldIndex);
      _missionItems.insert(newIndex, item);
      _trackChanges();
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

                          // Update the state to reflect the saved mission
                          setState(() {
                            _selectedMission = mission.missionName;
                            _originalItems =
                                List<MissionItem>.from(_missionItems);
                            _hasUnsavedChanges = false;
                          });

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
                                    icon:
                                        Icon(Icons.delete, color: Colors.white),
                                    onPressed: _confirmDeleteMission,
                                    tooltip: 'Delete Mission',
                                    padding: EdgeInsets.all(12),
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
                                    icon: Icon(Icons.save, color: Colors.white),
                                    onPressed: _showSaveMissionDialog,
                                    tooltip: 'Save Mission',
                                    padding: EdgeInsets.all(12),
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
          GestureDetector(
            onTap: _togglePanel,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    widget.modeColor.withOpacity(0.1),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border(
                  top: BorderSide(
                    color: Colors.grey[700]!,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.route,
                    color: widget.modeColor,
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Mission Planner',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isCollapsed ? 0.5 : 0.0, // Flip the rotation
                    duration: Duration(milliseconds: 300),
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      color: widget.modeColor,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
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

  // Helper function to convert radians to 0-360° range (clockwise positive)
  String _formatYawAngle(double radians) {
    // Convert to degrees and reverse direction (clockwise positive)
    double degrees = -radians * (180 / 3.141592653589793);
    // Normalize to 0-360 range
    degrees = degrees % 360;
    if (degrees < 0) degrees += 360;
    return '${degrees.toStringAsFixed(1)}°';
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
    if (_ros2DataProvider?.isLoadingServices ?? false)
      return 'Loading services...';
    if (_ros2DataProvider?.isLoadingActions ?? false)
      return 'Loading action servers...';
    if (_ros2DataProvider?.isLoadingMessageStructure ?? false)
      return 'Loading message structure...';
    return 'Loading...';
  }

  Widget _buildPublishForm(
      MissionItem item, int index, StateSetter setStateDialog) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Topic Configuration Section
        _buildSectionCard(
          title: 'Topic Configuration',
          icon: Icons.topic,
          color: MissionItemType.publish.color,
          child: _buildTopicDropdown(item, index, setStateDialog),
        ),
        SizedBox(height: 24),

        // Frequency Configuration Section
        _buildSectionCard(
          title: 'Publishing Frequency',
          icon: Icons.schedule,
          color: MissionItemType.publish.color,
          child: _buildFrequencySelector(item, index, setStateDialog),
        ),
        SizedBox(height: 24),

        // Message Data Section
        _buildSectionCard(
          title: 'Message Data',
          icon: Icons.data_object,
          color: MissionItemType.publish.color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (item.publishMsgType != null) ...[
                SizedBox(width: 8),
                Text(
                  '${item.publishMsgType}',
                  style: TextStyle(
                    color: Colors.grey[400], // Light grey color
                    fontSize: 12, // Small size
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              SizedBox(height: 16),
              _buildMessageFields(item, index),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.1),
                  Colors.transparent,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
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
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Section Content
          Container(
            padding: EdgeInsets.all(20),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildServiceForm(
      MissionItem item, int index, StateSetter setStateDialog) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Service Configuration Section
        _buildSectionCard(
          title: 'Service Configuration',
          icon: Icons.settings,
          color: MissionItemType.callService.color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select a service',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: _ros2DataProvider?.isLoadingServices ?? false
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: MissionItemType.callService.color,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(Icons.refresh,
                              color: MissionItemType.callService.color,
                              size: 18),
                      onPressed: _ros2DataProvider?.isLoadingServices ?? false
                          ? null
                          : () async {
                              await _fetchServices(true);
                            },
                      tooltip: 'Refresh Services',
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: item.serviceName != null
                        ? MissionItemType.callService.color.withOpacity(0.5)
                        : Colors.grey[600]!,
                    width: 1,
                  ),
                ),
                child: DropdownButtonFormField<String>(
                  value: item.serviceName != null &&
                          (_ros2DataProvider?.services
                                  .containsKey(item.serviceName) ??
                              false)
                      ? item.serviceName
                      : null,
                  hint: Row(
                    children: [
                      Icon(
                        Icons.settings,
                        color: Colors.grey[500],
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Text(
                        _ros2DataProvider?.services.isEmpty ?? true
                            ? 'Click refresh to load services'
                            : 'Select a service',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  isExpanded: true,
                  dropdownColor: Colors.grey[800],
                  menuMaxHeight: 300,
                  decoration: InputDecoration(
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
                  items:
                      (_ros2DataProvider?.services ?? {}).entries.map((entry) {
                    return DropdownMenuItem<String>(
                      value: entry.key,
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    if (value == null) return;

                    try {
                      setStateDialog(() {
                        // Start loading animation
                        _missionItems[index].serviceName = value;
                      });

                      // Get service type when user selects service
                      final serviceType = _ros2DataProvider?.services[value] ??
                          await _ros2DataProvider?.getServiceType(value) ??
                          '';

                      // Fetch service structure if not already available
                      final key = '${serviceType}_request';
                      if (_ros2DataProvider?.messageStructures[key] == null) {
                        await _fetchServiceStructure(value, serviceType, true);
                      }

                      setStateDialog(() {
                        _missionItems[index].serviceType = serviceType;
                        _missionItems[index].serviceRequest = {};
                        _trackChanges();
                      });
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to load service structure: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 24),

        // Wait for response toggle
        _buildSectionCard(
          title: 'Response Options',
          icon: Icons.timer,
          color: MissionItemType.callService.color,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Wait for Response',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Switch(
                value: item.waitForServiceResponse ?? false,
                onChanged: (value) {
                  setStateDialog(() {
                    _missionItems[index].waitForServiceResponse = value;
                    _trackChanges();
                  });
                },
                activeColor: MissionItemType.callService.color,
              ),
            ],
          ),
        ),
        SizedBox(height: 24),

        // Request Fields Section
        _buildSectionCard(
          title: 'Request Data',
          icon: Icons.send,
          color: MissionItemType.callService.color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (item.serviceType != null) ...[
                Text(
                  '${item.serviceType}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                SizedBox(height: 16),
              ],
              _buildServiceRequestFields(item, index, setStateDialog),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServiceRequestFields(
      MissionItem item, int index, StateSetter setStateDialog) {
    if (item.serviceType == null || item.serviceType!.isEmpty) {
      return Center(
          child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.grey[400],
              size: 32,
            ),
            SizedBox(height: 12),
            Text(
              'Select a service to load request structure',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ));
    }

    final key = '${item.serviceType}_request';
    final structure = _ros2DataProvider?.messageStructures[key];

    // Add null check and type validation
    if (structure == null || structure is! Map<String, dynamic>) {
      return Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: _ros2DataProvider?.isLoadingMessageStructure ?? false
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                          MissionItemType.callService.color),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading service request structure...',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.grey[400],
                    size: 32,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No request structure available',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      );
    }

    // Initialize serviceRequest with proper structure if null
    if (item.serviceRequest == null) {
      item.serviceRequest =
          MessageParser.getDefaultValueForStructure(structure);
    }

    if (structure.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[700]!,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            'This service doesn\'t require any parameters',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: structure.entries.map((entry) {
          final fieldName = entry.key;
          final fieldDefinition = entry.value as Map<String, dynamic>;

          // Get current value from serviceRequest
          final currentValue = item.serviceRequest![fieldName];

          return Container(
            margin: EdgeInsets.only(bottom: 16),
            padding: EdgeInsets.all(0),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            child: FormGenerator.generateFormField(
              fieldName,
              fieldDefinition,
              currentValue,
              (value) {
                setStateDialog(() {
                  item.serviceRequest![fieldName] = value;
                  _trackChanges();
                });
              },
              MissionItemType.callService.color,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionForm(
      MissionItem item, int index, StateSetter setStateDialog) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action Configuration Section
        _buildSectionCard(
          title: 'Action Configuration',
          icon: Icons.play_arrow,
          color: MissionItemType.callAction.color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Action Server Name',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  IconButton(
                    icon: _ros2DataProvider?.isLoadingActions ?? false
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  MissionItemType.callAction.color),
                            ),
                          )
                        : Icon(Icons.refresh,
                            color: MissionItemType.callAction.color),
                    onPressed: _ros2DataProvider?.isLoadingActions ?? false
                        ? null
                        : () async {
                            await _fetchActionServers(true);
                          },
                    tooltip: 'Refresh Action Servers',
                  ),
                ],
              ),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: (_ros2DataProvider?.actionServers ?? [])
                        .contains(item.actionName)
                    ? item.actionName
                    : null,
                hint: Text(
                  (_ros2DataProvider?.actionServers ?? []).isEmpty
                      ? 'Click refresh to load action servers'
                      : 'Select an action server',
                  style: TextStyle(color: Colors.grey[500]),
                ),
                isExpanded: true,
                dropdownColor: Colors.grey[800],
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey[900],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: MissionItemType.callAction.color),
                  ),
                ),
                items: (_ros2DataProvider?.actionServers ?? [])
                    .map((actionServer) {
                  return DropdownMenuItem<String>(
                    value: actionServer,
                    child: Text(
                      actionServer,
                      style: TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) async {
                  if (value != null) {
                    try {
                      setStateDialog(() {
                        // Start loading animation
                        _missionItems[index].actionName = value;
                      });

                      // First get the action type
                      final actionType =
                          await _ros2DataProvider?.getActionType(value) ?? '';

                      // Fetch action structure if not already available
                      final key = '${actionType}_goal';
                      if (_ros2DataProvider?.messageStructures[key] == null) {
                        await _fetchActionStructure(value, actionType);
                      }

                      setStateDialog(() {
                        _missionItems[index].actionType = actionType;
                        _missionItems[index].actionGoal = {};
                        _trackChanges();
                      });
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to load action structure: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 24),

        // Wait for result toggle
        _buildSectionCard(
          title: 'Result Options',
          icon: Icons.timer,
          color: MissionItemType.callAction.color,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Wait for Result',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Switch(
                value: item.waitForActionResult ?? false,
                onChanged: (value) {
                  setStateDialog(() {
                    _missionItems[index].waitForActionResult = value;
                    _trackChanges();
                  });
                },
                activeColor: MissionItemType.callAction.color,
              ),
            ],
          ),
        ),
        SizedBox(height: 24),

        // Goal Fields Section
        _buildSectionCard(
          title: 'Goal Data',
          icon: Icons.flag,
          color: MissionItemType.callAction.color,
          child: _buildActionGoalFields(item, index, setStateDialog),
        ),
      ],
    );
  }

  Widget _buildActionGoalFields(
      MissionItem item, int index, StateSetter setStateDialog) {
    if (item.actionType == null || item.actionType!.isEmpty) {
      return Center(
          child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.grey[400],
              size: 32,
            ),
            SizedBox(height: 12),
            Text(
              'Select an action to load goal structure',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ));
    }

    final key = '${item.actionType}_goal';
    final structure = _ros2DataProvider?.messageStructures[key];

    // Add null check and type validation
    if (structure == null || structure is! Map<String, dynamic>) {
      return Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: _ros2DataProvider?.isLoadingMessageStructure ?? false
            ? Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                          MissionItemType.callAction.color),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading action goal structure...',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.amber[400],
                    size: 32,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No goal structure available',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.amber[300],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      );
    }

    // Initialize actionGoal with proper structure if null
    if (item.actionGoal == null) {
      item.actionGoal = MessageParser.getDefaultValueForStructure(structure);
    }

    if (structure.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[700]!,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            'This action doesn\'t require any goal parameters',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.actionType != null) ...[
            Container(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                item.actionType!,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          ...structure.entries.map((entry) {
            final fieldName = entry.key;
            final fieldDefinition = entry.value as Map<String, dynamic>;

            // Get current value from actionGoal
            final currentValue = item.actionGoal![fieldName];

            return Container(
              margin: EdgeInsets.only(bottom: 16),
              padding: EdgeInsets.all(0),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: FormGenerator.generateFormField(
                fieldName,
                fieldDefinition,
                currentValue,
                (value) {
                  setStateDialog(() {
                    item.actionGoal![fieldName] = value;
                    _trackChanges();
                  });
                },
                MissionItemType.callAction.color,
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildTopicDropdown(
      MissionItem item, int index, StateSetter setStateDialog) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select a topic',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: _ros2DataProvider?.isLoadingTopics ?? false
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: MissionItemType.publish.color,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(Icons.refresh,
                        color: MissionItemType.publish.color, size: 18),
                onPressed: _ros2DataProvider?.isLoadingTopics ?? false
                    ? null
                    : () async {
                        await _fetchTopics(true);
                      },
                tooltip: 'Refresh Topics',
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: item.publishTopic != null
                  ? MissionItemType.publish.color.withOpacity(0.5)
                  : Colors.grey[600]!,
              width: 1,
            ),
          ),
          child: DropdownButtonFormField<String>(
            value:
                (_ros2DataProvider?.topics ?? {}).containsKey(item.publishTopic)
                    ? item.publishTopic
                    : null,
            hint: Row(
              children: [
                Icon(
                  Icons.topic,
                  color: Colors.grey[500],
                  size: 16,
                ),
                SizedBox(width: 8),
                Text(
                  (_ros2DataProvider?.topics ?? {}).isEmpty
                      ? 'Click refresh to load topics'
                      : 'Select a topic',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
            isExpanded: true,
            dropdownColor: Colors.grey[800],
            menuMaxHeight: 300,
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
            ),
            items: (_ros2DataProvider?.topics ?? {}).entries.map((entry) {
              return DropdownMenuItem<String>(
                value: entry.key,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              );
            }).toList(),
            onChanged: (value) async {
              if (value == null) return;

              setStateDialog(() {
                _missionItems[index].publishTopic = value;
                _missionItems[index].publishMessage = null;
                _trackChanges();
              });

              try {
                setStateDialog(() {
                  // Start loading animation for topic selection
                  _missionItems[index].publishTopic = value;
                });

                final messageType = _ros2DataProvider?.topics[value] ?? '';
                final normalizedType =
                    MessageParser.normalizeMessageType(messageType);

                // Check if we already have the message structure
                if (_ros2DataProvider?.messageStructures[normalizedType] ==
                    null) {
                  await _fetchMessageStructure(value, messageType);
                }

                setStateDialog(() {
                  _missionItems[index].publishMsgType = normalizedType;
                });
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to load message structure: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFrequencySelector(
      MissionItem item, int index, StateSetter setStateDialog) {
    // Initialize frequency type if not set
    if (item.publishFrequencyType == null) {
      item.publishFrequencyType = 'once';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary frequency type selector
        Text(
          'Publishing Mode',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 12),

        // 1. Publish Once
        _buildFrequencyOption(
          item,
          index,
          'once',
          'Publish Once',
          'Send message only once',
          Icons.check_circle_outline,
          setStateDialog,
        ),

        SizedBox(height: 12),

        // 2. Publish at Frequency
        _buildFrequencyOption(
          item,
          index,
          'frequency',
          'Publish at Frequency',
          'Send message continuously',
          Icons.repeat,
          setStateDialog,
        ),

        // Sub-options for frequency mode
        if (item.publishFrequencyType == 'frequency') ...[
          SizedBox(height: 16),
          Container(
            margin: EdgeInsets.only(left: 16),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: MissionItemType.publish.color.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frequency Options',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 12),

                // Frequency input with +/- buttons
                Row(
                  children: [
                    Text(
                      'Rate (Hz):', // Moved unit into label
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                    SizedBox(width: 16),
                    IconButton(
                      onPressed: () {
                        setStateDialog(() {
                          final current = (item.publishFrequency ?? 1).toInt();
                          _missionItems[index].publishFrequency =
                              (current - 1).clamp(1, 30).toDouble();
                          _trackChanges();
                        });
                      },
                      icon: Icon(Icons.remove,
                          color: MissionItemType.publish.color),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                        minimumSize: Size(32, 32),
                      ),
                    ),
                    SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        controller: TextEditingController(
                          text: (item.publishFrequency ?? 1).toInt().toString(),
                        ),
                        style: TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          NumericalRangeFormatter(min: 1, max: 30)
                        ],
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey[800],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            setStateDialog(() {
                              final intValue = int.tryParse(value) ?? 1;
                              _missionItems[index].publishFrequency =
                                  intValue.clamp(1, 30).toDouble();
                              _trackChanges();
                            });
                          }
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        setStateDialog(() {
                          final current = (item.publishFrequency ?? 1).toInt();
                          _missionItems[index].publishFrequency =
                              (current + 1).clamp(1, 30).toDouble();
                          _trackChanges();
                        });
                      },
                      icon:
                          Icon(Icons.add, color: MissionItemType.publish.color),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                        minimumSize: Size(32, 32),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 16),

                // Duration options
                Text(
                  'Duration',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8),

                // 1. For specific duration (default selection)
                Row(
                  children: [
                    Radio<String>(
                      value: 'duration',
                      groupValue: item.publishFrequencyType == 'frequency'
                          ? (item.publishDuration == null
                              ? 'until_next_goal' // Default to until_next_goal if null
                              : item.publishDuration! > 0
                                  ? 'duration'
                                  : item.publishDuration == -1
                                      ? 'mission_end'
                                      : 'until_next_goal')
                          : null,
                      onChanged: (value) {
                        setStateDialog(() {
                          _missionItems[index].publishDuration =
                              5.0; // Default 5 seconds
                          _trackChanges();
                        });
                      },
                      activeColor: MissionItemType.publish.color,
                    ),
                    Text(
                      'For specific duration',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    if (item.publishDuration != null &&
                        item.publishDuration! > 0) ...[
                      SizedBox(width: 16),
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          controller: TextEditingController(
                            text: item.publishDuration!.toInt().toString(),
                          ),
                          style: TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            NumericalRangeFormatter(min: 1, max: 3600)
                          ],
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.grey[800],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                          ),
                          onChanged: (value) {
                            if (value.isNotEmpty) {
                              setStateDialog(() {
                                final intValue = int.tryParse(value) ?? 5;
                                _missionItems[index].publishDuration =
                                    intValue.clamp(1, 3600).toDouble();
                                _trackChanges();
                              });
                            }
                          },
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'seconds',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),

                // 2. Until next waypoint
                Row(
                  children: [
                    Radio<String>(
                      value: 'until_next_goal',
                      groupValue: item.publishFrequencyType == 'frequency'
                          ? (item.publishDuration == null
                              ? 'until_next_goal' // Default to until_next_goal if null
                              : item.publishDuration! > 0
                                  ? 'duration'
                                  : item.publishDuration == -1
                                      ? 'mission_end'
                                      : 'until_next_goal')
                          : null,
                      onChanged: (value) {
                        setStateDialog(() {
                          _missionItems[index].publishDuration = null;
                          _trackChanges();
                        });
                      },
                      activeColor: MissionItemType.publish.color,
                    ),
                    Text(
                      'Until next waypoint',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),

                // 3. Until mission completion
                Row(
                  children: [
                    Radio<String>(
                      value: 'mission_end',
                      groupValue: item.publishFrequencyType == 'frequency'
                          ? (item.publishDuration == null
                              ? 'until_next_goal' // Default to until_next_goal if null
                              : item.publishDuration! > 0
                                  ? 'duration'
                                  : item.publishDuration == -1
                                      ? 'mission_end'
                                      : 'until_next_goal')
                          : null,
                      onChanged: (value) {
                        setStateDialog(() {
                          _missionItems[index].publishDuration = -1;
                          _trackChanges();
                        });
                      },
                      activeColor: MissionItemType.publish.color,
                    ),
                    Text(
                      'Until mission completion',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFrequencyOption(
    MissionItem item,
    int index,
    String value,
    String title,
    String description,
    IconData icon,
    StateSetter setStateDialog,
  ) {
    final isSelected = item.publishFrequencyType == value;

    return GestureDetector(
      onTap: () {
        setStateDialog(() {
          _missionItems[index].publishFrequencyType = value;
          if (value == 'once') {
            _missionItems[index].publishFrequency = null;
            _missionItems[index].publishDuration = null;
          } else if (value == 'frequency') {
            _missionItems[index].publishFrequency = 1.0;
            _missionItems[index].publishDuration =
                null; // Default to until next waypoint
          }
          _trackChanges();
        });
      },
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? MissionItemType.publish.color.withOpacity(0.2)
              : Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected ? MissionItemType.publish.color : Colors.grey[700]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color:
                  isSelected ? MissionItemType.publish.color : Colors.grey[400],
              size: 20,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[300],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: MissionItemType.publish.color,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  void _showDurationPickerForPublish(int index) async {
    // Simple text input for duration
    final TextEditingController durationController = TextEditingController(
      text: (_missionItems[index].publishDuration ?? 5).toInt().toString(),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          'Set Publishing Duration',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: durationController,
          style: TextStyle(color: Colors.white),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Duration (seconds)',
            labelStyle: TextStyle(color: Colors.grey[400]),
            filled: true,
            fillColor: Colors.grey[800],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: MissionItemType.publish.color),
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
              final value = double.tryParse(durationController.text) ?? 5.0;
              Navigator.pop(context, value);
            },
            child: Text('OK',
                style: TextStyle(color: MissionItemType.publish.color)),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _missionItems[index].publishDuration = result;
        _trackChanges();
      });
    }
  }

  Widget _buildMessageFields(MissionItem item, int index) {
    if (item.publishMsgType == null || item.publishMsgType!.isEmpty) {
      return Center(
          child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.grey[400],
              size: 32,
            ),
            SizedBox(height: 12),
            Text(
              'Select a topic to load message structure',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ));
    }

    final structure = _ros2DataProvider?.messageStructures[item.publishMsgType];

    // Add null check and type validation
    if (structure == null || structure is! Map<String, dynamic>) {
      return Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red[900]!.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.red[600]!,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red[400],
              size: 32,
            ),
            SizedBox(height: 12),
            Text(
              'Failed to load message structure',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.red[300],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Initialize publishMessage with proper structure if null
    if (item.publishMessage == null) {
      item.publishMessage =
          MessageParser.getDefaultValueForStructure(structure);
    }

    return Container(
      padding: EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: structure.entries.map((entry) {
          final fieldName = entry.key;
          final fieldDefinition = entry.value as Map<String, dynamic>;

          // Get current value from publishMessage
          final currentValue = item.publishMessage![fieldName];

          return Container(
            margin: EdgeInsets.only(bottom: 16),
            padding: EdgeInsets.all(0),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            child: FormGenerator.generateFormField(
              fieldName,
              fieldDefinition,
              currentValue,
              (value) {
                setState(() {
                  item.publishMessage![fieldName] = value;
                  _trackChanges();
                });
              },
              MissionItemType.publish.color,
            ),
          );
        }).toList(),
      ),
    );
  }
}
