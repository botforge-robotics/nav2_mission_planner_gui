import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nav2_mission_planner/modals/bookmark.dart';
import 'package:nav2_mission_planner/services/goal_service.dart';
import 'package:nav2_mission_planner/providers/ros2_data_provider.dart';
import 'package:nav2_mission_planner/widgets/navigation/nav_bottom_bar.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/providers/branding_provider.dart';
import 'package:nav2_mission_planner/services/get_map_list_service.dart';
import 'package:nav2_mission_planner/services/launch_service.dart';
import 'package:nav2_mission_planner/widgets/occupancy_grid_viewer.dart';
import 'package:nav2_mission_planner/widgets/sensors/joystick_thumb_widget.dart';
import 'package:nav2_mission_planner/widgets/sensors/image_viwer.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner/services/delete_map_service.dart';
import 'package:nav2_mission_planner/widgets/navigation/navigation_toolbar.dart';
import 'package:nav2_mission_planner/widgets/navigation/visibility_toolbar.dart';
import 'package:nav2_mission_planner/widgets/navigation/robot_telemetry_panel.dart';
import 'package:nav2_mission_planner/services/pose_estimation_service.dart';
import 'package:nav_msgs/msg.dart' as nav_msgs;
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'dart:async';
import 'package:nav2_msgs/action.dart';
import 'package:nav2_mission_planner/helpers/conversions.dart';
import 'package:nav2_mission_planner/widgets/bookmarks/bookmark_dialog.dart';

import 'package:nav2_mission_planner/widgets/navigation/navigation_feedback_widget.dart';
import 'package:nav2_mission_planner/widgets/bookmarks/bookmark_tooltip.dart';
import 'package:uuid/uuid.dart';

import '../modals/mission.dart';
import '../widgets/waypoint_panel/waypoint_panel.dart';
import 'package:nav2_mission_planner/services/mission_execution_service.dart';
import 'package:nav2_mission_planner/services/tf_service.dart';
import 'package:nav2_mission_planner/services/docking_service.dart';

class NavigationScreen extends StatefulWidget {
  final Color modeColor;
  const NavigationScreen({super.key, required this.modeColor});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  List<String> _mapList = [];
  String? _selectedMap;
  bool _loadingMaps = true;
  bool _isNavigationActive = false;
  bool _disableToolBar = false;
  bool _disableLongPress = false;
  // RViz-style overlay toggles — off by default. First live test showed
  // enabling them made robot/bookmark positions look wrong and laser points
  // collapse to one spot; root-caused as rebuild-storm interference (fixed
  // below with throttling) but leaving off by default until confirmed
  // clean on hardware.
  bool _showLocalCostmap = false;
  bool _showGlobalCostmap = false;
  bool _showLaserScan = false;
  // Map display variables
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  Widget? _mapWidget;

  // track which maps are currently being deleted
  final Set<String> _deletingMaps = {};

  Subscriber<dynamic>? _odomSubscriber;
  double _robotX = 0.0;
  double _robotY = 0.0;
  geometry_msgs.Quaternion _robotQ = geometry_msgs.Quaternion();
  // Frame the pose above is measured in. Reported rather than assumed: an
  // odom pose is relative to wherever the robot last started, so it is not
  // comparable to a stored waypoint, and the readout has to say which it has.
  String _poseFrame = 'odom';
  bool _poseReceived = false;
  // Measured velocity from the odometry message, when the source provides it.
  // amcl_pose carries no twist, so these stay null on that path.
  double? _measuredLinear;
  double? _measuredAngular;
  // Last teleop command published by the joystick, and whether the stick is
  // currently deflected.
  double? _cmdLinear;
  double? _cmdAngular;
  bool _teleopActive = false;
  String? _currentOdomTopic;
  String? _currentOdomType;
  late SettingsProvider _settingsProvider;

  final _robotPositionController =
      StreamController<Map<String, dynamic>>.broadcast();
  // Add to class properties
  bool _poseEstimationMode = false;
  bool _goalMode = false;
  bool _bookmarksMode = false;
  // Set while repositioning an existing bookmark (via its tooltip's "Move"
  // button) — the next marker pose updates that bookmark instead of
  // creating a new one. Reuses bookmarks-mode placement.
  String? _repositioningBookmarkId;
  final GoalService _goalService = GoalService();
  String _selectedTool = '';
  final _goalPositionController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Add these variables for goal handling
  bool _showGoalBar = false;
  Map<String, dynamic>? _currentGoalPose;

  bool _showNavigationFeedback = false;
  NavigateToPoseFeedback? _currentFeedback;

  // Add new properties for path handling
  Subscriber<nav_msgs.Path>? _pathSubscriber;
  final _pathController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  // Add late variables to store provider references
  late ConnectionProvider _connectionProvider;
  bool _isInitialized = false; // Add this flag

  List<Bookmark> _localBookmarks = []; // Local list for bookmarks

  // Add this to the existing properties
  bool _isGoalActive = false;

  // Add waypoint mode properties
  bool _missionMode = false;
  List<Waypoint> _waypoints = [];
  List<Waypoint> _previewWaypoints = [];

  bool _showWaypointPanel = false;
  bool _showArrowButton = false;

  // Add info banner for mission mode
  bool _showMissionInfoBanner = false;

  // Add info banner for initial pose
  bool _showInitialPoseBanner = false;

  // Add a new state variable to track if a mission is available to start
  bool _missionAvailable = false;

  // Add GlobalKey for WaypointPanel
  final GlobalKey<WaypointPanelState> _waypointPanelKey =
      GlobalKey<WaypointPanelState>();

  // Add new tracking variables for path subscription
  String? _currentPathTopic;
  bool _pathSubscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Store provider references when dependencies change
    _settingsProvider = Provider.of<SettingsProvider>(context);
    _connectionProvider = Provider.of<ConnectionProvider>(context);

