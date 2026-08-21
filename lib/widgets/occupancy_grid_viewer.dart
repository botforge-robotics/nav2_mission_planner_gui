import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/helpers/conversions.dart';
import 'package:nav2_mission_planner/modals/bookmark.dart';
import 'package:nav2_mission_planner/modals/mission.dart';
import 'package:nav2_mission_planner/services/mission_execution_service.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/branding_provider.dart';
import 'package:nav_msgs/msg.dart' as nav_msgs;
import 'package:nav_msgs/srv.dart' as nav_srvs;
import 'package:sensor_msgs/msg.dart' as sensor_msgs;
import '../services/tf_service.dart';
import 'sensors/robot_position_marker.dart';
import 'navigation/Arrow_painter.dart';
import 'Simple_rotation_slider.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// RViz-style occupancy grid rendering. Row-major cell data -> RGBA8888,
/// Y-flipped so image pixel (0,0) is the grid's top-left in world space
/// (matches the rest of this file's map<->canvas pixel conventions).
///
/// [isCostmap] picks the color scheme:
///  - map (false): RViz "map" scheme — free=white, occupied=black, a
///    grayscale gradient in between, unknown=transparent. No longer tinted
///    by the app's mode color (that produced the "orange" occupied cells).
///  - costmap (true): RViz "costmap" scheme — free=transparent (so the
///    static map shows through), a blue->yellow->red heat gradient for
///    rising cost, lethal (100)=solid red.
Uint8List renderOccupancyGridRgba(nav_msgs.OccupancyGrid grid,
    {required bool isCostmap}) {
  final int width = grid.info.width;
  final int height = grid.info.height;
  final Uint8List pixels = Uint8List(width * height * 4);

  for (int y = height - 1; y >= 0; y--) {
    for (int x = 0; x < width; x++) {
      final int index = (height - 1 - y) * width + x;
      final int pixelIndex = (y * width + x) * 4;

      if (index >= grid.data.length) {
        // Out of bounds — transparent.
        pixels[pixelIndex + 3] = 0;
        continue;
      }

      final int value = grid.data[index].toInt();
      int r, g, b, a;

      if (value < 0) {
        // Unknown.
        r = g = b = 0;
        a = 0;
      } else if (!isCostmap) {
        // "map" scheme: linear grayscale, 0->white, 100->black.
        final int intensity = (255 - (value.clamp(0, 100) * 255 / 100))
            .round()
            .clamp(0, 255);
        r = g = b = intensity;
        a = 255;
      } else if (value == 0) {
        // "costmap" scheme, free space — fully transparent.
        r = g = b = 0;
        a = 0;
      } else {
        // "costmap" scheme, cost 1-100: blue (low) -> yellow -> red (high).
        final double t = value.clamp(1, 100) / 100.0;
        if (t < 0.5) {
          final double u = t / 0.5; // 0..1 across blue->yellow
          r = (u * 255).round();
          g = (u * 255).round();
          b = (255 * (1 - u)).round();
        } else {
          final double u = (t - 0.5) / 0.5; // 0..1 across yellow->red
          r = 255;
          g = (255 * (1 - u)).round();
          b = 0;
        }
        a = 160; // semi-transparent so it overlays the map cleanly
      }

      pixels[pixelIndex] = r;
      pixels[pixelIndex + 1] = g;
      pixels[pixelIndex + 2] = b;
      pixels[pixelIndex + 3] = a;
    }
  }
  return pixels;
}

Future<ui.Image> decodeGridRgba(Uint8List pixels, int width, int height) {
  final Completer<ui.Image> completer = Completer();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    (ui.Image image) => completer.complete(image),
  );
  return completer.future;
}

class OccupancyGridViewer extends StatefulWidget {
  final bool enabled;
  final String topic;
  final double scale;
  final Function(double)? onScaleChanged;
  final Color appModeColor;
  final bool showMarkers;
  final Stream<Map<String, dynamic>>? robotPositionStrem;
  final Stream<Map<String, dynamic>>? goalPositionStream;
  final Function(Map<String, dynamic>)? onMarkerPoseReceived;
  final VoidCallback? onMarkerPoseCancelled;
  final Stream<List<Map<String, dynamic>>>? pathStream;
  final bool disableLongPress;
  /// When true (localization / goal / bookmarks tool), mouse left-drag places
  /// a pose. Touch still uses long-press; pan stays for touch / non-placement.
  final bool placementMode;
  final List<Bookmark>? bookmarks;
  final Function(Bookmark)? onBookmarkTap;
  final bool isGoalActive;
  final List<Waypoint>? waypoints;
  final List<Waypoint>? previewWaypoints;
  final bool useMapService;
  final String mapServiceName;
  final bool showWaypointPath;
  // RViz-style overlays. Local costmap is published in odom frame (a
  // rolling window around the robot) and needs the odom->map TF to
  // composite correctly, hence tfMapFrame/tfOdomFrame — global costmap is
  // already in map frame, same as the static map, so it doesn't.
  final bool showLocalCostmap;
  final bool showGlobalCostmap;
  final bool showLaserScan;
  final String localCostmapTopic;
  final String globalCostmapTopic;
  final String laserScanTopic;
  final String tfMapFrame;
  final String tfOdomFrame;

  const OccupancyGridViewer({
    super.key,
    required this.enabled,
    required this.topic,
    this.scale = 1.0,
    this.onScaleChanged,
    required this.appModeColor,
    this.showMarkers = true,
    this.robotPositionStrem,
    this.goalPositionStream,
    this.onMarkerPoseReceived,
    this.onMarkerPoseCancelled,
    this.pathStream,
    this.disableLongPress = false,
    this.placementMode = false,
    this.bookmarks,
    this.onBookmarkTap,
    this.isGoalActive = false,
    this.waypoints,
    this.previewWaypoints,
    this.useMapService = false,
    this.mapServiceName = '/map_server/map',
    this.showLocalCostmap = false,
    this.showGlobalCostmap = false,
    this.showLaserScan = false,
    this.localCostmapTopic = '/local_costmap/costmap',
    this.globalCostmapTopic = '/global_costmap/costmap',
    this.laserScanTopic = '/scan_filtered',
    this.tfMapFrame = 'map',
    this.tfOdomFrame = 'odom',
    this.showWaypointPath = false,
  });

  // Cache fetched maps per service to avoid refetching on widget rebuilds
  // Note: This cache is cleared when navigation starts to ensure fresh map data
  static final Map<String, nav_msgs.OccupancyGrid> _serviceMapCache = {};

  // Static method to clear the map cache
  static void clearMapCache() {
    _serviceMapCache.clear();
  }

  @override
  State<OccupancyGridViewer> createState() => _OccupancyGridViewerState();
}

class _OccupancyGridViewerState extends State<OccupancyGridViewer> {
  Subscriber<nav_msgs.OccupancyGrid>? _subscriber;
  ui.Image? _mapImage;
  double _mapResolution = 0.05;
  int _mapWidth = 0;
  int _mapHeight = 0;
  bool _isLoading = false;
  String _statusMessage = 'Waiting for map data...';
  bool _hasError = false;
  double _initialMapFitScale = 1.0;

  // -- costmap / laser overlays --------------------------------------
  Subscriber<nav_msgs.OccupancyGrid>? _localCostmapSub;
  Subscriber<nav_msgs.OccupancyGrid>? _globalCostmapSub;
  Subscriber<sensor_msgs.LaserScan>? _laserScanSub;
  ui.Image? _localCostmapImage;
  nav_msgs.MapMetaData? _localCostmapInfo;
  ui.Image? _globalCostmapImage;
  nav_msgs.MapMetaData? _globalCostmapInfo;
  sensor_msgs.LaserScan? _latestScan;
  DateTime? _lastScanUiUpdate;
  DateTime? _lastLocalCostmapUiUpdate;
  bool _hasCalculatedInitialScale = false;

  // Controller for the interactive viewer
  final TransformationController _transformationController =
      TransformationController();

  // Add these variables for better zoom tracking
  double _currentScale = 1.0;
  bool _isFirstLoad = true;

  double _robotX = 0.0;
  double _robotY = 0.0;
  double _robotTheta = 0.0;
  // Add these variables to store map origin information
  double _mapOriginX = 0.0;
  double _mapOriginY = 0.0;
  double _mapOriginTheta = 0.0;

  double _markerX = 0.0;
  double _markerY = 0.0;
  double _markerTheta = 0.0;
  bool _isDraggingMarker = false;

  // Add to class state variables
  bool _showRotationSlider = false;
  Offset _rotationSliderCenter = Offset.zero;

  StreamSubscription? _positionSubscription;

  // Add goal position variables
  double _goalX = 0.0;
  double _goalY = 0.0;
  double _goalTheta = 0.0;
  bool _showGoal = false;
  StreamSubscription? _goalSubscription;

