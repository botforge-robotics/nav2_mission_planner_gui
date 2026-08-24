import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/modals/bookmark.dart';
import 'package:nav2_mission_planner/services/goal_service.dart';
import 'package:nav2_mission_planner/providers/ros2_data_provider.dart';
import 'package:nav2_mission_planner/widgets/navigation/nav_bottom_bar.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/providers/live_telemetry_provider.dart';
import 'package:nav2_mission_planner/services/get_map_list_service.dart';
import 'package:nav2_mission_planner/services/launch_service.dart';
import 'package:nav2_mission_planner/widgets/occupancy_grid_viewer.dart';
import 'package:nav2_mission_planner/widgets/sensors/image_viwer.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner/services/delete_map_service.dart';
import 'package:nav2_mission_planner/widgets/navigation/navigation_toolbar.dart';
import 'package:nav2_mission_planner/widgets/navigation/visibility_toolbar.dart';
import 'package:nav2_mission_planner/widgets/navigation/robot_telemetry_panel.dart';
import 'package:nav2_mission_planner/widgets/navigation/nav_banners.dart';
import 'package:nav2_mission_planner/widgets/navigation/joystick_overlay.dart';
import 'package:nav2_mission_planner/widgets/navigation/dock_undock_fab.dart';
import 'package:nav2_mission_planner/widgets/navigation/nav_goal_bar_and_feedback.dart';
import 'package:nav2_mission_planner/widgets/navigation/mission_execution_panel.dart';
import 'package:nav2_mission_planner/widgets/navigation/map_selection_view.dart';
import 'package:nav2_mission_planner/widgets/navigation/nav_bookmark_tap_handler.dart';
import 'package:nav2_mission_planner/services/pose_estimation_service.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'dart:async';
import 'package:nav2_msgs/action.dart';
import 'package:nav2_mission_planner/helpers/conversions.dart';
import 'package:nav2_mission_planner/widgets/bookmarks/bookmark_dialog.dart';
import 'package:uuid/uuid.dart';