    // Initialize only once
    if (!_isInitialized) {
      TFService.instance.initialize(context);
      DockingService.instance.initialize(context);
      _settingsProvider.addListener(_handleSettingsChange);
      _goalService.initialize(context: context);
      _isInitialized = true;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _loadMaps();
      }
    });
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _settingsProvider.removeListener(_handleSettingsChange);
    }
    _unsubscribePath();
    _pathController.close();
    super.dispose();
  }

  Future<void> _loadMaps() async {
    if (!mounted) return;

    final maps = await MapListService().getMapList(context);

    if (!mounted) return;

    setState(() {
      _mapList = maps;
      _selectedMap = maps.isNotEmpty ? maps.first : null;
      _loadingMaps = false;
    });
  }

  /// Delete remote+local map, then remove from the list on success
  Future<void> _deleteMap(String mapName, int removedIndex) async {
    if (!mounted) return;

    final success = await DeleteMapService().deleteMap(context, mapName);

    if (!mounted) return;

    if (success) {
      // Remove bookmarks for this map
      final bookmarksCount = _settingsProvider.bookmarks[mapName]?.length ?? 0;
      _settingsProvider.bookmarks.remove(mapName);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Map "$mapName" deleted${bookmarksCount > 0 ? " (with $bookmarksCount associated bookmarks)" : ""}',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green.withOpacity(0.9),
        ),
      );
    } else {
      // Deletion failed – restore item to list
      setState(() {
        _mapList.insert(removedIndex, mapName);
      });
    }
  }

  Future<void> _startNavigation() async {
    if (_selectedMap == null) return;
    setState(() {
      _localBookmarks = _settingsProvider.bookmarks[_selectedMap!] ?? [];
    });

    final launchManager = Provider.of<LaunchManager>(context, listen: false);

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: widget.modeColor),
                const SizedBox(height: 16),
                Text(
                  'Starting Navigation...',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );

      final success =
          await launchManager.startNavigation(context, _selectedMap!);

      // Wait until bt_navigator is active (lifecycle can take 10–30s)
      bool navReady = false;
      if (success && mounted) {
        navReady = await _goalService.waitUntilNav2Active(
          timeout: const Duration(seconds: 50),
        );
      }

      // Dismiss loading dialog
      if (mounted) Navigator.pop(context);

      if (success && mounted) {
        // Clear map cache to ensure fresh map data
        OccupancyGridViewer.clearMapCache();

        setState(() {
          _isNavigationActive = true;
          _showInitialPoseBanner = true;
        });
        _subscribeToOdometry();
        PoseEstimationService.initializePublisher(context);
        setState(() {
          // Create map widget
          _mapWidget = _buildMapWidget();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                navReady
                    ? 'Navigation ready with map: $_selectedMap — set initial pose, then send goal'
                    : 'Map loaded but Nav2 still inactive — wait a few seconds or Stop/Start Navigation again',
              ),
              backgroundColor: (navReady ? Colors.green : Colors.orange)
                  .withOpacity(0.9),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting navigation: ${e.toString()}'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
      }
    }
  }

  Future<void> _stopNavigation() async {
    final launchManager = Provider.of<LaunchManager>(context, listen: false);

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Stopping Navigation...',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
      _unsubscribeFromOdometry();
      await PoseEstimationService.shutdown();
      for (final entry in launchManager.activeLaunches.entries) {
        await launchManager.stopLaunch(context, entry.key);
      }

      // Dismiss loading dialog
      if (mounted) Navigator.pop(context);

      if (mounted) {
        // Clear map cache when stopping navigation
        OccupancyGridViewer.clearMapCache();

        setState(() {
          _isNavigationActive = false;
          _mapWidget = null;
          // Reset robot position
          _robotX = 0.0;
          _robotY = 0.0;
          _robotQ = geometry_msgs.Quaternion();
        });

        // Send reset position through stream
        _robotPositionController.add({
          'x': 0.0,
          'y': 0.0,
          'q': geometry_msgs.Quaternion(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Navigation stopped'),
            backgroundColor: Colors.green.withOpacity(0.9),
          ),
        );
      }
    } catch (e) {
      // Dismiss loading dialog if still showing
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping navigation: ${e.toString()}'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
      }
    }

    // Cancel any NavigateToPose goal that might still be active
    try {
      _goalService.cancelCurrentGoal();
    } catch (_) {}
  }

  // Add new confirmation method
  void _confirmStopNavigation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: widget.modeColor),
            const SizedBox(width: 12),
            const Text('Confirm Stop'),
          ],
        ),
        content: const Text('Are you sure you want to stop navigation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
            ),
            onPressed: () {
              Navigator.pop(context);
              _stopNavigation();
            },
            child: const Text('Stop Navigation',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _unsubscribeFromOdometry() {
    _odomSubscriber?.shutdown();
    _odomSubscriber = null;
    _currentOdomTopic = null;
    _currentOdomType = null;
  }

  void _subscribeToOdometry() {
    if (!_isNavigationActive) return;
    final connection = Provider.of<ConnectionProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    // Determine which topic and type to use
    final (String topic, String type) =
        (settings.navigationOdomTopic, settings.navigationOdomTopicType);
    if (topic == _currentOdomTopic && type == _currentOdomType) return;
    _currentOdomTopic = topic;
    _currentOdomType = type;
    // Unsubscribe from old topic
    if (_odomSubscriber != null) {
      _odomSubscriber?.shutdown();
      _odomSubscriber = null;
    }
    try {
      // Create subscriber based on message type
      if (type == 'nav_msgs/msg/Odometry') {
        _odomSubscriber = Subscriber<nav_msgs.Odometry>(
          name: topic,
          type: nav_msgs.Odometry().fullType,
          ros2: connection.ros2Client,
          callback: _processNavOdomMessage,
          prototype: nav_msgs.Odometry(),
        );
      } else if (type == 'geometry_msgs/msg/PoseWithCovarianceStamped') {
        _odomSubscriber = Subscriber<geometry_msgs.PoseWithCovarianceStamped>(
          name: topic,
          type: geometry_msgs.PoseWithCovarianceStamped().fullType,
          ros2: connection.ros2Client,
          callback: _processPoseMessage,
          prototype: geometry_msgs.PoseWithCovarianceStamped(),
        );
      }
    } catch (e) {
      // Silent error handling
    }
  }

  void _processNavOdomMessage(nav_msgs.Odometry message) {
    setState(() {
      _robotX = message.pose.pose.position.x;
      _robotY = message.pose.pose.position.y;
      _robotQ = message.pose.pose.orientation;
      _poseFrame = message.header.frame_id.isNotEmpty
          ? message.header.frame_id
          : 'odom';
      _poseReceived = true;
      _measuredLinear = message.twist.twist.linear.x;
      _measuredAngular = message.twist.twist.angular.z;
    });

    // Send position update through stream
    _robotPositionController.add({
      'x': _robotX,
      'y': _robotY,
      'q': _robotQ,
    });
  }

  void _processPoseMessage(geometry_msgs.PoseWithCovarianceStamped message) {
    setState(() {
      _robotX = message.pose.pose.position.x;
      _robotY = message.pose.pose.position.y;
      _robotQ = message.pose.pose.orientation;
      _poseFrame =
          message.header.frame_id.isNotEmpty ? message.header.frame_id : 'map';
      _poseReceived = true;
      // PoseWithCovarianceStamped carries no twist — leave the measured
      // velocity null so the readout says "not reported" rather than 0.000,
      // which would look like a stationary robot.
      _measuredLinear = null;
      _measuredAngular = null;
    });
    // Send position update through stream
    _robotPositionController.add({
      'x': _robotX,
      'y': _robotY,
      'q': _robotQ,
    });
  }

  void _handleToolSelected(String tool) async {
    // Check for unsaved changes before switching away from mission mode
    if (_missionMode && tool != 'mission') {
      // Add unsaved changes check here if needed
    }

    //debugPrint('tool selected: $tool');
    setState(() {
      _selectedTool = tool;
      _poseEstimationMode = false;
      _goalMode = false;
      // Was never reset here — toggling the active toolbar button off
      // (tap-to-deselect) unhighlights the sidebar but left this true
      // forever, so map taps kept opening "Add Bookmark".
      _bookmarksMode = false;
      _missionMode = tool == 'mission';
      _showGoalBar = false;
      _showWaypointPanel = tool == 'mission';

      // Clear waypoints and preview when switching away from mission mode
      if (!_missionMode) {
        _waypoints.clear();
        _previewWaypoints.clear();
        _showMissionInfoBanner = false;
        // Clear any pattern preview from waypoint panel
        _waypointPanelKey.currentState?.clearPatternPreview();
      }

      _goalPositionController.add({
        'x': 0.0,
        'y': 0.0,
        'orientation': geometry_msgs.Quaternion(x: 0, y: 0, z: 0, w: 1),
        'show': false,
      });
    });

    if (_selectedTool == 'localization') {
      setState(() {
        _goalPositionController.add({
          'x': 0.0,
          'y': 0.0,
          'orientation': geometry_msgs.Quaternion(x: 0, y: 0, z: 0, w: 1),
          'show': false,
        });
        _poseEstimationMode = true;
        _goalMode = false;
        _bookmarksMode = false;
        _showWaypointPanel = false;
        _missionMode = false;
        // Clear any pattern preview when switching to localization
        _previewWaypoints.clear();
        _waypointPanelKey.currentState?.clearPatternPreview();
        if (_isNavigationActive) {
          _mapWidget = _buildMapWidget();
        }
      });
    }
    if (_selectedTool == 'goal') {
      setState(() {
        _goalPositionController.add({
          'x': 0.0,
          'y': 0.0,
          'orientation': geometry_msgs.Quaternion(x: 0, y: 0, z: 0, w: 1),
          'show': false,
        });
        _poseEstimationMode = false;
        _showInitialPoseBanner = false;
        _goalMode = true;
        _bookmarksMode = false;
        _showWaypointPanel = false;
        _missionMode = false;
        // Clear any pattern preview when switching to goal
        _previewWaypoints.clear();
        _waypointPanelKey.currentState?.clearPatternPreview();
        if (_isNavigationActive) {
          _mapWidget = _buildMapWidget();
        }
      });
    }
    if (_selectedTool == 'bookmarks') {
      setState(() {
        _goalPositionController.add({
          'x': 0.0,
          'y': 0.0,
          'orientation': geometry_msgs.Quaternion(x: 0, y: 0, z: 0, w: 1),
          'show': false,
        });
        _poseEstimationMode = false;
        _goalMode = false;
        _bookmarksMode = true;
        _showWaypointPanel = false;
        _missionMode = false;
        // Clear any pattern preview when switching to bookmarks
        _previewWaypoints.clear();
        _waypointPanelKey.currentState?.clearPatternPreview();
        if (_isNavigationActive) {
          _mapWidget = _buildMapWidget();
        }
      });
    }
    if (_selectedTool == 'mission') {
      setState(() {
        _goalPositionController.add({
          'x': 0.0,
          'y': 0.0,
          'orientation': geometry_msgs.Quaternion(x: 0, y: 0, z: 0, w: 1),
          'show': false,
        });
        _poseEstimationMode = false;
        _goalMode = false;
        _bookmarksMode = false;
        _missionMode = true;
        _showWaypointPanel = true;
        if (_isNavigationActive) {
          _mapWidget = _buildMapWidget();
        }
      });

      // Initialize mission services
      if (_connectionProvider.isConnected) {
        // Get the ROS2DataProvider from the widget tree
        final ros2DataProvider =
            Provider.of<ROS2DataProvider>(context, listen: false);

        // Show loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(widget.modeColor),
                ),
                SizedBox(height: 16),
                Column(
                  children: [
                    Text(
                      'Fetching available:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Topics • Services • Actions',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        try {
          // Fetch all required data in parallel using the provider
          await ros2DataProvider.initializeAllData();

          // Close loading dialog
          Navigator.of(context).pop();
        } catch (e) {
          // Close loading dialog
          Navigator.of(context).pop();

          // Show error
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to initialize mission mode: $e'),
              backgroundColor: Colors.red.withOpacity(0.9),
            ),
          );
        }
      }
    }
  }

  void _handleMarkerPoseReceived(Map<String, dynamic> markerPose) {
    if (_goalMode) {
      // Place goal + show slide-to-confirm / cancel (do not auto-send)
      setState(() {
        _showGoalBar = true;
        _currentGoalPose = markerPose;
      });

      _goalPositionController.add({
        'x': markerPose['x'],
        'y': markerPose['y'],
        'orientation': markerPose['orientation'],
        'show': true,
      });
    } else if (_poseEstimationMode) {
      PoseEstimationService.publishPoseEstimate(
        context: context,
        x: markerPose['x'],
        y: markerPose['y'],
        theta: markerPose['orientation'],
      );

      // One placement, one pose — then disarm the tool completely.
      //
      // Previously only the banner was hidden: _poseEstimationMode stayed
      // true and 'localization' stayed selected, so the tool remained armed
      // and the placement marker stayed on the map after the pose had already
      // been published. The next tap on the map would silently re-publish
      // another initial pose, and the left-hand tool still looked active with
      // nothing left to do.
      setState(() {
        _showInitialPoseBanner = false;
        _poseEstimationMode = false;
        _selectedTool = '';
        _goalPositionController.add({
          'x': 0.0,
          'y': 0.0,
          'orientation': geometry_msgs.Quaternion(x: 0, y: 0, z: 0, w: 1),
          'show': false,
        });
      });
    } else if (_bookmarksMode && _repositioningBookmarkId != null) {
      final id = _repositioningBookmarkId!;
      final theta = extractYawFromOriginQuaternion(markerPose['orientation']);
      setState(() {
        _repositioningBookmarkId = null;
        _bookmarksMode = false;
        final idx = _localBookmarks.indexWhere((b) => b.id == id);
        if (idx != -1) {
          _localBookmarks[idx] = _localBookmarks[idx].copyWith(
            positionX: markerPose['x'] as double,
            positionY: markerPose['y'] as double,
            theta: theta,
          );
        }
        _settingsProvider.updateBookmark(
          _selectedMap!,
          id,
          positionX: markerPose['x'] as double,
          positionY: markerPose['y'] as double,
          positionZ: 0.0,
          theta: theta,
        );
        if (idx != -1 && _localBookmarks[idx].isDock) {
          DockingService.instance.publishDockPose(
            markerPose['x'] as double,
            markerPose['y'] as double,
            theta,
          );
        }
      });
    } else if (_bookmarksMode) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => BookmarkDialog(
          onDone: (icon, name, isDock) {
            Navigator.pop(context);

            final theta =
                extractYawFromOriginQuaternion(markerPose['orientation']);

            // Create a new bookmark
            final newBookmark = Bookmark(
              id: Uuid().v4(),
              icon: icon,
              name: name,
              positionX: markerPose['x'],
              positionY: markerPose['y'],
              positionZ: 0.0, // z coordinate
              theta: theta,
              isDock: isDock,
            );

            // Add bookmark to the local list
            setState(() {
              if (isDock) {
                // Only one dock bookmark per map — mirror provider behavior locally.
                for (var i = 0; i < _localBookmarks.length; i++) {
                  if (_localBookmarks[i].isDock) {
                    _localBookmarks[i] =
                        _localBookmarks[i].copyWith(isDock: false);
                  }
                }
              }
              _localBookmarks.add(newBookmark);
              // Update the settings provider
              _settingsProvider.addBookmark(
                icon,
                _selectedMap!,
                name,
                markerPose['x'],
                markerPose['y'],
                0.0,
                theta,
                isDock: isDock,
              );
              if (isDock) {
                DockingService.instance.publishDockPose(
                  markerPose['x'] as double,
                  markerPose['y'] as double,
                  theta,
                );
              }
            });
          },
          onCancel: () {
            Navigator.pop(context);
          },
        ),
      );
    } else if (_missionMode) {
      // Create a new waypoint with sequential numbering
      // Count existing waypoints that were added from map (not bookmarks)
      final mapAddedWaypoints = _waypoints
          .where((w) => w.name != null && w.name!.startsWith('Waypoint '))
          .length;
      final nextWaypointNumber = mapAddedWaypoints + 1;

      final waypoint = Waypoint(
        id: Uuid().v4(),
        events: [],
        position: Position(
          x: markerPose['x'],
          y: markerPose['y'],
          theta: extractYawFromOriginQuaternion(markerPose['orientation']),
        ),
        name: 'Waypoint $nextWaypointNumber',
      );

      setState(() {
        _waypoints.add(waypoint);
        _mapWidget = _buildMapWidget();
        _showMissionInfoBanner = false; // Hide banner after adding location
      });
    }
  }

  Future<void> _subscribeToPath() async {
    final ros2 = _connectionProvider.ros2Client;

    // If already subscribed to the desired topic, do nothing
    if (_pathSubscribed && _currentPathTopic == _settingsProvider.pathTopic) {
      return;
    }

    // Otherwise unsubscribe first
    _unsubscribePath();

    try {
      final subscriber = Subscriber<nav_msgs.Path>(
        name: _settingsProvider.pathTopic,
        type: nav_msgs.Path().fullType,
        ros2: ros2,
        callback: _handlePathMessage,
        prototype: nav_msgs.Path(),
      );
      _pathSubscriber = subscriber;
      _currentPathTopic = _settingsProvider.pathTopic;
      _pathSubscribed = true;
    } catch (e) {
      // Silent error handling
    }
  }

  void _handlePathMessage(nav_msgs.Path message) {
    // Convert PoseStamped list to JSON
    final List<Map<String, dynamic>> posesJson = message.poses.map((pose) {
      return {
        'position': {
          'x': pose.pose.position.x,
          'y': pose.pose.position.y,
          'z': pose.pose.position.z,
        },
        'orientation': {
          'x': pose.pose.orientation.x,
          'y': pose.pose.orientation.y,
          'z': pose.pose.orientation.z,
          'w': pose.pose.orientation.w,
        },
      };
    }).toList();

    _pathController.add(posesJson);
  }

  void _unsubscribePath() {
    _pathSubscriber?.shutdown();
    _pathSubscriber = null;
    _pathSubscribed = false;
    _currentPathTopic = null;

    // Clear any existing path data so UI immediately removes path overlay
    _pathController.add([]);
  }

  void _handleBookmarkGoal(Bookmark bookmark) {
    setState(() {
      // Reset all bookmarks' goal state
      for (var b in _localBookmarks) {
        b.isGoalActive = b == bookmark;
      }

      // Update the bookmark in settings provider
      if (_selectedMap != null) {
        final mapBookmarks = _settingsProvider.bookmarks[_selectedMap!] ?? [];
        final index = mapBookmarks.indexWhere((b) =>
            b.positionX == bookmark.positionX &&
            b.positionY == bookmark.positionY);

        if (index != -1) {
          // Create a new list to trigger change detection
          final updatedBookmarks = List<Bookmark>.from(mapBookmarks);
          updatedBookmarks[index] = Bookmark(
            id: bookmark.id,
            icon: bookmark.icon,
            name: bookmark.name,
            positionX: bookmark.positionX,
            positionY: bookmark.positionY,
            positionZ: bookmark.positionZ,
            theta: bookmark.theta,
            isGoalActive: true,
            isDock: bookmark.isDock,
          );

          // Update the bookmarks in settings provider
          _settingsProvider.bookmarks[_selectedMap!] = updatedBookmarks;
        }
      }

      // Set goal
      _showGoalBar = true;
      _currentGoalPose = {
        'x': bookmark.positionX,
        'y': bookmark.positionY,
        'orientation': eulerToQuaternion(0, 0, bookmark.theta),
      };

      // Rebuild the map widget to reflect changes
      _mapWidget = _buildMapWidget();
    });
  }

  /// Actually docks (staging, detection, seat-nudge, charge confirmation via
  /// dock_manager_node) — distinct from _handleBookmarkGoal's plain nav goal.
  void _handleDockBookmark(Bookmark bookmark) async {
    DockingService.instance.initialize(context);
    try {
      final result = await DockingService.instance.dock(
        x: bookmark.positionX,
        y: bookmark.positionY,
        theta: bookmark.theta,
      );
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dock failed or was cancelled')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Dock failed: $e')));
    }
  }

  void _handleUndockBookmark() async {
    DockingService.instance.initialize(context);
    try {
      final result = await DockingService.instance.undockInPlace();
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Undock failed or was cancelled')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Undock failed: $e')));
    }
  }

  /// Clear goal marker, unlock UI, refresh bookmarks/map after cancel/fail/success.
  void _resetGoalUi() {
    if (_selectedMap != null) {
      final mapBookmarks = _settingsProvider.bookmarks[_selectedMap!] ?? [];
      final updatedBookmarks = mapBookmarks.map((bookmark) {
        return Bookmark(
          id: bookmark.id,
          icon: bookmark.icon,
          name: bookmark.name,
          positionX: bookmark.positionX,
          positionY: bookmark.positionY,
          positionZ: bookmark.positionZ,
          theta: bookmark.theta,
          isGoalActive: false,
          isDock: bookmark.isDock,
        );
      }).toList();
      _settingsProvider.bookmarks[_selectedMap!] = updatedBookmarks;
    }

    for (var b in _localBookmarks) {
      b.isGoalActive = false;
    }

    _isGoalActive = false;
    _disableLongPress = false;
    _disableToolBar = false;
    _showNavigationFeedback = false;
    _showGoalBar = false;
    _currentFeedback = null;
    _currentGoalPose = null;
    _goalPositionController.add({
      'x': 0.0,
      'y': 0.0,
      'orientation': geometry_msgs.Quaternion(x: 0, y: 0, z: 0, w: 1),
      'show': false,
    });
    _mapWidget = _buildMapWidget();
  }

  void _handleGoalSubmission() async {
    if (_currentGoalPose == null) return;

    setState(() {
      _showGoalBar = false;
      _isGoalActive = true;
      _disableLongPress = true;
      _disableToolBar = true;
      _showNavigationFeedback = true;
      _currentFeedback = null;
      _mapWidget = _buildMapWidget();
    });

    try {
      await _subscribeToPath();

      final firstFeedback = Completer<void>();

      final resultFuture = _goalService.sendGoal(
        x: _currentGoalPose!['x'],
        y: _currentGoalPose!['y'],
        orientation: _currentGoalPose!['orientation'],
        frameId: 'map',
        feedbackHandler: (feedback) {
          if (!firstFeedback.isCompleted) {
            firstFeedback.complete();
          }
          if (!mounted) return;
          setState(() {
            _currentFeedback = feedback;
            _mapWidget = _buildMapWidget();
          });
        },
      );

      // Fail fast if Nav2 never accepts / never starts (stack unconfigured)
      await firstFeedback.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _goalService.cancelCurrentGoal();
          throw Exception(
            'Navigation did not start — Nav2 may be inactive. '
            'Stop and Start Navigation again after setting initial pose.',
          );
        },
      );

      final result = await resultFuture;

      if (!mounted) return;

      _unsubscribePath();

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Goal failed — is navigation running and AMCL localized?',
            ),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
        setState(() => _resetGoalUi());
        return;
      }

      setState(() => _resetGoalUi());
    } catch (e) {
      if (!mounted) return;
      _unsubscribePath();
      final msg = e.toString();
      final canceled = msg.toLowerCase().contains('cancel');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(canceled ? 'Goal canceled' : 'Goal error: $e'),
          backgroundColor:
              (canceled ? Colors.orange : Colors.red).withOpacity(0.9),
        ),
      );
      setState(() => _resetGoalUi());
    }
  }

  void _cancelPendingGoal() {
    setState(() => _resetGoalUi());
  }

  void _handleNavigationCancel() {
    _goalService.cancelCurrentGoal();
    _unsubscribePath();
    setState(() => _resetGoalUi());
  }

  void _handleWaypointSelected(int index) {
    // Center view on selected waypoint
    // You may need to implement this based on your map viewer
    // debugPrint('Waypoint $index selected');
  }

  void _handleWaypointDeleted(int index) {
    setState(() {
      _waypoints.removeAt(index);
      _renumberMapWaypoints();
      _mapWidget = _buildMapWidget();
    });
  }

  void _renumberMapWaypoints() {
    // Renumber only waypoints that were added from map (start with "Waypoint ")
    int waypointNumber = 1;
    for (int i = 0; i < _waypoints.length; i++) {
      if (_waypoints[i].name != null &&
          _waypoints[i].name!.startsWith('Waypoint ')) {
        _waypoints[i] = Waypoint(
          id: _waypoints[i].id,
          events: _waypoints[i].events,
          position: _waypoints[i].position,
          name: 'Waypoint $waypointNumber',
        );
        waypointNumber++;
      }
    }
  }

  void _handleWaypointReordered(int oldIndex, int newIndex) {
    setState(() {
      final Waypoint item = _waypoints.removeAt(oldIndex);
      _waypoints.insert(newIndex, item);
      _renumberMapWaypoints();
      _mapWidget = _buildMapWidget();
    });
  }

  void _handleWaypointsLoaded(List<Waypoint> newWaypoints) {
    setState(() {
      _waypoints = newWaypoints;
      _mapWidget = _buildMapWidget();
      // Update mission availability status when waypoints change
      _missionAvailable = newWaypoints.isNotEmpty;
    });
  }

  void _handlePreviewWaypoints(List<Waypoint> previewWaypoints) {
    setState(() {
      _previewWaypoints = previewWaypoints;
      _mapWidget = _buildMapWidget();
    });
  }

  void _handleClearPreview() {
    setState(() {
      _previewWaypoints = [];
      _mapWidget = _buildMapWidget();
    });
  }

  Widget _buildMapWidget() {
    final placementMode = _poseEstimationMode || _goalMode || _bookmarksMode;

    // InteractiveViewer inside OccupancyGridViewer owns pan/zoom.
    // Do not wrap with another scale GestureDetector — it steals left-click.
    return OccupancyGridViewer(
      key: const ValueKey('navigation_viewer'),
      topic: '/map',
      enabled: true,
      scale: _scale,
      appModeColor: widget.modeColor,
      onScaleChanged: (newScale) {
        setState(() {
          _scale = newScale;
        });
      },
      robotPositionStrem: TFService.instance.robotPositionStream,
      goalPositionStream: _goalPositionController.stream,
      pathStream: _pathController.stream,
      showLocalCostmap: _showLocalCostmap,
      showGlobalCostmap: _showGlobalCostmap,
      showLaserScan: _showLaserScan,
      localCostmapTopic: '/local_costmap/costmap',
      globalCostmapTopic: '/global_costmap/costmap',
      // /scan_filtered (not settings.lidarTopic, the raw /scan) — matches
      // what nav2's own costmaps/collision_monitor actually see, so this
      // overlay shows exactly what's driving obstacle avoidance.
      tfMapFrame: _settingsProvider.mapFrame,
      tfOdomFrame: _settingsProvider.odomFrame,
          onMarkerPoseReceived: _handleMarkerPoseReceived,
          onMarkerPoseCancelled: () {
            _cancelPendingGoal();
          },
          disableLongPress: _disableLongPress,
      placementMode: placementMode,
      bookmarks: _localBookmarks,
      onBookmarkTap: (Bookmark bookmark) {
        final mapBookmarks = _settingsProvider.bookmarks[_selectedMap!] ?? [];

        final matchingBookmark = mapBookmarks.firstWhere(
          (b) => b == bookmark,
          orElse: () => bookmark,
        );

        showDialog(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.5),
          barrierDismissible: true,
          builder: (context) => BookmarkTooltip(
            bookmark: bookmark,
            modeColor: widget.modeColor,
            isMissionMode: _missionMode,
            onSendGoal: () {
              Navigator.of(context).pop();
              _handleBookmarkGoal(bookmark);
            },
            onDock: () {
              Navigator.of(context).pop();
              _handleDockBookmark(bookmark);
            },
            onUndock: () {
              Navigator.of(context).pop();
              _handleUndockBookmark();
            },
            onAddWaypoint: () {
              Navigator.of(context).pop();
              _addBookmarkAsWaypoint(bookmark);
            },
            onDelete: () {
              Navigator.of(context).pop();
              // Find the index of the matching bookmark
              final index = mapBookmarks.indexOf(matchingBookmark);

              if (index != -1) {
                setState(() {
                  _localBookmarks.removeWhere((b) => b == bookmark);
                  _settingsProvider.removeBookmark(_selectedMap!, index);
                });
              } else {
                // Could not find bookmark index for deletion
              }
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
                    setState(() {
                      final idx =
                          _localBookmarks.indexWhere((b) => b.id == bookmark.id);
                      if (idx != -1) {
                        _localBookmarks[idx] = _localBookmarks[idx].copyWith(
                          icon: icon,
                          name: name,
                          isDock: isDock,
                        );
                      }
                      _settingsProvider.updateBookmark(
                        _selectedMap!,
                        bookmark.id,
                        icon: icon,
                        name: name,
                        isDock: isDock,
                      );
                      if (isDock) {
                        // Position unchanged here — just (re)confirm it with
                        // the robot in case this bookmark was newly marked
                        // as the dock rather than repositioned.
                        DockingService.instance.publishDockPose(
                          bookmark.positionX,
                          bookmark.positionY,
                          bookmark.theta,
                        );
                      }
                    });
                  },
                  onCancel: () => Navigator.pop(context),
                ),
              );
            },
            onReposition: () {
              Navigator.of(context).pop();
              setState(() {
                _repositioningBookmarkId = bookmark.id;
                _bookmarksMode = true;
              });
            },
          ),
        );
      },
      isGoalActive: _isGoalActive,
      waypoints: _waypoints,
      previewWaypoints: _previewWaypoints,
      showWaypointPath: _missionMode,
      useMapService: true,
      mapServiceName: '/map_server/map',
    );
  }

  void _handleSettingsChange() {
    if (_isNavigationActive) {
      _subscribeToPath();
      if (_settingsProvider.bookmarksVisible) {
        setState(() {
          // Create a new list with the current bookmarks, preserving their state
          _localBookmarks = _settingsProvider.bookmarks[_selectedMap!]
                  ?.map((bookmark) => Bookmark(
                        id: bookmark.id,
                        icon: bookmark.icon,
                        name: bookmark.name,
                        positionX: bookmark.positionX,
                        positionY: bookmark.positionY,
                        positionZ: bookmark.positionZ,
                        theta: bookmark.theta,
                        isGoalActive: bookmark.isGoalActive,
                        isDock: bookmark.isDock,
                      ))
                  .toList() ??
              [];

          _mapWidget = _buildMapWidget();
        });
      } else {
        setState(() {
          _localBookmarks = [];
          _mapWidget = _buildMapWidget();
        });
      }
    }
  }

  void _addBookmarkAsWaypoint(Bookmark bookmark) {
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

    setState(() {
      _waypoints.add(waypoint);
      _mapWidget = _buildMapWidget();
    });
  }

  void _handleArrowButtonStateChanged(bool showArrow) {
    setState(() {
      _showArrowButton = showArrow;
    });
  }

  void _handleMissionItemsChanged() {
    // Trigger a rebuild to update the slide-to-start mission button
    setState(() {
      // This will cause the slide-to-start mission button to rebuild
      // and check for mission items again
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final missionExecService = Provider.of<MissionExecutionService>(context);
    final bool isMissionRunning = missionExecService.isRunning;

    if (_isNavigationActive && _mapWidget != null) {
      // Active navigation view
      return Stack(
        children: [
          // Map Background
          Positioned.fill(child: Container(color: Colors.black)),

          // Map Display
          Positioned.fill(child: _mapWidget!),

          // Mission Info Banner
          if (_showMissionInfoBanner)
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: widget.modeColor.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.touch_app,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Long press on map to add location',
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

          // Placement hint banner (initial pose / goal / bookmarks)
          if (_showInitialPoseBanner ||
              (_goalMode && !_isGoalActive && !_showGoalBar) ||
              (_bookmarksMode && !_showGoalBar))
            Positioned(
              top: _showMissionInfoBanner ? 80 : 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_poseEstimationMode || _showInitialPoseBanner)
                        ? Colors.orange.withOpacity(0.9)
                        : widget.modeColor.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        (_poseEstimationMode || _showInitialPoseBanner)
                            ? Icons.my_location
                            : Icons.navigation,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Text(
                        _goalMode
                            ? (kIsWeb
                                ? 'Set goal — drag to aim · release · then slide to send'
                                : 'Set goal — long-press drag to aim · release · slide to send')
                            : (_poseEstimationMode || _showInitialPoseBanner)
                                ? (kIsWeb
                                    ? 'Set initial pose — drag to aim, release to set'
                                    : 'Set initial pose — long-press drag to aim, release to set')
                                : (kIsWeb
                                    ? 'Drag to place bookmark · release to save'
                                    : 'Long-press drag to place bookmark · release to save'),
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

          // Subscribe to path topic during mission execution
          Consumer<MissionExecutionService>(
            builder: (context, missionService, _) {
              // We need to keep path subscription active either while a mission is running
              // OR while a standalone goal is active.
              final bool shouldSubscribe =
                  missionService.isRunning || _isGoalActive;

              if (shouldSubscribe) {
                // Ensure path subscription is active when required
                _subscribeToPath();
              } else {
                // Otherwise, make sure we are not wasting traffic
                if (_pathSubscribed) {
                  _unsubscribePath();
                }
              }

              return const SizedBox.shrink();
            },
          ),

          // Add Navigation Toolbar
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
                margin: const EdgeInsets.only(left: 5),
                child: Consumer<MissionExecutionService>(
                  builder: (context, missionService, _) {
                    // Disable toolbar during mission execution
                    final bool disableDuringMission = missionService.isRunning;
                    return NavToolbar(
                        disableToolBar: _disableToolBar || disableDuringMission,
                        modeColor: widget.modeColor,
                        selectedTool: _selectedTool,
                        onToolSelected: (tool) => {_handleToolSelected(tool)});
                  },
                )),
          ),

          // Joystick Control
          Visibility(
            visible: settings.joystickVisible,
            child: Positioned(
              bottom: 30,
              right: 40,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: JoystickThumbWidget(
                  modeColor: widget.modeColor,
                  onCommand: (linear, angular) {
                    if (!mounted) return;
                    setState(() {
                      _cmdLinear = linear;
                      _cmdAngular = angular;
                      _teleopActive = linear != 0.0 || angular != 0.0;
                    });
                  },
                ),
              ),
            ),
          ),

          // Pose / velocity readout. Bottom-left is the only corner nothing
          // else claims: the toolbars are on the right, the joystick and
          // waypoint panel bottom-right, banners across the top.
          if (settings.telemetryVisible)
            Positioned(
              left: 12,
              bottom: 12,
              child: RobotTelemetryPanel(
                modeColor: widget.modeColor,
                x: _robotX,
                y: _robotY,
                theta: extractYawFromOriginQuaternion(_robotQ),
                frame: _poseFrame,
                poseAvailable: _poseReceived,
                measuredLinear: _measuredLinear,
                measuredAngular: _measuredAngular,
                commandedLinear: settings.joystickVisible ? _cmdLinear : null,
                commandedAngular: settings.joystickVisible ? _cmdAngular : null,
                teleopActive: _teleopActive,
              ),
            ),

          // Stop Button
          Positioned(
            top: 16,
            right: 65,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.red,
              onPressed: _confirmStopNavigation,
              child: const Icon(Icons.stop, color: Colors.white),
            ),
          ),

          // Camera / image view — hidden for now (keep code)
          // if (settings.cameraEnabled && settings.cameraVisible)
          //   Positioned(
          //     top: 10,
          //     left: 100,
          //     child: SizedBox(
          //       width: MediaQuery.of(context).size.width * 0.25,
          //       height: MediaQuery.of(context).size.width * 0.25 * (9 / 16),
          //       child: Container(
          //         decoration: BoxDecoration(
          //           color: Colors.black,
          //           borderRadius: BorderRadius.circular(8),
          //           border: Border.all(color: widget.modeColor, width: 2),
          //         ),
          //         child: ClipRRect(
          //           borderRadius: BorderRadius.circular(6),
          //           child: ImageViewer(
          //             topic: settings.cameraImageTopic,
          //             enabled: settings.cameraEnabled,
          //             hideTopic: true,
          //           ),
          //         ),
          //       ),
          //     ),
          //   ),

          // Visibility Toolbar
          Positioned(
            right: 0,
            top: 80,
            child: VisibilityToolbar(
              modeColor: widget.modeColor,
              showLocalCostmap: _showLocalCostmap,
              onLocalCostmapToggle: (v) {
                setState(() {
                  _showLocalCostmap = v;
                  _mapWidget = _buildMapWidget();
                });
              },
              showGlobalCostmap: _showGlobalCostmap,
              onGlobalCostmapToggle: (v) {
                setState(() {
                  _showGlobalCostmap = v;
                  _mapWidget = _buildMapWidget();
                });
              },
              showLaserScan: _showLaserScan,
              onLaserScanToggle: (v) {
                setState(() {
                  _showLaserScan = v;
                  _mapWidget = _buildMapWidget();
                });
              },
            ),
          ),

          // Slide to confirm / cancel goal
          if (_showGoalBar)
            NavBottomBar(
              onSlideRight: () {
                setState(() {
                  _showGoalBar = false;
                });
                _handleGoalSubmission();
              },
              onCancel: _cancelPendingGoal,
              promptText: 'Slide to send goal',
              visible: _showGoalBar,
              color: widget.modeColor,
            ),

          // Navigation status bar (show immediately while waiting for feedback)
          if (_showNavigationFeedback)
            _currentFeedback != null
                ? NavigationFeedbackWidget(
                    feedback: _currentFeedback!,
                    onCancel: _handleNavigationCancel,
                  )
                : Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 450,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      widget.modeColor),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Sending goal…',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: _handleNavigationCancel,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade300,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
                  ),

          // Add Waypoint Panel
          if (_showWaypointPanel)
            Positioned(
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                // Disable interaction with waypoint panel during mission execution
                ignoring: isMissionRunning,
                child: Opacity(
                  // Make panel slightly transparent when disabled
                  opacity: isMissionRunning ? 0.7 : 1.0,
                  child: WaypointPanel(
                    key: _waypointPanelKey,
                    waypoints: _waypoints,
                    modeColor: widget.modeColor,
                    onWaypointSelected: _handleWaypointSelected,
                    onWaypointDeleted: _handleWaypointDeleted,
                    onWaypointReordered: _handleWaypointReordered,
                    onWaypointsLoaded: _handleWaypointsLoaded,
                    currentMap: _selectedMap,
                    robotPosition: Position(x: _robotX, y: _robotY, theta: 0),
                    onPreviewWaypoints: _handlePreviewWaypoints,
                    onClearPreview: _handleClearPreview,
                    onShowMissionBanner: () {
                      setState(() {
                        _showMissionInfoBanner = true;
                      });
                    },
                    onArrowButtonStateChanged: _handleArrowButtonStateChanged,
                    onMissionItemsChanged: _handleMissionItemsChanged,
                  ),
                ),
              ),
            ),

          // Mission execution side panel (full-height)
          Consumer<MissionExecutionService>(
            builder: (context, missionService, _) {
              if (!missionService.isRunning ||
                  missionService.currentMission == null) {
                return const SizedBox.shrink();
              }

              return Positioned(
                right: 0,
                top: 0,
                bottom: 0, // extend to bottom edge
                child: Container(
                  width: 300,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(-2, 0),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          border: Border(
                            bottom:
                                BorderSide(color: Colors.grey[700]!, width: 1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: widget.modeColor.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.play_arrow,
                                  color: widget.modeColor, size: 16),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Mission In Progress',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    missionService.currentMission!.missionName,
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.red[400]!.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: GestureDetector(
                                onTap: () => missionService.cancel(),
                                child: const Icon(Icons.stop,
                                    color: Colors.red, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Mission items scroll list fills remaining space
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 16),
                          child: Column(
                            children: [
                              for (int i = 0;
                                  i <
                                      missionService
                                          .currentMission!.items.length;
                                  i++)
                                _buildMissionExecutionItem(
                                  missionService.currentMission!.items[i],
                                  i,
                                  missionService.currentIndex,
                                  missionService,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Arrow button to reopen waypoint panel patterns
          if (_showArrowButton && _missionMode)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    _waypointPanelKey.currentState?.reopenPatternDialog();
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: widget.modeColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),

          // Slide-to-start mission button (only shown when mission is available and not running)
          Consumer<MissionExecutionService>(
            builder: (context, execService, _) {
              // Check if there are mission items in the waypoint panel
              final hasMissionItems =
                  _waypointPanelKey.currentState?.hasMissionItems() ?? false;

              if (!hasMissionItems || execService.isRunning || !_missionMode) {
                return const SizedBox.shrink();
              }

              return NavBottomBar(
                onSlideRight: () {
                  // Start mission using the WaypointPanel's method
                  if (_waypointPanelKey.currentState != null) {
                    _waypointPanelKey.currentState!.startMissionExecution();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Cannot start mission. Please try again.'),
                        backgroundColor: Colors.red.withOpacity(0.9),
                      ),
                    );
                  }
                },
                promptText: 'Slide to start mission',
                visible: true,
                color: widget.modeColor,
              );
            },
          ),
        ],
      );
    }

    // Map selection screen
    return Container(
      color: Colors.black87, // 60% - Primary background
      child: Row(
        children: [
          // Left side - Map List
          Container(
            width: 300,
            decoration: BoxDecoration(
              color: Colors.grey.shade900, // 30% - Secondary color
              border: Border(
                  right: BorderSide(color: Colors.grey.shade800, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800, // 30% - Secondary color
                    border: Border(
                        bottom:
                            BorderSide(color: Colors.grey.shade700, width: 1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Available Maps',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh,
                            color: widget.modeColor), // 10% - Accent for action
                        onPressed: () {
                          setState(() => _loadingMaps = true);
                          _loadMaps();
                        },
                      ),
                    ],
                  ),
                ),

                // Loading indicator or list
                Expanded(
                  child: _loadingMaps
                      ? Center(
                          child: CircularProgressIndicator(
                              color: widget.modeColor), // 10% - Accent
                        )
                      : _mapList.isEmpty
                          ? Center(
                              child: Text(
                                'No maps available',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _mapList.length,
                              itemBuilder: (context, index) {
                                final map = _mapList[index];
                                final isSelected = map == _selectedMap;

                                return Dismissible(
                                  key: Key(map),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (_) async {
                                    // Get the number of bookmarks for this map
                                    final bookmarksCount = _settingsProvider
                                            .bookmarks[map]?.length ??
                                        0;

                                    return await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: Text('Delete Map'),
                                            content: RichText(
                                              text: TextSpan(
                                                style: TextStyle(
                                                    color: Colors.white70),
                                                children: [
                                                  TextSpan(
                                                    text:
                                                        'Are you sure you want to delete "$map"',
                                                  ),
                                                  if (bookmarksCount > 0) ...[
                                                    TextSpan(
                                                      text:
                                                          ' and its $bookmarksCount associated bookmarks',
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                  ],
                                                  TextSpan(
                                                    text: '?',
                                                  ),
                                                ],
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                ),
                                                onPressed: () => Navigator.pop(
                                                    context, false),
                                                child: Text('Cancel'),
                                              ),
                                              TextButton(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: Colors.red,
                                                ),
                                                onPressed: () => Navigator.pop(
                                                    context, true),
                                                child: Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        ) ??
                                        false;
                                  },
                                  onDismissed: (_) {
                                    final removedIndex = index;
                                    setState(() {
                                      _mapList.removeAt(removedIndex);
                                      if (_selectedMap == map) {
                                        _selectedMap = _mapList.isNotEmpty
                                            ? _mapList.first
                                            : null;
                                      }
                                    });
                                    _deleteMap(map, removedIndex);
                                  },
                                  background: Container(
                                    color: Colors.transparent,
                                  ),
                                  secondaryBackground: Container(
                                    alignment: Alignment.centerRight,
                                    padding: EdgeInsets.only(right: 20),
                                    color: Colors.red.shade800,
                                    child: Icon(
                                      Icons.delete_forever,
                                      color: Colors.white,
                                    ),
                                  ),
                                  child: Container(
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.grey.shade800
                                          : Colors.grey.shade900,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.3),
                                                blurRadius: 3,
                                                offset: Offset(0, 2),
                                              )
                                            ]
                                          : null,
                                      border: Border.all(
                                        color: isSelected
                                            ? widget.modeColor
                                            : Colors.transparent,
                                        width: isSelected ? 1 : 0,
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        if (isSelected)
                                          Positioned(
                                            left: 0,
                                            top: 0,
                                            bottom: 0,
                                            width: 4,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: widget.modeColor,
                                                borderRadius: BorderRadius.only(
                                                  topLeft: Radius.circular(8),
                                                  bottomLeft:
                                                      Radius.circular(8),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ListTile(
                                          contentPadding: EdgeInsets.only(
                                            left: isSelected ? 16 : 16,
                                            right: 16,
                                          ),
                                          leading: FaIcon(
                                            FontAwesomeIcons.map,
                                            color: isSelected
                                                ? widget.modeColor
                                                : Colors.grey.shade600,
                                            size: 20,
                                          ),
                                          title: Text(
                                            map,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          onTap: () => setState(
                                              () => _selectedMap = map),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),

          // Right side - Controls
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon and title
                  Container(
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800, // 30% - Secondary color
                      shape: BoxShape.circle,
                    ),
                    child: FaIcon(
                      FontAwesomeIcons.route,
                      size: 80,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Navigation Mode',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Selected map display
                  Text(
                    _selectedMap != null
                        ? 'Selected: $_selectedMap'
                        : 'No map selected',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Start button - Primary action
                  ElevatedButton(
                    onPressed: _mapList.isEmpty || _selectedMap == null
                        ? null
                        : _startNavigation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget
                          .modeColor, // 10% - Primary accent for main action
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Start Navigation',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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

  // Helper method to build mission execution item
  Widget _buildMissionExecutionItem(MissionItem item, int index,
      int currentIndex, MissionExecutionService missionService) {
    final bool isActive = index == currentIndex;
    final bool isCompleted = index < currentIndex;

    // Get item-specific feedback for active items
    String? feedbackText;
    if (isActive) {
      switch (item.type) {
        case MissionItemType.goto:
          final distance = missionService.distanceRemaining;
          if (distance != null && distance > 0) {
            feedbackText = '${distance.toStringAsFixed(1)}m remaining';
          }
          break;
        case MissionItemType.wait:
          final remaining = missionService.waitTimeRemaining;
          if (remaining != null && remaining > 0) {
            feedbackText = '${remaining.toStringAsFixed(1)}s remaining';
          }
          break;
        case MissionItemType.dock:
        case MissionItemType.undock:
          feedbackText = DockingService.instance.status.replaceAll('_', ' ');
          break;
        default:
          break;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive ? Colors.grey[800] : Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? item.type.color : Colors.grey[700]!,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 4,
            height: 60,
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green
                  : (isActive ? item.type.color : Colors.grey[600]),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Item icon with status
                  Stack(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? Colors.green.withOpacity(0.2)
                              : item.type.color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Icon(
                            isCompleted ? Icons.check : item.type.icon,
                            color: isCompleted ? Colors.green : item.type.color,
                            size: 20,
                          ),
                        ),
                      ),
                      if (isActive)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Provider.of<BrandingProvider>(context,
                                      listen: false)
                                  .themeColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.grey[800]!,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(width: 12),

                  // Item details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${index + 1}. ',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              item.type.displayName,
                              style: TextStyle(
                                color: isCompleted
                                    ? Colors.green
                                    : item.type.color,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 2),
                        Text(
                          item.displayTitle,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isActive && feedbackText != null)
                          Container(
                            margin: EdgeInsets.only(top: 4),
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: item.type.color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              feedbackText,
                              style: TextStyle(
                                color: item.type.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
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
}