  StreamSubscription<List<Map<String, dynamic>>>? _pathSubscription;
  List<Map<String, dynamic>> _currentPath = [];

  // Remove multiple paths storage and colors
  final Color _pathColor = Colors.green.withOpacity(0.7);

  // Service polling
  Timer? _mapServiceTimer;
  bool _isFetchingMap = false;
  bool _mapFetched = false;

  /// Mouse left-drag pose placement (web/desktop). Touch keeps long-press.
  bool _mousePlacing = false;
  int? _mousePlacePointer;
  Offset? _mousePlaceOrigin;
  Offset? _mouseLastPos;
  final GlobalKey _viewerKey = GlobalKey();

  /// Convert a global pointer position into map-image (scene) pixels.
  Offset? _globalToMapPixels(Offset globalPosition) {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final viewportLocal = box.globalToLocal(globalPosition);
    return _transformationController.toScene(viewportLocal);
  }

  void _beginMarkerAt(Offset mapPixelPos) {
    setState(() {
      _markerX = mapPixelPos.dx;
      _markerY = mapPixelPos.dy;
      _markerTheta = 0;
      _isDraggingMarker = true;
      _showRotationSlider = false;
    });
  }

  void _updateMarkerAt(Offset mapPixelPos, {Offset? placeOrigin}) {
    // Drag direction sets yaw. Image Y grows downward; Flutter rotate is
    // clockwise, and marker uses theta+π/2 so atan2(dy, dx) matches the drag.
    double theta = _markerTheta;
    double x = mapPixelPos.dx;
    double y = mapPixelPos.dy;
    if (placeOrigin != null) {
      x = placeOrigin.dx;
      y = placeOrigin.dy;
      final dx = mapPixelPos.dx - placeOrigin.dx;
      final dy = mapPixelPos.dy - placeOrigin.dy;
      if (dx * dx + dy * dy > 4) {
        theta = math.atan2(dy, dx);
      }
    }
    setState(() {
      _markerX = x;
      _markerY = y;
      _markerTheta = theta;
      _isDraggingMarker = true;
    });
  }

  void _cancelMarkerPlacement() {
    setState(() {
      _isDraggingMarker = false;
      _showRotationSlider = false;
      _markerX = -100;
      _markerY = -100;
      _markerTheta = 0;
    });
    widget.onMarkerPoseCancelled?.call();
  }

  void _commitMarkerPose() {
    final targetPose = transformFromMapFrame(
      _markerX,
      _markerY,
      _markerTheta,
      _mapOriginX,
      _mapOriginY,
      _mapResolution,
      _mapHeight,
      _mapWidth,
      _mapOriginTheta,
    );
    widget.onMarkerPoseReceived?.call({
      'x': targetPose.targetX,
      'y': targetPose.targetY,
      'orientation': targetPose.orientation,
    });
    setState(() {
      _isDraggingMarker = false;
      _showRotationSlider = false;
      _markerX = -100;
      _markerY = -100;
      _markerTheta = 0;
    });
  }

  /// Release: swipe left → cancel; otherwise send immediately.
  void _finishMousePlacement(Offset? lastPos) {
    if (!_isDraggingMarker) return;
    final origin = _mousePlaceOrigin;
    if (origin != null && lastPos != null) {
      final dx = lastPos.dx - origin.dx;
      final dy = lastPos.dy - origin.dy;
      // Slide left to cancel (horizontal-dominant left swipe)
      if (dx < -36 && dx.abs() >= dy.abs()) {
        _cancelMarkerPlacement();
        return;
      }
    }
    _commitMarkerPose();
  }

  /// Touch long-press end: send (same as mouse release).
  void _endMarkerPlacement({required bool sendImmediately}) {
    if (!_isDraggingMarker) return;
    if (sendImmediately) {
      _commitMarkerPose();
      return;
    }
    setState(() {
      _isDraggingMarker = false;
      _showRotationSlider = true;
      _rotationSliderCenter = Offset(_markerX, _markerY);
    });
  }

  bool get _blockPanForMousePlacement =>
      widget.placementMode && !widget.disableLongPress && kIsWeb;

  // RViz-style view controls (web/desktop)
  double _viewRotation = 0.0;
  bool _middlePanning = false;
  bool _rightRotating = false;
  Offset? _viewDragLast;
  int? _viewDragPointer;

  void _applyViewportPan(Offset viewportDelta) {
    final m = Matrix4.fromFloat64List(
      Float64List.fromList(_transformationController.value.storage),
    );
    // Matrix maps scene→viewport; nudging translation pans like InteractiveViewer
    m.storage[12] += viewportDelta.dx;
    m.storage[13] += viewportDelta.dy;
    _transformationController.value = m;
  }

  void _applyScrollZoom(Offset viewportFocal, double scrollDy) {
    final double factor = scrollDy > 0 ? 0.9 : 1.1;
    final Matrix4 matrix = Matrix4.fromFloat64List(
      Float64List.fromList(_transformationController.value.storage),
    );
    final double currentScale = matrix.getMaxScaleOnAxis();
    final double newScale = (currentScale * factor).clamp(0.1, 10.0);
    final double ratio = newScale / currentScale;
    if ((ratio - 1.0).abs() < 1e-6) return;

    final Offset focalScene = _transformationController.toScene(viewportFocal);
    matrix.translate(focalScene.dx, focalScene.dy);
    matrix.scale(ratio, ratio, 1.0);
    matrix.translate(-focalScene.dx, -focalScene.dy);
    _transformationController.value = matrix;
    setState(() {
      _currentScale = newScale;
      if (widget.onScaleChanged != null) {
        widget.onScaleChanged!(newScale);
      }
    });
  }

  void _applyViewRotate(double deltaRadians) {
    setState(() {
      _viewRotation += deltaRadians;
    });
  }


  @override
  void initState() {
    super.initState();
    // Start with identity matrix (no transformations)
    _transformationController.value = Matrix4.identity();
    if (widget.useMapService) {
      // Check cache first
      if (OccupancyGridViewer._serviceMapCache
          .containsKey(widget.mapServiceName)) {
        _processMapMessage(
            OccupancyGridViewer._serviceMapCache[widget.mapServiceName]!);
        _mapFetched = true;
      } else {
        _startMapServicePolling();
      }
    } else {
      _subscribeToTopic();
    }
    if (!mounted) return;

    // Subscribe to position updates
    if (widget.robotPositionStrem != null) {
      _positionSubscription = widget.robotPositionStrem!.listen((data) {
        updateRobotPosition(
          data['x'],
          data['y'],
          data['q'],
        );
      });
    }

    // Subscribe to goal position updates
    if (widget.goalPositionStream != null) {
      _goalSubscription = widget.goalPositionStream!.listen((data) {
        updateGoalPosition(data);
      });
    }

    _pathSubscription = widget.pathStream?.listen((posesJson) {
      setState(() {
        _currentPath = posesJson;
      });
    });

    _updateOverlaySubscriptions();
  }

  void _updateOverlaySubscriptions() {
    if (!widget.enabled) return;
    final connection = Provider.of<ConnectionProvider>(context, listen: false);

    if (widget.showLocalCostmap && _localCostmapSub == null) {
      _localCostmapSub = Subscriber<nav_msgs.OccupancyGrid>(
        name: widget.localCostmapTopic,
        type: nav_msgs.OccupancyGrid().fullType,
        ros2: connection.ros2Client,
        callback: _processLocalCostmap,
        prototype: nav_msgs.OccupancyGrid(),
      );
    } else if (!widget.showLocalCostmap && _localCostmapSub != null) {
      _localCostmapSub?.shutdown();
      _localCostmapSub = null;
      setState(() {
        _localCostmapImage = null;
        _localCostmapInfo = null;
      });
    }

    if (widget.showGlobalCostmap && _globalCostmapSub == null) {
      _globalCostmapSub = Subscriber<nav_msgs.OccupancyGrid>(
        name: widget.globalCostmapTopic,
        type: nav_msgs.OccupancyGrid().fullType,
        ros2: connection.ros2Client,
        callback: _processGlobalCostmap,
        prototype: nav_msgs.OccupancyGrid(),
      );
    } else if (!widget.showGlobalCostmap && _globalCostmapSub != null) {
      _globalCostmapSub?.shutdown();
      _globalCostmapSub = null;
      setState(() {
        _globalCostmapImage = null;
        _globalCostmapInfo = null;
      });
    }

    if (widget.showLaserScan && _laserScanSub == null) {
      _laserScanSub = Subscriber<sensor_msgs.LaserScan>(
        name: widget.laserScanTopic,
        type: sensor_msgs.LaserScan().fullType,
        ros2: connection.ros2Client,
        // Lidars publish at 5-40Hz — a full-widget setState() per message
        // (rebuilding the whole map/bookmarks/waypoints tree, not just
        // repainting) starved the robot-position/bookmark rendering of
        // frame time under load, making them look "wrong"/laggy. Throttled
        // to a max ~8Hz, matching the actual visual update rate this
        // overlay needs.
        callback: (msg) {
          final now = DateTime.now();
          if (_lastScanUiUpdate != null &&
              now.difference(_lastScanUiUpdate!) <
                  const Duration(milliseconds: 120)) {
            _latestScan = msg; // keep freshest data without forcing a rebuild
            return;
          }
          _lastScanUiUpdate = now;
          setState(() => _latestScan = msg);
        },
        prototype: sensor_msgs.LaserScan(),
      );
    } else if (!widget.showLaserScan && _laserScanSub != null) {
      _laserScanSub?.shutdown();
      _laserScanSub = null;
      setState(() => _latestScan = null);
    }
  }