import '../modals/mission.dart';
import '../widgets/waypoint_panel/waypoint_panel.dart';
import 'package:nav2_mission_planner/services/mission_execution_service.dart';
import 'package:nav2_mission_planner/services/tf_service.dart';
import 'package:nav2_mission_planner/services/docking_service.dart';
import 'package:nav2_mission_planner/services/mission_sync_service.dart';
import 'package:nav2_mission_planner/services/waypoint_sync_service.dart';
import 'package:nav2_mission_planner/screens/navigation/navigation_odometry_controller.dart';
import 'package:nav2_mission_planner/screens/navigation/navigation_path_controller.dart';

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
  // Map display variables
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  Widget? _mapWidget;

  // track which maps are currently being deleted
  final Set<String> _deletingMaps = {};

  // Odometry/velocity subscriptions + pose state — see
  // NavigationOdometryController's doc comment for why this is a separate
  // object rather than fields on this State.
  final _odometryController = NavigationOdometryController();
  // Last teleop command published by the joystick, and whether the stick is
  // currently deflected.
  double? _cmdLinear;
  double? _cmdAngular;
  bool _teleopActive = false;
  late SettingsProvider _settingsProvider;

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

  // Path subscription — see NavigationPathController's doc comment.
  final _pathController = NavigationPathController();

  // Add late variables to store provider references
  late ConnectionProvider _connectionProvider;
  bool _isInitialized = false; // Add this flag

  List<Bookmark> _localBookmarks = []; // Local list for bookmarks

  // Add this to the existing properties
  bool _isGoalActive = false;

  // Add waypoint mode properties
  bool _missionMode = false;
  List<Waypoint> _waypoints = [];

  bool _showWaypointPanel = false;

  // Add info banner for mission mode
  bool _showMissionInfoBanner = false;

  // Add info banner for initial pose
  bool _showInitialPoseBanner = false;

  // Add a new state variable to track if a mission is available to start
  bool _missionAvailable = false;

  // Add GlobalKey for WaypointPanel
  final GlobalKey<WaypointPanelState> _waypointPanelKey =
      GlobalKey<WaypointPanelState>();

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
      WaypointSyncService.instance.initialize(context);
      MissionSyncService.instance.initialize(context);
      _settingsProvider.addListener(_handleSettingsChange);
      _goalService.initialize(context: context);
      _isInitialized = true;
      _restoreIfAlreadyActive();
      _adoptRobotWaypointsIfLocalEmpty();
      _adoptRobotMissionsIfLocalEmpty();
    }
  }

  /// A fresh device (or a robot whose bookmarks were never saved to this
  /// one) has nothing in SettingsProvider's SharedPreferences — but the
  /// robot may already hold a real set via waypoint_store_node, pushed
  /// there by some other client. Adopt it in that case rather than leaving
  /// the bookmark list empty until someone happens to notice and re-enters
  /// them by hand.
  ///
  /// Deliberately one-shot and one-directional (robot -> here) only when
  /// local is empty: if this device already has bookmarks, they win — the
  /// push side (SettingsProvider._syncWaypointsToRobot) already keeps the
  /// robot's copy current from every local edit, so there's no ongoing
  /// merge to reconcile, just this one adoption for the empty case.
  void _adoptRobotWaypointsIfLocalEmpty() {
    final alreadyHasLocalBookmarks =
        _settingsProvider.bookmarks.values.any((list) => list.isNotEmpty);
    if (alreadyHasLocalBookmarks) return;

    void tryAdopt() {
      final fromRobot = WaypointSyncService.instance.fromRobot;
      if (fromRobot == null || !mounted) return;
      final hasAny = fromRobot.values.any((list) => list.isNotEmpty);
      if (!hasAny) return;
      _settingsProvider.adoptBookmarks(fromRobot);
      WaypointSyncService.instance.removeListener(tryAdopt);
    }

    // /waypoints is transient_local — if the robot already has a saved set,
    // the callback fires almost immediately on subscribe. If it never
    // fires, there was nothing to adopt (also correct: nothing to do).
    WaypointSyncService.instance.addListener(tryAdopt);
  }

  /// Same one-shot adoption as _adoptRobotWaypointsIfLocalEmpty, for
  /// missions instead of bookmarks.
  void _adoptRobotMissionsIfLocalEmpty() {
    final alreadyHasLocalMissions = _settingsProvider.missions.isNotEmpty;
    if (alreadyHasLocalMissions) return;

    void tryAdopt() {
      final fromRobot = MissionSyncService.instance.fromRobot;
      if (fromRobot == null || !mounted || fromRobot.isEmpty) return;
      _settingsProvider.adoptMissions(fromRobot);
      MissionSyncService.instance.removeListener(tryAdopt);
    }

    MissionSyncService.instance.addListener(tryAdopt);
  }

  /// Landing on this screen (fresh connect, app reopen/refresh) doesn't mean
  /// Nav2 isn't already running — a previous session may have started it
  /// and left it running robot-side, or another client did. Without this,
  /// _isNavigationActive stays at its default false and the UI shows "Start
  /// Navigation" over a stack that's actually already up, which just fails
  /// (or worse, tries to launch a second copy) the moment it's pressed.
  /// Mirrors _startNavigation's own post-success setup, minus the part that
  /// launches anything — it's already launched.
  ///
  /// Also restores WHICH map, not just that navigation is active — reading
  /// robot mode without this still leaves _selectedMap at whatever
  /// _loadMaps() defaults to (alphabetically/listing-order first), which is
  /// only right by coincidence. See ConnectionProvider.detectActiveMapName.
  Future<void> _restoreIfAlreadyActive() async {
    // waitUntilNav2Active, not a single isNav2Active() check — this runs
    // right at connect, when rosbridge/rosapi/the lifecycle service can
    // still be settling; a one-shot check racing that looks identical to
    // "Nav2 really isn't running" and silently gives up with no retry.
    // Short timeout (not its 45s default, meant for a genuine cold start)
    // since this is just absorbing that race, not waiting through one.
    final active = await _goalService.waitUntilNav2Active(
      timeout: const Duration(seconds: 12),
      pollInterval: const Duration(seconds: 2),
    );
    if (!mounted || !active || _isNavigationActive) return;

    final activeMap = await _connectionProvider.detectActiveMapName();
    if (!mounted) return;
    if (activeMap != null) {
      setState(() {
        _selectedMap = activeMap;
        _localBookmarks = _settingsProvider.bookmarks[activeMap] ?? [];
      });
    }

    OccupancyGridViewer.clearMapCache();
    setState(() => _isNavigationActive = true);
    _subscribeToOdometry();
    _subscribeToVelocity();
    PoseEstimationService.initializePublisher(context);
    setState(() => _mapWidget = _buildMapWidget());
  }

  @override
  void initState() {
    super.initState();
    // Odometry/velocity updates arrive via the controller's own
    // notifyListeners(); rebuild this screen exactly as the direct
    // setState() calls inside it used to, before that logic moved into
    // NavigationOdometryController.
    _odometryController.addListener(_onOdometryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _loadMaps();
      }
    });
  }

  void _onOdometryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _settingsProvider.removeListener(_handleSettingsChange);
    }
    _odometryController.removeListener(_onOdometryChanged);
    _pathController.unsubscribe();
    _pathController.disposeStream();
    super.dispose();
  }

  Future<void> _loadMaps() async {
    if (!mounted) return;

    final maps = await MapListService().getMapList(context);

    if (!mounted) return;

    setState(() {
      _mapList = maps;
      // Don't clobber a map _restoreIfAlreadyActive() already set from the
      // robot's real running map — only default to "first in the list"
      // when nothing better is already selected, or what's selected turned
      // out not to actually exist in this list.
      if (_selectedMap == null || !maps.contains(_selectedMap)) {
        _selectedMap = maps.isNotEmpty ? maps.first : null;
      }
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
        _subscribeToVelocity();
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
              backgroundColor:
                  (navReady ? Colors.green : Colors.orange).withOpacity(0.9),
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
      _odometryController.unsubscribeFromOdometry();
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
        });
        _odometryController.resetPose();

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

  // Thin delegates to _odometryController, kept as same-named methods so
  // every existing call site (_restoreIfAlreadyActive, _startNavigation)
  // reads unchanged. See NavigationOdometryController for the subscription
  // logic itself.
  void _subscribeToVelocity() {
    _odometryController.subscribeToVelocity(
      isNavigationActive: _isNavigationActive,
      connection: Provider.of<ConnectionProvider>(context, listen: false),
    );
  }

  void _subscribeToOdometry() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _odometryController.subscribeToOdometry(
      isNavigationActive: _isNavigationActive,
      connection: Provider.of<ConnectionProvider>(context, listen: false),
      topic: settings.navigationOdomTopic,
      type: settings.navigationOdomTopicType,
    );
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

      // Clear waypoints when switching away from mission mode
      if (!_missionMode) {
        _waypoints.clear();
        _showMissionInfoBanner = false;
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

  // Thin delegates to _pathController, kept as same-named methods so every
  // existing call site reads unchanged. See NavigationPathController for
  // the subscription logic itself.
  Future<void> _subscribeToPath() async {
    await _pathController.subscribe(
      connection: _connectionProvider,
      pathTopic: _settingsProvider.pathTopic,
    );
  }

  void _unsubscribePath() {
    _pathController.unsubscribe();
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

      // Fail fast if Nav2 never accepts / never starts (stack unconfigured).
      //
      // 40s, not 15s: every goal actually goes through dock_manager_node's
      // /undock relay (GoalService prefers it whenever advertised, which is
      // always), and when the robot is docked that relay undocks FIRST,
      // silently — its own timeout for that phase is 25s
      // (dock_manager_node.py's _UNDOCK_TIMEOUT_SEC) and it wires no
      // feedback callback until undocking finishes and the real
      // navigate_to_pose child goal is sent. A 15s watchdog here fired
      // during a perfectly normal, still-in-progress undock, cancelling the
      // goal client-side before real navigation ever started producing
      // feedback — the robot would go on to reach the goal via the
      // still-running server-side task while the UI had already declared
      // failure. 40s clears the 25s undock allowance with margin.
      await firstFeedback.future.timeout(
        const Duration(seconds: 40),
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
      pathStream: _pathController.pathStream,
      showLocalCostmap: _showLocalCostmap,
      showGlobalCostmap: _showGlobalCostmap,
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

        showBookmarkTapDialog(
          context: context,
          bookmark: bookmark,
          modeColor: widget.modeColor,
          missionMode: _missionMode,
          onSendGoal: () => _handleBookmarkGoal(bookmark),
          onDock: () => _handleDockBookmark(bookmark),
          onUndock: _handleUndockBookmark,
          onAddWaypoint: () => _addBookmarkAsWaypoint(bookmark),
          onDelete: () {
            final index = mapBookmarks.indexOf(matchingBookmark);
            if (index != -1) {
              setState(() {
                _localBookmarks.removeWhere((b) => b == bookmark);
                _settingsProvider.removeBookmark(_selectedMap!, index);
              });
            }
          },
          onEditDone: (icon, name, isDock) {
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
                // Position unchanged here — just (re)confirm it with the
                // robot in case this bookmark was newly marked as the dock
                // rather than repositioned.
                DockingService.instance.publishDockPose(
                  bookmark.positionX,
                  bookmark.positionY,
                  bookmark.theta,
                );
              }
            });
          },
          onReposition: () {
            setState(() {
              _repositioningBookmarkId = bookmark.id;
              _bookmarksMode = true;
            });
          },
        );
      },
      isGoalActive: _isGoalActive,
      waypoints: _waypoints,
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
            MissionInfoBanner(modeColor: widget.modeColor),

          // Placement hint banner (initial pose / goal / bookmarks)
          if (_showInitialPoseBanner ||
              (_goalMode && !_isGoalActive && !_showGoalBar) ||
              (_bookmarksMode && !_showGoalBar))
            PlacementHintBanner(
              modeColor: widget.modeColor,
              missionInfoBannerShowing: _showMissionInfoBanner,
              showInitialPoseBanner: _showInitialPoseBanner,
              goalMode: _goalMode,
              poseEstimationMode: _poseEstimationMode,
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
                if (_pathController.isSubscribed) {
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
          JoystickOverlay(
            visible: settings.joystickVisible,
            modeColor: widget.modeColor,
            onCommand: (linear, angular) {
              if (!mounted) return;
              setState(() {
                _cmdLinear = linear;
                _cmdAngular = angular;
                _teleopActive = linear != 0.0 || angular != 0.0;
              });
              // Shared with screens that don't own a joystick (Dashboard,
              // Robot Status) so they can read "is teleop active" from one
              // place — see LiveTelemetryProvider.
              Provider.of<LiveTelemetryProvider>(context, listen: false)
                  .reportTeleopCommand(linear, angular);
            },
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
                x: _odometryController.robotX,
                y: _odometryController.robotY,
                theta:
                    extractYawFromOriginQuaternion(_odometryController.robotQ),
                frame: _odometryController.poseFrame,
                poseAvailable: _odometryController.poseReceived,
                measuredLinear: _odometryController.measuredLinear,
                measuredAngular: _odometryController.measuredAngular,
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

          // Dock / Undock — always reachable here rather than only via the
          // dock bookmark's map tooltip. Reflects DockingService's own
          // state, which mirrors dock_manager_node's /dock_status — that
          // topic is the actual source of truth (robot-side, survives an
          // app restart or a different client entirely), this button is
          // just a reactive view onto it, same as the bookmark tooltip's
          // own Dock/Undock button.
          if (_selectedMap != null)
            Positioned(
              top: 16,
              right: 114,
              child: DockUndockFab(
                dockBookmark: _settingsProvider.getDockBookmark(_selectedMap!),
                onDock: () => _handleDockBookmark(
                    _settingsProvider.getDockBookmark(_selectedMap!)!),
                onUndock: _handleUndockBookmark,
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
            ),
          ),

          // Slide to confirm/cancel goal + navigation status/feedback overlay
          NavGoalBarAndFeedback(
            showGoalBar: _showGoalBar,
            onGoalSlideRight: () {
              setState(() {
                _showGoalBar = false;
              });
              _handleGoalSubmission();
            },
            onCancelPendingGoal: _cancelPendingGoal,
            showNavigationFeedback: _showNavigationFeedback,
            currentFeedback: _currentFeedback,
            onNavigationCancel: _handleNavigationCancel,
            modeColor: widget.modeColor,
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
                    robotPosition: Position(
                        x: _odometryController.robotX,
                        y: _odometryController.robotY,
                        theta: 0),
                    onShowMissionBanner: () {
                      setState(() {
                        _showMissionInfoBanner = true;
                      });
                    },
                    onMissionItemsChanged: _handleMissionItemsChanged,
                  ),
                ),
              ),
            ),

          // Mission execution side panel (full-height)
          MissionExecutionPanel(modeColor: widget.modeColor),

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
    return MapSelectionView(
      mapList: _mapList,
      selectedMap: _selectedMap,
      loadingMaps: _loadingMaps,
      bookmarksCountForMap: (map) =>
          _settingsProvider.bookmarks[map]?.length ?? 0,
      onRefresh: () {
        setState(() => _loadingMaps = true);
        _loadMaps();
      },
      onSelectMap: (map) => setState(() => _selectedMap = map),
      onDeleteConfirmed: (map, index) {
        setState(() {
          _mapList.removeAt(index);
          if (_selectedMap == map) {
            _selectedMap = _mapList.isNotEmpty ? _mapList.first : null;
          }
        });
        _deleteMap(map, index);
      },
      onStartNavigation: _startNavigation,
    );
  }
}