  void _processLocalCostmap(nav_msgs.OccupancyGrid message) async {
    if (message.info.width <= 0 || message.info.height <= 0) return;
    // Rolling window updates at ~5Hz — throttle the (expensive: full
    // image re-render + full-widget rebuild) UI update to ~4Hz so it
    // doesn't compete with robot-position/bookmark rendering.
    final now = DateTime.now();
    if (_lastLocalCostmapUiUpdate != null &&
        now.difference(_lastLocalCostmapUiUpdate!) <
            const Duration(milliseconds: 250)) {
      return;
    }
    _lastLocalCostmapUiUpdate = now;
    final pixels = renderOccupancyGridRgba(message, isCostmap: true);
    final image =
        await decodeGridRgba(pixels, message.info.width, message.info.height);
    if (!mounted) return;
    setState(() {
      _localCostmapImage = image;
      _localCostmapInfo = message.info;
    });
  }

  void _processGlobalCostmap(nav_msgs.OccupancyGrid message) async {
    if (message.info.width <= 0 || message.info.height <= 0) return;
    final pixels = renderOccupancyGridRgba(message, isCostmap: true);
    final image =
        await decodeGridRgba(pixels, message.info.width, message.info.height);
    if (!mounted) return;
    setState(() {
      _globalCostmapImage = image;
      _globalCostmapInfo = message.info;
    });
  }

  void _unsubscribeOverlays() {
    _localCostmapSub?.shutdown();
    _localCostmapSub = null;
    _globalCostmapSub?.shutdown();
    _globalCostmapSub = null;
    _laserScanSub?.shutdown();
    _laserScanSub = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    _unsubscribeOverlays();
    _transformationController.dispose();
    _positionSubscription?.cancel();
    _goalSubscription?.cancel();
    _pathSubscription?.cancel();
    _mapServiceTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(OccupancyGridViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.showLocalCostmap != widget.showLocalCostmap ||
        oldWidget.showGlobalCostmap != widget.showGlobalCostmap ||
        oldWidget.showLaserScan != widget.showLaserScan) {
      _updateOverlaySubscriptions();
    }

    // Check if waypoints changed (including order changes)
    bool waypointsChanged = false;
    if (widget.waypoints != null && oldWidget.waypoints != null) {
      if (widget.waypoints!.length != oldWidget.waypoints!.length) {
        waypointsChanged = true;
      } else {
        for (int i = 0; i < widget.waypoints!.length; i++) {
          if (widget.waypoints![i].id != oldWidget.waypoints![i].id) {
            waypointsChanged = true;
            break;
          }
        }
      }
    } else if ((widget.waypoints == null) != (oldWidget.waypoints == null)) {
      waypointsChanged = true;
    }

    // Force rebuild when waypoint path display changes
    if (widget.showWaypointPath != oldWidget.showWaypointPath ||
        waypointsChanged) {
      setState(() {
        // Just trigger a rebuild
      });
    }

    if (oldWidget.useMapService != widget.useMapService) {
      _unsubscribe();
      if (widget.useMapService) {
        _startMapServicePolling();
      } else {
        _subscribeToTopic();
      }
    } else if (oldWidget.topic != widget.topic ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.appModeColor != widget.appModeColor ||
        oldWidget.showMarkers != widget.showMarkers) {
      _unsubscribe();
      if (widget.useMapService) {
        _startMapServicePolling();
      } else {
        _subscribeToTopic();
      }
    }
  }

  void _subscribeToTopic() async {
    if (!widget.enabled) return;

    final connection = Provider.of<ConnectionProvider>(context, listen: false);

    setState(() {
      _statusMessage = 'Waiting for /map…';
      _hasError = false;
      _isLoading = true;
    });

    try {
      if (!mounted) return;

      _subscriber = Subscriber<nav_msgs.OccupancyGrid>(
        name: widget.topic,
        type: nav_msgs.OccupancyGrid().fullType,
        ros2: connection.ros2Client,
        callback: _processMapMessage,
        prototype: nav_msgs.OccupancyGrid(),
        // map_server / slam_toolbox publish TRANSIENT_LOCAL
        qos: const {
          'durability': 'transient_local',
          'reliability': 'reliable',
          'history': 'keep_last',
          'depth': 1,
        },
      );

      setState(() {
        _statusMessage = 'Subscribed to ${widget.topic}, waiting for data…';
        _hasError = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to subscribe: $e';
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _unsubscribe() {
    try {
      _subscriber?.shutdown();
      _subscriber = null;
      _mapServiceTimer?.cancel();
      _mapServiceTimer = null;
      //debugPrint('Unsubscribed from ${widget.topic}');
    } catch (e) {
      //debugPrint('Error unsubscribing: $e');
    }
  }


  Future<ui.Image> _createMapImage(nav_msgs.OccupancyGrid message) async {
    final pixels = renderOccupancyGridRgba(message, isCostmap: false);
    return decodeGridRgba(pixels, message.info.width, message.info.height);
  }

  void _processMapMessage(nav_msgs.OccupancyGrid message) async {
    // Add coordinate system validation
    _validateCoordinateSystem(message.info);

    // Store current transformation before updating the image
    final Matrix4? currentTransform = _mapImage != null
        ? Matrix4.copy(_transformationController.value)
        : null;

    // Store previous map metadata to detect changes
    final double previousMapWidth = _mapWidth.toDouble();
    final double previousMapHeight = _mapHeight.toDouble();
    final double previousMapResolution = _mapResolution;
    final double previousMapOriginX = _mapOriginX;
    final double previousMapOriginY = _mapOriginY;
    final double previousMapOriginTheta = _mapOriginTheta;

    // debugPrint('Processing map update! Width: ${message.info.width}, Height: ${message.info.height}');

    // Only show loading indicator for the first load
    if (_mapImage == null && mounted) {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Processing map data...';
        _hasError = false;
      });
    }

    try {
      // Extract map metadata including origin
      _mapWidth = message.info.width;
      _mapHeight = message.info.height;
      _mapResolution = message.info.resolution;

      // Store origin information
      _mapOriginX = message.info.origin.position.x;
      _mapOriginY = message.info.origin.position.y;

      _mapOriginTheta =
          extractYawFromOriginQuaternion(message.info.origin.orientation);

      //debugPrint('Map origin: ($_mapOriginX, $_mapOriginY), theta: $_mapOriginTheta');

      if (_mapWidth <= 0 || _mapHeight <= 0) {
        setState(() {
          _statusMessage = 'Invalid map dimensions: $_mapWidth x $_mapHeight';
          _hasError = true;
          _isLoading = false;
        });
        return;
      }

      // Check if map metadata has changed significantly
      final bool mapMetadataChanged = previousMapWidth != _mapWidth ||
          previousMapHeight != _mapHeight ||
          previousMapResolution != _mapResolution ||
          previousMapOriginX != _mapOriginX ||
          previousMapOriginY != _mapOriginY ||
          previousMapOriginTheta != _mapOriginTheta;

      // Use the more reliable image creation method
      final ui.Image image = await _createMapImage(message);

      if (mounted) {
        setState(() {
          _mapImage = image;
          _isLoading = false;
          _statusMessage = 'Map rendered successfully';
        });

        // Calculate initial scale to fit screen on first successful load
        if (!_hasCalculatedInitialScale) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _calculateInitialScale(context);
            }
          });
        }

        // If map metadata changed, recalculate robot position with new map parameters
        if (mapMetadataChanged && _mapWidth > 0 && _mapHeight > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _recalculateRobotPositionWithNewMap();
            }
          });
        }
      }

      // Restore the previous view — but COMPENSATED for the map having moved
      // underneath it.
      //
      // While SLAM is running, every update can change info.origin and grow
      // width/height as new area is discovered. Scene coordinates here are
      // image pixels, so pixel (0,0) means a different world point after the
      // map grows leftward or downward. Restoring the old matrix verbatim
      // therefore slides the entire world under the camera — the map appeared
      // to jump and drift on every update, where RViz stays still because it
      // draws in world coordinates with a camera independent of map size.
      //
      // Fix: shift the view by exactly the amount the world moved in pixel
      // space, so the world point under a given screen pixel is unchanged.
      // Zoom is untouched; only translation is corrected.
      //
      //   pixel_x(world) = (world.x - originX) / res
      //   pixel_y(world) = (originY + height*res - world.y) / res   (y flipped)
      if (currentTransform != null && !_isFirstLoad && _mapImage != null) {
        final Matrix4 restored = Matrix4.copy(currentTransform);
        // A resolution change re-scales everything, so pixel compensation is
        // meaningless — leave the view as-is rather than shifting it wrongly.
        if (previousMapResolution == _mapResolution && _mapResolution > 0) {
          final double dxPix =
              (previousMapOriginX - _mapOriginX) / _mapResolution;
          final double dyPix = (_mapOriginY - previousMapOriginY) /
                  _mapResolution +
              (_mapHeight.toDouble() - previousMapHeight);
          if (dxPix != 0.0 || dyPix != 0.0) {
            // Post-multiply in scene space: M' = M * T(-d) gives
            // M' * (p + d) == M * p, i.e. the same world point stays put.
            restored.translate(-dxPix, -dyPix);
          }
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _transformationController.value = restored;
          }
        });
      }

      // Note: caching and timer cancellation are handled in _startMapServicePolling
    } catch (e) {
      //debugPrint('Error processing map data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Error: $e';
          _hasError = true;
        });
      }
    }
  }

  void _calculateInitialScale(BuildContext context) {
    if (_mapImage == null || !mounted) return;

    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;
    final screenHeight = size.height;

    final imageWidth = _mapImage!.width.toDouble();
    final imageHeight = _mapImage!.height.toDouble();

    // Calculate scale to fit the image within the screen
    final widthScale = screenWidth / imageWidth;
    final heightScale = screenHeight / imageHeight;

    // Use the smaller scale to ensure the image fits within the screen
    _initialMapFitScale = widthScale < heightScale ? widthScale : heightScale;
    _initialMapFitScale *= 0.9; // 90% of full fit for some padding

    // Set current scale to initial fit scale
    _currentScale = _initialMapFitScale;

    _hasCalculatedInitialScale = true;

    // Only reset view on first load
    if (_isFirstLoad) {
      _resetView();
      _isFirstLoad = false;
    }

    // Notify parent about the initial scale
    if (widget.onScaleChanged != null) {
      widget.onScaleChanged!(_initialMapFitScale);
    }

    //debugPrint('Initial map scale calculated: $_initialMapFitScale');
  }

  void _resetView() {
    if (_mapImage == null) return;

    final size = MediaQuery.of(context).size;
    final imageWidth = _mapImage!.width.toDouble();
    final imageHeight = _mapImage!.height.toDouble();

    // Calculate scale to fit the image within the screen
    final widthScale = size.width / imageWidth;
    final heightScale = size.height / imageHeight;
    final scale = (widthScale < heightScale ? widthScale : heightScale) * 0.9;

    // Important: update the _currentScale when resetting
    _currentScale = scale;

    // For proper centering, we need to:
    // 1. Reset to identity
    // 2. Scale appropriately
    // 3. Translate to center
    final matrix = Matrix4.identity();

    // Scale first (this is important for proper calculation)
    matrix.scale(scale, scale);

    // Then translate to center the scaled image
    final scaledWidth = imageWidth * scale;
    final scaledHeight = imageHeight * scale;
    final dx = (size.width - scaledWidth) / 2;
    final dy = (size.height - scaledHeight) / 2;
    matrix.translate(dx / scale, dy / scale);

    // Apply the transformation
    _transformationController.value = matrix;
    _viewRotation = 0.0;

    // Notify parent about scale change
    if (widget.onScaleChanged != null) {
      widget.onScaleChanged!(scale);
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background
        Container(
          color: Colors.black26,
          width: double.infinity,
          height: double.infinity,
        ),

        // Map or loading state
        if (_mapImage != null && !_isLoading)
          // Outer Listener: RViz-style middle-pan / scroll-zoom / right-rotate
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final box =
                    _viewerKey.currentContext?.findRenderObject() as RenderBox?;
                if (box == null) return;
                final local = box.globalToLocal(event.position);
                _applyScrollZoom(local, event.scrollDelta.dy);
              }
            },
            onPointerDown: (details) {
              final isMouse = details.kind == PointerDeviceKind.mouse ||
                  details.kind == PointerDeviceKind.stylus;
              if (!isMouse) return;
              if ((details.buttons & kMiddleMouseButton) != 0) {
                _middlePanning = true;
                _rightRotating = false;
                _viewDragPointer = details.pointer;
                _viewDragLast = details.localPosition;
              } else if ((details.buttons & kSecondaryMouseButton) != 0) {
                _rightRotating = true;
                _middlePanning = false;
                _viewDragPointer = details.pointer;
                _viewDragLast = details.localPosition;
              }
            },
            onPointerMove: (details) {
              if (details.pointer != _viewDragPointer ||
                  _viewDragLast == null) {
                return;
              }
              final delta = details.localPosition - _viewDragLast!;
              _viewDragLast = details.localPosition;
              if (_middlePanning) {
                _applyViewportPan(delta);
              } else if (_rightRotating) {
                // Horizontal drag rotates view (RViz-like)
                _applyViewRotate(delta.dx * 0.01);
              }
            },
            onPointerUp: (details) {
              if (details.pointer != _viewDragPointer) return;
              _middlePanning = false;
              _rightRotating = false;
              _viewDragPointer = null;
              _viewDragLast = null;
            },
            onPointerCancel: (details) {
              if (details.pointer != _viewDragPointer) return;
              _middlePanning = false;
              _rightRotating = false;
              _viewDragPointer = null;
              _viewDragLast = null;
            },
            child: InteractiveViewer(
              key: _viewerKey,
              transformationController: _transformationController,
              constrained: false,
              minScale: 0.1,
              maxScale: 10.0,
              // Left-drag reserved for pose/goal on web; pan via middle mouse.
              // Touch still pans/zooms via InteractiveViewer.
              panEnabled: !_blockPanForMousePlacement && !_middlePanning,
              scaleEnabled: !kIsWeb, // web uses scroll wheel zoom
              boundaryMargin: const EdgeInsets.all(double.infinity),
              onInteractionStart: (details) {
                if (_mousePlacing || _middlePanning || _rightRotating) return;
                setState(() {
                  final scale =
                      _transformationController.value.getMaxScaleOnAxis();
                  _currentScale = scale;
                  if (widget.onScaleChanged != null) {
                    widget.onScaleChanged!(scale);
                  }
                });
              },
              onInteractionUpdate: (details) {
                if (_middlePanning || _rightRotating) return;
                setState(() {
                  final scale =
                      _transformationController.value.getMaxScaleOnAxis();
                  _currentScale = scale;
                  if (widget.onScaleChanged != null) {
                    widget.onScaleChanged!(scale);
                  }
                });
              },
              onInteractionEnd: (details) {},
              child: Transform.rotate(
                angle: _viewRotation,
                alignment: Alignment.center,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (details) {
                    if (widget.disableLongPress || !widget.placementMode) {
                      return;
                    }
                    final isMouse = details.kind == PointerDeviceKind.mouse ||
                        details.kind == PointerDeviceKind.stylus;
                    if (!isMouse) return;
                    // Only primary (left) for pose/goal — ignore middle/right
                    if ((details.buttons & kPrimaryMouseButton) == 0) return;
                    if ((details.buttons & kMiddleMouseButton) != 0) return;
                    if ((details.buttons & kSecondaryMouseButton) != 0) return;

                    final mapPixelPos = details.localPosition;
                    _mousePlacing = true;
                    _mousePlacePointer = details.pointer;
                    _mousePlaceOrigin = mapPixelPos;
                    _mouseLastPos = mapPixelPos;
                    _beginMarkerAt(mapPixelPos);
                  },
                  onPointerMove: (details) {
                    if (!_mousePlacing ||
                        details.pointer != _mousePlacePointer) {
                      return;
                    }
                    _mouseLastPos = details.localPosition;
                    _updateMarkerAt(
                      details.localPosition,
                      placeOrigin: _mousePlaceOrigin,
                    );
                  },
                  onPointerUp: (details) {
                    if (!_mousePlacing ||
                        details.pointer != _mousePlacePointer) {
                      return;
                    }
                    final last = details.localPosition;
                    _mousePlacing = false;
                    _mousePlacePointer = null;
                    _finishMousePlacement(last);
                    _mousePlaceOrigin = null;
                    _mouseLastPos = null;
                  },
                  onPointerCancel: (details) {
                    if (details.pointer != _mousePlacePointer) return;
                    _mousePlacing = false;
                    _mousePlacePointer = null;
                    _mousePlaceOrigin = null;
                    _mouseLastPos = null;
                    _cancelMarkerPlacement();
                  },
                  child: GestureDetector(
                    onLongPressStart: widget.disableLongPress
                        ? null
                        : (details) {
                            if (_mousePlacing) return;
                            final mapPixelPos =
                                _globalToMapPixels(details.globalPosition) ??
                                    details.localPosition;
                            _beginMarkerAt(mapPixelPos);
                          },
                    onLongPressMoveUpdate: widget.disableLongPress
                        ? null
                        : (details) {
                            if (_mousePlacing) return;
                            final mapPixelPos =
                                _globalToMapPixels(details.globalPosition) ??
                                    details.localPosition;
                            _updateMarkerAt(
                              mapPixelPos,
                              placeOrigin: Offset(_markerX, _markerY),
                            );
                          },
                    onLongPressEnd: widget.disableLongPress
                        ? null
                        : (details) {
                            if (_mousePlacing) return;
                            _endMarkerPlacement(sendImmediately: true);
                          },
                    child: Stack(
                      children: [
                        // 1. Base map image
                        RawImage(
                          key: ValueKey(_mapImage.hashCode),
                          image: _mapImage,
                          fit: BoxFit.none,
                          filterQuality: FilterQuality.medium,
                        ),

                    // 1b. Global costmap (already in map frame — no TF needed)
                    if (widget.showGlobalCostmap &&
                        _globalCostmapImage != null &&
                        _globalCostmapInfo != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: CostmapImagePainter(
                              image: _globalCostmapImage!,
                              costmapInfo: _globalCostmapInfo!,
                              mapOriginX: _mapOriginX,
                              mapOriginY: _mapOriginY,
                              mapResolution: _mapResolution,
                              mapHeight: _mapHeight,
                              mapWidth: _mapWidth,
                              mapOriginTheta: _mapOriginTheta,
                            ),
                          ),
                        ),
                      ),

                    // 1c. Local costmap (odom frame — composited via the
                    // live odom->map TF so it re-aligns as odom drifts).
                    if (widget.showLocalCostmap &&
                        _localCostmapImage != null &&
                        _localCostmapInfo != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: CostmapImagePainter(
                              image: _localCostmapImage!,
                              costmapInfo: _localCostmapInfo!,
                              mapOriginX: _mapOriginX,
                              mapOriginY: _mapOriginY,
                              mapResolution: _mapResolution,
                              mapHeight: _mapHeight,
                              mapWidth: _mapWidth,
                              mapOriginTheta: _mapOriginTheta,
                              frameTransform: TFService.instance
                                  .getFrameTransform(
                                      widget.tfMapFrame, widget.tfOdomFrame),
                            ),
                          ),
                        ),
                      ),

                    // 1d. Laser scan points
                    if (widget.showLaserScan && _latestScan != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: LaserScanPainter(
                              scan: _latestScan!,
                              robotWorldX: _lastWorldRobotX,
                              robotWorldY: _lastWorldRobotY,
                              robotWorldTheta:
                                  quaternionToEuler(_lastWorldRobotQ)[2],
                              mapOriginX: _mapOriginX,
                              mapOriginY: _mapOriginY,
                              mapResolution: _mapResolution,
                              mapHeight: _mapHeight,
                              mapWidth: _mapWidth,
                              mapOriginTheta: _mapOriginTheta,
                              scale: _currentScale,
                            ),
                          ),
                        ),
                      ),

                    // 2. Path (if active goal or mission execution)
                    if (_mapImage != null &&
                        (widget.isGoalActive ||
                            Provider.of<MissionExecutionService>(context,
                                    listen: false)
                                .isRunning))
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: PathPainter(
                              path: _currentPath,
                              mapOriginX: _mapOriginX,
                              mapOriginY: _mapOriginY,
                              mapResolution: _mapResolution,
                              mapHeight: _mapHeight,
                              mapWidth: _mapWidth,
                              mapOriginTheta: _mapOriginTheta,
                              scale: _currentScale,
                              pathColor: _pathColor,
                            ),
                          ),
                        ),
                      ),

                    // 2b. Planned Waypoint path - only show when not in mission execution
                    if (_mapImage != null &&
                        widget.showWaypointPath &&
                        widget.waypoints != null &&
                        widget.waypoints!.isNotEmpty &&
                        !Provider.of<MissionExecutionService>(context,
                                listen: false)
                            .isRunning)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: WaypointPathPainter(
                              robotX: _robotX,
                              robotY: _robotY,
                              waypoints: widget.waypoints!,
                              mapOriginX: _mapOriginX,
                              mapOriginY: _mapOriginY,
                              mapResolution: _mapResolution,
                              mapHeight: _mapHeight,
                              mapWidth: _mapWidth,
                              mapOriginTheta: _mapOriginTheta,
                              scale: _currentScale,
                              color: widget.appModeColor,
                            ),
                          ),
                        ),
                      ),

                    // 2c. Preview Waypoint path
                    if (_mapImage != null &&
                        widget.previewWaypoints != null &&
                        widget.previewWaypoints!.isNotEmpty) ...[
                      // Draw preview path lines
                      ...List.generate(widget.previewWaypoints!.length - 1,
                          (i) {
                        final waypoint1 = widget.previewWaypoints![i];
                        final waypoint2 = widget.previewWaypoints![i + 1];

                        final transformedPose1 = transformToMapFrame(
                          waypoint1.position.x,
                          waypoint1.position.y,
                          eulerToQuaternion(0, 0, waypoint1.position.theta),
                          _mapOriginX,
                          _mapOriginY,
                          _mapResolution,
                          _mapHeight,
                          _mapWidth,
                          _mapOriginTheta,
                        );

                        final transformedPose2 = transformToMapFrame(
                          waypoint2.position.x,
                          waypoint2.position.y,
                          eulerToQuaternion(0, 0, waypoint2.position.theta),
                          _mapOriginX,
                          _mapOriginY,
                          _mapResolution,
                          _mapHeight,
                          _mapWidth,
                          _mapOriginTheta,
                        );

                        return Positioned.fill(
                          child: CustomPaint(
                            painter: DashedLinePainter(
                              start: Offset(
                                  transformedPose1.x, transformedPose1.y),
                              end: Offset(
                                  transformedPose2.x, transformedPose2.y),
                              color: Colors.orange.withOpacity(0.8),
                              strokeWidth: 2.0,
                              dashLength: 5.0,
                              dashGap: 3.0,
                            ),
                          ),
                        );
                      }),

                      // Draw preview waypoint markers
                      ...List.generate(widget.previewWaypoints!.length, (i) {
                        final waypoint = widget.previewWaypoints![i];
                        final transformedPose = transformToMapFrame(
                          waypoint.position.x,
                          waypoint.position.y,
                          eulerToQuaternion(0, 0, waypoint.position.theta),
                          _mapOriginX,
                          _mapOriginY,
                          _mapResolution,
                          _mapHeight,
                          _mapWidth,
                          _mapOriginTheta,
                        );

                        return Positioned(
                          left: transformedPose.x - 8,
                          top: transformedPose.y - 8,
                          child: Stack(
                            children: [
                              // Solid circle
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              // Orientation arrow
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: OrientationArrowPainter(
                                    angle: transformedPose.theta,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],

                    // 3. Waypoints (add here, before bookmarks)
                    if (widget.waypoints != null &&
                        widget.waypoints!.isNotEmpty) ...[
                      ...widget.waypoints!.asMap().entries.map((entry) {
                        final index = entry.key;
                        final waypoint = entry.value;
                        final transformedPose = transformToMapFrame(
                          waypoint.position.x,
                          waypoint.position.y,
                          eulerToQuaternion(0, 0, waypoint.position.theta),
                          _mapOriginX,
                          _mapOriginY,
                          _mapResolution,
                          _mapHeight,
                          _mapWidth,
                          _mapOriginTheta,
                        );

                        // Find if this waypoint corresponds to a bookmark
                        Color waypointColor = widget.appModeColor;
                        if (widget.bookmarks != null && waypoint.name != null) {
                          try {
                            final matchingBookmark =
                                widget.bookmarks!.firstWhere(
                              (bookmark) =>
                                  bookmark.name == waypoint.name &&
                                  bookmark.positionX == waypoint.position.x &&
                                  bookmark.positionY == waypoint.position.y,
                            );
                            // Use the same color logic as in BookmarkWidget
                            waypointColor = matchingBookmark.isGoalActive
                                ? Colors.green
                                : Provider.of<BrandingProvider>(context,
                                        listen: false)
                                    .themeColor;
                          } catch (e) {
                            // No matching bookmark found, keep default color
                          }
                        }

                        // Determine if this should show a number (only for position-based waypoints)
                        String? markerNumber;
                        if (waypoint.name != null &&
                            waypoint.name!.startsWith('Waypoint ')) {
                          // Extract the number from the waypoint name (e.g., "Waypoint 1" -> "1")
                          final match = RegExp(r'Waypoint (\d+)')
                              .firstMatch(waypoint.name!);
                          if (match != null) {
                            markerNumber = match.group(1);
                          }
                        }

                        return _buildTargetMarker(
                          transformedPose.x,
                          transformedPose.y,
                          transformedPose.theta,
                          color: waypointColor, // Use the determined color
                          number:
                              markerNumber, // Only show number for position-based waypoints
                        );
                      }),
                    ],

                    // 4. Bookmarks
                    if (widget.bookmarks != null) ...[
                      ...widget.bookmarks!.map((bookmark) {
                        final transformedPose = transformToMapFrame(
                          bookmark.positionX,
                          bookmark.positionY,
                          geometry_msgs.Quaternion(
                            x: 0,
                            y: 0,
                            z: 0,
                            w: 1,
                          ),
                          _mapOriginX,
                          _mapOriginY,
                          _mapResolution,
                          _mapHeight,
                          _mapWidth,
                          _mapOriginTheta,
                        );
                        return Positioned(
                          left: transformedPose.x - (40 / 2),
                          top: transformedPose.y - (40 / 2),
                          child: Transform.scale(
                            scale: 1 / _currentScale,
                            alignment: Alignment.center,
                            child: GestureDetector(
                              onTap: widget.isGoalActive
                                  ? null
                                  : () {
                                      if (widget.onBookmarkTap != null) {
                                        widget.onBookmarkTap!(bookmark);
                                      }
                                    },
                              child: BookmarkWidget(
                                x: bookmark.positionX,
                                y: bookmark.positionY,
                                theta: bookmark.theta,
                                color: bookmark.isGoalActive
                                    ? Colors.green
                                    : Provider.of<BrandingProvider>(context,
                                            listen: false)
                                        .themeColor,
                                size: 40.0,
                                icon: bookmark.icon,
                                label: bookmark.name,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],

                    // 5. Robot marker
                    if (_mapImage != null && !_isLoading)
                      Positioned(
                        left: _robotX - 15,
                        top: _robotY - 15,
                        child: IgnorePointer(
                          child: Transform.scale(
                            scale: 1 / _currentScale,
                            alignment: Alignment.center,
                            child: RobotPositionMarker(
                              x: 0,
                              y: 0,
                              theta: _robotTheta,
                              color: Colors.green,
                              size: 30.0,
                            ),
                          ),
                        ),
                      ),

                    // 6. Goal marker
                    if (widget.showMarkers && _showGoal)
                      _buildTargetMarker(_goalX, _goalY, _goalTheta,
                          color: Colors.green),

                    // 7. Pose estimation marker (only while placing)
                    if (widget.showMarkers &&
                        (_isDraggingMarker || _showRotationSlider))
                      _buildTargetMarker(_markerX, _markerY, _markerTheta),

                    // 8. Rotation slider
                    if (_showRotationSlider)
                      Positioned(
                        left: _rotationSliderCenter.dx - 50,
                        top: _rotationSliderCenter.dy - 50,
                        child: Transform.scale(
                          scale: 1 / _currentScale,
                          child: GestureDetector(
                            onPanStart: (details) {
                              _updateRotation(details.localPosition);
                            },
                            onPanUpdate: (details) {
                              _updateRotation(details.localPosition);
                            },
                            onPanEnd: (_) {
                              _commitMarkerPose();
                            },
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black38,
                              ),
                              child: CustomPaint(
                                painter: SimpleRotationSliderPainter(
                                  angle: _markerTheta,
                                  color: widget.appModeColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ),
            ),
          )
        else
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_hasError)
                  CircularProgressIndicator(color: widget.appModeColor)
                else
                  const Icon(Icons.error_outline, color: Colors.red, size: 40),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _hasError ? Colors.red : Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (_hasError) ...[
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry Connection'),
                    onPressed: () {
                      _unsubscribe();
                      if (widget.useMapService) {
                        _startMapServicePolling();
                      } else {
                        _subscribeToTopic();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),

        // Reset view button (always on top)
        if (_mapImage != null && !_isLoading)
          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'resetMapView',
              mini: true,
              backgroundColor: widget.appModeColor.withOpacity(0.8),
              onPressed: _resetView,
              tooltip: 'Fit map to screen',
              child: const Icon(
                Icons.fit_screen,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  // Add new validation method
  void _validateCoordinateSystem(nav_msgs.MapMetaData info) {
    assert(info.resolution > 0, 'Invalid map resolution (must be > 0)');
    assert(info.origin.position.z == 0, 'Z position must be zero for 2D maps');

    final q = info.origin.orientation;
    final rollPitchYaw = quaternionToEuler(q);
    assert(rollPitchYaw[0].abs() < 1e-4 && rollPitchYaw[1].abs() < 1e-4,
        'Map orientation must be 2D (only yaw rotation supported)');
  }

  Widget _buildTargetMarker(double markerX, double markerY, double markerTheta,
      {Color color = Colors.greenAccent, String? number}) {
    // Calculate size based on current scale - larger when zoomed out
    final markerSize = 60.0 * (1 / _currentScale);
    // Adjust positioning based on dynamic size
    final halfWidth = markerSize / 2;
    final height = markerSize;

    return Positioned(
      // Position custom painter exactly at the marker position
      left: markerX - halfWidth, // Center horizontally based on actual size
      top: markerY - height, // Bottom of arrow at marker point
      child: IgnorePointer(
        child: Transform.rotate(
          angle: markerTheta + math.pi / 2,
          alignment: Alignment.bottomCenter, // Pivot at bottom center
          child: CustomPaint(
            size: Size(markerSize, markerSize),
            painter: ArrowPainter(
              color: color,
              angle: markerTheta + math.pi / 2,
              number: number,
            ),
          ),
        ),
      ),
    );
  }

  // Update the rotation slider positioning and painting logic
  void _updateRotation(Offset localPosition) {
    final center = Offset(50, 50);
    final touchOffset = localPosition - center;

    // Calculate angle where 0 is along x-axis, counterclockwise increases angle
    final mapAngle = math.atan2(touchOffset.dy, touchOffset.dx);

    setState(() {
      _markerTheta = mapAngle;
    });
  }

  // Store the last received robot position in world coordinates
  double _lastWorldRobotX = 0.0;
  double _lastWorldRobotY = 0.0;
  geometry_msgs.Quaternion _lastWorldRobotQ = geometry_msgs.Quaternion();

  void updateRobotPosition(double x, double y, geometry_msgs.Quaternion q) {
    // Store the world coordinates for recalculation when map changes
    _lastWorldRobotX = x;
    _lastWorldRobotY = y;
    _lastWorldRobotQ = q;

    if (_mapWidth > 0 && _mapHeight > 0) {
      // Only transform if we have valid map data
      final transformedPose = transformToMapFrame(
        x,
        y,
        q,
        _mapOriginX,
        _mapOriginY,
        _mapResolution,
        _mapHeight,
        _mapWidth,
        _mapOriginTheta,
      );

      setState(() {
        _robotX = transformedPose.x;
        _robotY = transformedPose.y;
        _robotTheta = transformedPose.theta;
      });
    } else {
      // Store raw values until map is loaded
      setState(() {
        _robotX = x;
        _robotY = y;
      });
    }
  }

  // Recalculate robot position when map metadata changes
  void _recalculateRobotPositionWithNewMap() {
    if (_mapWidth > 0 && _mapHeight > 0) {
      // Recalculate robot position with new map parameters
      final transformedPose = transformToMapFrame(
        _lastWorldRobotX,
        _lastWorldRobotY,
        _lastWorldRobotQ,
        _mapOriginX,
        _mapOriginY,
        _mapResolution,
        _mapHeight,
        _mapWidth,
        _mapOriginTheta,
      );

      setState(() {
        _robotX = transformedPose.x;
        _robotY = transformedPose.y;
        _robotTheta = transformedPose.theta;
      });
    }
  }

  // Add goal position update method
  void updateGoalPosition(Map<String, dynamic> data) {
    if (mounted) {
      if (_mapWidth > 0 && _mapHeight > 0) {
        // Only transform if we have valid map data
        final transformedPose = transformToMapFrame(
          data['x'],
          data['y'],
          data['orientation'],
          _mapOriginX,
          _mapOriginY,
          _mapResolution,
          _mapHeight,
          _mapWidth,
          _mapOriginTheta,
        );

        setState(() {
          _goalX = transformedPose.x;
          _goalY = transformedPose.y;
          _goalTheta = transformedPose.theta;
          _showGoal = data['show'] ?? false;
        });
      }
    }
  }

  void _startMapServicePolling() {
    // Load via GetMap (/map_server/map) — same as original Mission Planner.
    // Retries until map_server is configured+active and the service appears.
    final connection = Provider.of<ConnectionProvider>(context, listen: false);

    _mapServiceTimer?.cancel();
    _mapFetched = false;

    setState(() {
      _statusMessage = 'Loading map via ${widget.mapServiceName}…';
      _hasError = false;
      _isLoading = true;
    });

    var attempt = 0;
    Future<void> fetchOnce() async {
      if (!mounted || _mapFetched || _isFetchingMap) return;
      _isFetchingMap = true;
      attempt++;
      try {
        if (mounted) {
          setState(() {
            _statusMessage =
                'Getting map (attempt $attempt)…\n${widget.mapServiceName}';
            _hasError = false;
            _isLoading = true;
          });
        }

        final client = ServiceClient<nav_srvs.GetMap, nav_srvs.GetMapRequest,
            nav_srvs.GetMapResponse>(
          ros2: connection.ros2Client,
          name: widget.mapServiceName,
          type: nav_srvs.GetMap().fullType,
          serviceType: nav_srvs.GetMap(),
          timeout: 30,
          // Service may not exist until map_server is activated
          checkExists: false,
        );

        final response = await client.call(nav_srvs.GetMapRequest());
        if (!mounted || _mapFetched) return;

        final grid = response.map;
        if (grid.info.width <= 0 ||
            grid.info.height <= 0 ||
            grid.data.isEmpty) {
          throw StateError(
            'Empty map from ${widget.mapServiceName} '
            '(${grid.info.width}x${grid.info.height}, data=${grid.data.length})',
          );
        }

        _mapFetched = true;
        OccupancyGridViewer._serviceMapCache[widget.mapServiceName] = grid;
        _mapServiceTimer?.cancel();
        _mapServiceTimer = null;
        _processMapMessage(grid);
      } catch (e) {
        if (!mounted || _mapFetched) return;
        // Soft status while waiting for map_server lifecycle
        final msg = e.toString();
        final waiting = msg.contains('does not exist') ||
            msg.contains('timeout') ||
            msg.contains('Timeout') ||
            msg.contains('failed');
        setState(() {
          _statusMessage = waiting
              ? 'Waiting for map_server… (attempt $attempt)\n'
                  'Map must finish loading on the robot'
              : 'Map not ready yet… retrying\n$e';
          _hasError = !waiting;
          _isLoading = true;
        });
      } finally {
        _isFetchingMap = false;
      }
    }

    unawaited(fetchOnce());
    _mapServiceTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(fetchOnce());
    });
  }
}

class MapPainter extends CustomPainter {
  final ui.Image mapImage;
  final double resolution;

  MapPainter(this.mapImage, this.resolution);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Calculate scaling to fit the map to the screen
    final double scale = size.width / mapImage.width;

    // Draw the map image
    canvas.drawImageRect(
      mapImage,
      Rect.fromLTWH(
          0, 0, mapImage.width.toDouble(), mapImage.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );

    // Draw grid lines (optional)
    paint.color = Colors.grey.withOpacity(0.3);
    paint.strokeWidth = 1.0;

    // Draw a grid based on map resolution
    final double gridSize = (1.0 / resolution) * scale;
    if (gridSize > 20) {
      // Only draw grid if cells are big enough
      for (double x = 0; x < size.width; x += gridSize) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (double y = 0; y < size.height; y += gridSize) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MapPainter oldDelegate) {
    return mapImage != oldDelegate.mapImage ||
        resolution != oldDelegate.resolution;
  }
}

/// Draws a costmap's pre-rendered image, positioned/rotated onto the same
/// pixel space the base map image uses. For the global costmap (already in
/// map frame) [frameTransform] is null; for the local costmap (published in
/// odom frame) it's the current odom->map transform (translation + yaw) —
/// re-composited every paint, so it naturally re-aligns as odom drifts or
/// AMCL corrects it, same as everything else already drawn in map frame
/// here.
class CostmapImagePainter extends CustomPainter {
  final ui.Image image;
  final nav_msgs.MapMetaData costmapInfo;
  final double mapOriginX;
  final double mapOriginY;
  final double mapResolution;
  final int mapHeight;
  final int mapWidth;
  final double mapOriginTheta;
  final ({double x, double y, double theta})? frameTransform;

  CostmapImagePainter({
    required this.image,
    required this.costmapInfo,
    required this.mapOriginX,
    required this.mapOriginY,
    required this.mapResolution,
    required this.mapHeight,
    required this.mapWidth,
    required this.mapOriginTheta,
    this.frameTransform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Costmap origin (bottom-left corner of its grid) in its own frame.
    double ox = costmapInfo.origin.position.x;
    double oy = costmapInfo.origin.position.y;
    double oTheta =
        extractYawFromOriginQuaternion(costmapInfo.origin.orientation);

    final ft = frameTransform;
    if (ft != null) {
      // Rotate+translate the costmap's own-frame origin into map frame.
      final cosT = math.cos(ft.theta);
      final sinT = math.sin(ft.theta);
      final rotatedX = ox * cosT - oy * sinT;
      final rotatedY = ox * sinT + oy * cosT;
      ox = ft.x + rotatedX;
      oy = ft.y + rotatedY;
      oTheta += ft.theta;
    }

    // Bottom-left corner's position in the base map's own pixel space
    // (same convention transformToMapFrame uses everywhere else here).
    final corner = transformToMapFrame(
      ox,
      oy,
      eulerToQuaternion(0, 0, oTheta),
      mapOriginX,
      mapOriginY,
      mapResolution,
      mapHeight,
      mapWidth,
      mapOriginTheta,
    );

    final double pixelsPerCostmapCell = costmapInfo.resolution / mapResolution;
    final double imageWidthPx = image.width * pixelsPerCostmapCell;
    final double imageHeightPx = image.height * pixelsPerCostmapCell;

    canvas.save();
    // Move to the bottom-left corner, rotate around it, THEN shift up by
    // the image's rendered height in the now-rotated frame — the image
    // itself is Y-flipped (its own top-left = grid's top-left in world
    // space), so this aligns its top-left with the grid's actual top-left.
    canvas.translate(corner.x, corner.y);
    canvas.rotate(corner.theta);
    canvas.translate(0, -imageHeightPx);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, imageWidthPx, imageHeightPx),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CostmapImagePainter oldDelegate) {
    return image != oldDelegate.image ||
        costmapInfo != oldDelegate.costmapInfo ||
        frameTransform != oldDelegate.frameTransform;
  }
}

/// RViz-style laser scan points — small dots at each valid range reading,
/// projected from the robot's current map-frame pose. Approximates the
/// laser frame as coincident with base_link (no separate lidar->base_link
/// offset applied); fine for a roughly-centered lidar, revisit if the scan
/// visibly doesn't line up with real obstacles on a robot where it isn't.
class LaserScanPainter extends CustomPainter {
  final sensor_msgs.LaserScan scan;
  // Robot pose in raw world/map-frame meters + standard math-convention
  // yaw (radians) — NOT the widget's _robotX/_robotY/_robotTheta, which
  // are already transformToMapFrame'd into image-pixel space with a
  // flipped theta convention; this painter needs to do that conversion
  // itself, once per scan point, after rotating into the robot's frame.
  final double robotWorldX;
  final double robotWorldY;
  final double robotWorldTheta;
  final double mapOriginX;
  final double mapOriginY;
  final double mapResolution;
  final int mapHeight;
  final int mapWidth;
  final double mapOriginTheta;
  final double scale;

  LaserScanPainter({
    required this.scan,
    required this.robotWorldX,
    required this.robotWorldY,
    required this.robotWorldTheta,
    required this.mapOriginX,
    required this.mapOriginY,
    required this.mapResolution,
    required this.mapHeight,
    required this.mapWidth,
    required this.mapOriginTheta,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF3B30) // RViz-ish red scan points
      ..style = PaintingStyle.fill;
    final double dotRadius = math.max(0.8, 1.2 / scale);
    final double cosR = math.cos(robotWorldTheta);
    final double sinR = math.sin(robotWorldTheta);

    final ranges = scan.ranges;
    for (int i = 0; i < ranges.length; i++) {
      final double r = ranges[i];
      if (!r.isFinite || r < scan.range_min || r > scan.range_max) continue;

      final double angle = scan.angle_min + i * scan.angle_increment;
      // Point in the laser/base_link frame.
      final double lx = r * math.cos(angle);
      final double ly = r * math.sin(angle);
      // Rotate+translate into map frame by the robot's current pose.
      final double worldX = robotWorldX + lx * cosR - ly * sinR;
      final double worldY = robotWorldY + lx * sinR + ly * cosR;

      final p = transformToMapFrame(
        worldX,
        worldY,
        eulerToQuaternion(0, 0, 0),
        mapOriginX,
        mapOriginY,
        mapResolution,
        mapHeight,
        mapWidth,
        mapOriginTheta,
      );
      canvas.drawCircle(Offset(p.x, p.y), dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LaserScanPainter oldDelegate) {
    return scan != oldDelegate.scan ||
        robotWorldX != oldDelegate.robotWorldX ||
        robotWorldY != oldDelegate.robotWorldY ||
        robotWorldTheta != oldDelegate.robotWorldTheta;
  }
}

// Update PathPainter for single path
class PathPainter extends CustomPainter {
  final List<Map<String, dynamic>> path;
  final double mapOriginX;
  final double mapOriginY;
  final double mapResolution;
  final int mapHeight;
  final int mapWidth;
  final double mapOriginTheta;
  final double scale;
  final Color pathColor;

  PathPainter({
    required this.path,
    required this.mapOriginX,
    required this.mapOriginY,
    required this.mapResolution,
    required this.mapHeight,
    required this.mapWidth,
    required this.mapOriginTheta,
    required this.scale,
    required this.pathColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (path.isEmpty) return;

    final pathPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / scale; // slightly thicker

    // Determine gradient start/end based on first and last points
    final Offset startPt = _toOffset(path.first);
    final Offset endPt = _toOffset(path.last);

    pathPaint.shader = ui.Gradient.linear(
      startPt,
      endPt,
      [pathColor, Colors.black],
    );

    final dotPaint = Paint()
      ..color = pathColor
      ..style = PaintingStyle.fill;

    for (var poseJson in path) {
      final position = poseJson['position'];
      final orientation = poseJson['orientation'];
      final mapPose = transformToMapFrame(
        position['x'],
        position['y'],
        geometry_msgs.Quaternion(
          x: orientation['x'],
          y: orientation['y'],
          z: orientation['z'],
          w: orientation['w'],
        ),
        mapOriginX,
        mapOriginY,
        mapResolution,
        mapHeight,
        mapWidth,
        mapOriginTheta,
      );

      // Draw dots at each pose
      canvas.drawCircle(Offset(mapPose.x, mapPose.y), 0.5 / scale, dotPaint);
    }
  }

  @override
  bool shouldRepaint(PathPainter oldDelegate) {
    return path != oldDelegate.path || scale != oldDelegate.scale;
  }

  // helper
  Offset _toOffset(Map<String, dynamic> poseJson) {
    final position = poseJson['position'];
    return Offset(position['x'].toDouble(), position['y'].toDouble());
  }
}

// Painter for orientation arrows
class OrientationArrowPainter extends CustomPainter {
  final double angle;
  final Color color;
  final double size;

  OrientationArrowPainter({
    required this.angle,
    required this.color,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Calculate arrow points
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final arrowLength = this.size * 0.4;

    // Arrow head pointing in the direction of theta
    final endX = centerX + arrowLength * math.cos(angle);
    final endY = centerY + arrowLength * math.sin(angle);

    // Draw arrow line
    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(endX, endY),
      paint,
    );

    // Draw arrow head
    final arrowHeadLength = this.size * 0.15;
    final arrowHeadAngle = math.pi / 6; // 30 degrees

    final head1X = endX - arrowHeadLength * math.cos(angle - arrowHeadAngle);
    final head1Y = endY - arrowHeadLength * math.sin(angle - arrowHeadAngle);

    final head2X = endX - arrowHeadLength * math.cos(angle + arrowHeadAngle);
    final head2Y = endY - arrowHeadLength * math.sin(angle + arrowHeadAngle);

    canvas.drawLine(Offset(endX, endY), Offset(head1X, head1Y), paint);
    canvas.drawLine(Offset(endX, endY), Offset(head2X, head2Y), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Painter for dashed lines
class DashedLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double dashGap;

  DashedLinePainter({
    required this.start,
    required this.end,
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.dashGap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Calculate the distance and direction vector
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    // Calculate the normalized direction vector
    final dirX = dx / distance;
    final dirY = dy / distance;

    // Draw the dashed line
    double currentDistance = 0;
    bool drawDash = true;

    while (currentDistance < distance) {
      final segmentLength = drawDash ? dashLength : dashGap;
      final remainingDistance = distance - currentDistance;
      final segmentDistance = math.min(segmentLength, remainingDistance);

      if (drawDash) {
        final startX = start.dx + dirX * currentDistance;
        final startY = start.dy + dirY * currentDistance;
        final endX = start.dx + dirX * (currentDistance + segmentDistance);
        final endY = start.dy + dirY * (currentDistance + segmentDistance);

        canvas.drawLine(
          Offset(startX, startY),
          Offset(endX, endY),
          paint,
        );
      }

      currentDistance += segmentDistance;
      drawDash = !drawDash;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Painter to draw connecting lines between robot and waypoints
class WaypointPathPainter extends CustomPainter {
  final double robotX;
  final double robotY;
  final List<Waypoint> waypoints;

  // Map metadata for coordinate conversion
  final double mapOriginX;
  final double mapOriginY;
  final double mapResolution;
  final int mapHeight;
  final int mapWidth;
  final double mapOriginTheta;

  final double scale;
  final Color color;

  WaypointPathPainter({
    required this.robotX,
    required this.robotY,
    required this.waypoints,
    required this.mapOriginX,
    required this.mapOriginY,
    required this.mapResolution,
    required this.mapHeight,
    required this.mapWidth,
    required this.mapOriginTheta,
    required this.scale,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waypoints.isEmpty) return;

    // Build list of sequential points (robot + waypoints)
    final List<Offset> pts = [];
    pts.add(Offset(robotX, robotY));

    for (final waypoint in waypoints) {
      final transformed = transformToMapFrame(
        waypoint.position.x,
        waypoint.position.y,
        eulerToQuaternion(0, 0, waypoint.position.theta),
        mapOriginX,
        mapOriginY,
        mapResolution,
        mapHeight,
        mapWidth,
        mapOriginTheta,
      );
      pts.add(Offset(transformed.x, transformed.y));
    }

    // Draw each segment with its own gradient
    for (int i = 0; i < pts.length - 1; i++) {
      final Offset p0 = pts[i];
      final Offset p1 = pts[i + 1];

      final paint = Paint()
        ..strokeWidth = 2.5 / scale
        ..style = PaintingStyle.stroke
        ..shader = ui.Gradient.linear(
          p0,
          p1,
          [color.withOpacity(0.8), Colors.black],
        );

      canvas.drawLine(p0, p1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WaypointPathPainter oldDelegate) {
    // Check if waypoint order or content has changed by comparing IDs and positions
    bool waypointsChanged = waypoints.length != oldDelegate.waypoints.length;

    if (!waypointsChanged) {
      for (int i = 0; i < waypoints.length; i++) {
        if (waypoints[i].id != oldDelegate.waypoints[i].id ||
            waypoints[i].position.x != oldDelegate.waypoints[i].position.x ||
            waypoints[i].position.y != oldDelegate.waypoints[i].position.y) {
          waypointsChanged = true;
          break;
        }
      }
    }

    return robotX != oldDelegate.robotX ||
        robotY != oldDelegate.robotY ||
        waypointsChanged ||
        scale != oldDelegate.scale;
  }
}

class BookmarkWidget extends StatefulWidget {
  final double x;
  final double y;
  final double theta;
  final Color color;
  final double size;
  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;

  const BookmarkWidget({
    super.key,
    this.x = 0,
    this.y = 0,
    required this.theta,
    required this.color,
    required this.size,
    this.icon,
    this.label,
    this.onTap,
  });

  @override
  _BookmarkWidgetState createState() => _BookmarkWidgetState();
}

class _BookmarkWidgetState extends State<BookmarkWidget> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none, // Allow overflow for badge
      children: [
        CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _BookmarkPainter(
            color: widget.color,
            icon: widget.icon,
            label: widget.label,
          ),
        ),
      ],
    );
  }
}

class _BookmarkPainter extends CustomPainter {
  final Color color;
  final IconData? icon;
  final String? label;

  _BookmarkPainter({
    required this.color,
    this.icon,
    this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = size.width * 0.4; // Larger circular background

    // Linear gradient across the circle from left (color) to right (black)
    final Paint backgroundPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(centerX - radius, centerY),
        Offset(centerX + radius, centerY),
        [color, Colors.black],
      )
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(centerX, centerY),
      radius,
      backgroundPaint,
    );

    // Draw white border
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(
      Offset(centerX, centerY),
      radius,
      borderPaint,
    );

    // Draw icon if provided
    if (icon != null) {
      // Prepare icon paint
      final iconSize = radius * 1.2;
      final textPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon!.codePoint),
          style: TextStyle(
            color: Colors.white,
            fontSize: iconSize,
            fontFamily: icon!.fontFamily,
            package: icon!.fontPackage,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          centerX - textPainter.width / 2,
          centerY - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BookmarkPainter oldDelegate) {
    return color != oldDelegate.color ||
        icon != oldDelegate.icon ||
        label != oldDelegate.label;
  }
}
