import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:nav_msgs/msg.dart' as nav_msgs;
import 'package:ros2_api/ros2_api.dart';
import 'package:sensor_msgs/msg.dart' as sensor_msgs;
import 'package:tf2_msgs/msg.dart' as tf2_msgs;

import '../../theme/app_theme.dart';
import '../design/fade_in.dart';
import '../design/skeleton.dart';

/// Converts a map-frame world point to the base map's own pixel space —
/// the coordinate system every overlay in this file (robot, dock, saved
/// locations, costmaps, path) is drawn in, regardless of the overlay's own
/// resolution/origin (costmaps in particular are a different footprint than
/// the base map). Assumes an unrotated origin — true for every map this app
/// will ever see in practice.
Offset _worldToPixel(nav_msgs.OccupancyGrid baseGrid, double x, double y) {
  final resolution = baseGrid.info.resolution;
  final originX = baseGrid.info.origin.position.x;
  final originY = baseGrid.info.origin.position.y;
  final colFromLeft = (x - originX) / resolution;
  final rowFromBottom = (y - originY) / resolution;
  return Offset(colFromLeft, baseGrid.info.height - rowFromBottom);
}

Offset _pixelToWorld(nav_msgs.OccupancyGrid baseGrid, Offset px) {
  final resolution = baseGrid.info.resolution;
  final originX = baseGrid.info.origin.position.x;
  final originY = baseGrid.info.origin.position.y;
  final x = originX + px.dx * resolution;
  final y = originY + (baseGrid.info.height - px.dy) * resolution;
  return Offset(x, y);
}

double _yawOf(geometry_msgs.Quaternion q) =>
    atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z));

geometry_msgs.Quaternion _quaternionFromYaw(double yaw) {
  final half = yaw / 2;
  return geometry_msgs.Quaternion()
    ..x = 0
    ..y = 0
    ..z = sin(half)
    ..w = cos(half);
}

/// A rigid 2D transform (rotation + translation, no scale) — used here for
/// the live `map` -> `odom` transform (see [OccupancyGridView]'s class doc
/// on why the local costmap specifically needs it).
typedef _RigidTransform2D = ({double x, double y, double theta});

/// The marker's dot+cone size, before [OccupancyGridView]'s zoom
/// counter-scale — [_drawRobotMarker]'s own default, so the live robot and
/// the draft marker shown while picking a pose/location are guaranteed the
/// same size instead of two numbers that happen to match today. Also used
/// by the picking State to anchor the heading handle to the draft marker's
/// own cone tip (see [_OccupancyGridViewState]'s posePicking branch), so
/// that stays in lock-step with whatever size is drawn too.
///
/// Previously the draft marker used its own, smaller pair (7/20 vs the live
/// marker's 9/26) — on a screen that opens straight into picking mode with
/// no prior zoom (Add Position, and Map View's own pose-picking before the
/// operator has zoomed at all), the counter-scale hasn't shrunk anything
/// yet, so the marker draws at this raw size directly — and 9/26 read as
/// oversized against the map at that point. Unified on the smaller pair.
const _draftDotRadius = 7.0;
const _draftConeRadius = 20.0;

/// Live occupancy-grid renderer, shared by the Dashboard's small preview and
/// the full Map View screen — same rendering, different size/interactivity.
///
/// `/map` can be millions of cells; per-cell Canvas draws would be far too
/// slow, so the grid is converted once into an RGBA pixel buffer and decoded
/// into a single `ui.Image` (via decodeImageFromPixels) that's then just
/// drawn as one image per frame — cost independent of grid size. Rebuilt
/// only when `/map` actually republishes (TRANSIENT_LOCAL — it doesn't
/// republish on a timer), not every frame. The two costmaps use the exact
/// same pixel-buffer technique, just with a translucent color ramp instead
/// of grayscale, and are positioned via [_worldToPixel] rather than assumed
/// to share the base map's footprint — the local costmap in particular is a
/// small window around the robot, not the whole map.
///
/// The two costmaps also don't share a *frame*: the global costmap is
/// published in `map`, same as the base grid, but Nav2's local costmap is
/// deliberately published in `odom` (standard practice — it keeps local
/// planning smooth across AMCL's discrete pose corrections instead of
/// jumping with them). Nav2's rolling-window costmap never rotates its own
/// cells, so the local costmap's `info.origin` carries no rotation of its
/// own — but `odom` and `map` themselves can differ by a rotation (AMCL
/// corrects heading drift, not just position), which was previously just
/// dropped: the local costmap was drawn as if `odom` and `map` were always
/// identical, which is only ever exactly true the instant they happen to
/// agree. Subscribing to `/tf` and tracking the live `map`->`odom` edge
/// (see `_onTf`/`_mapOdomTransform`) fixes this — see `_drawCostmapLayer`.
///
/// Draws several other real, live overlays when asked: the robot's own pose
/// (`/amcl_pose`), its saved dock pose (`/dock_pose`, TRANSIENT_LOCAL — same
/// ROS-native subscription pattern as `/map`, not routed through the SDK),
/// the planner's current path (`/plan`), both costmaps
/// (`/global_costmap/costmap`, `/local_costmap/costmap` — both plain
/// `nav_msgs/OccupancyGrid`, same type as `/map` itself), and saved
/// locations (passed in by the caller, since those are genuinely
/// SDK-exclusive data with no ROS-native equivalent — see
/// navpromini-sdk-is-optional-not-gateway in project memory). All of the
/// non-essential ones are gated by [showOverlays] plus their own individual
/// `show*` flag, so a "Layers" panel can hide/show each independently
/// without tearing down subscriptions.
///
/// [posePicking] keeps the normal pan/zoom InteractiveViewer live — a
/// picker that can't be zoomed or panned to line a pin up precisely isn't
/// usable on anything but a small map. What it can't do is reuse
/// InteractiveViewer's own single tap+drag gesture for placing a pose:
/// nesting a second pan recognizer inside InteractiveViewer risks a
/// gesture-arena conflict (Flutter still runs InteractiveViewer's own
/// recognizer even with panEnabled/scaleEnabled false — its own doc
/// comment says so). So picking is split into two gestures instead of one:
/// a plain tap places the draft position (coexists with InteractiveViewer
/// the same way the non-picking branch's location/dock tap already does —
/// see [_handleMapTap]), then a small dedicated heading handle appears at
/// that position; dragging *it* sets the heading. The handle is a
/// `HitTestBehavior.opaque` hit target positioned as a *sibling* of
/// InteractiveViewer (via `CompositedTransformTarget`/`Follower` — see
/// [_handleLink] — tracking the marker through Center + InteractiveViewer's
/// transform, without itself being nested inside either), which blocks
/// hit-testing to whatever's behind it within its own small bounds — so a
/// drag starting on the handle never reaches InteractiveViewer's pan
/// recognizer at all, and there's no arena race to resolve. A widget
/// nested *inside* InteractiveViewer's own transformed child wouldn't get
/// that protection — ancestor gesture recognizers still see every pointer
/// that lands within their bounds regardless of what a descendant claims,
/// hit-test opacity only prunes *siblings* — which is why the handle lives
/// outside it despite needing to visually track something inside it.
/// Everywhere else on the map, hits fall through to InteractiveViewer
/// exactly as normal.
///
/// When not [interactive] (the Dashboard's live preview, Maps List's
/// thumbnail), the zoom level always fits the map's width to the
/// container — a small "here's the floor, and there's the robot" thumbnail,
/// not a variable zoom — but the vertical pan follows the robot (clamped to
/// the map's own bounds) so a tall map doesn't just show its top edge with
/// the robot cropped out of frame. When [interactive] (the full Map View /
/// Create Map's live view), the
/// robot marker counter-scales against the InteractiveViewer's current zoom
/// so it stays a constant, legible on-screen size instead of growing right
/// along with the map as the operator zooms in.
class OccupancyGridView extends StatefulWidget {
  const OccupancyGridView({
    super.key,
    required this.ros2,
    this.interactive = false,
    this.showRobot = true,
    this.showDock = false,
    this.showPath = false,
    this.showGlobalCostmap = false,
    this.showLocalCostmap = false,
    this.locations = const [],
    this.showWaypointRoute = false,
    this.showOverlays = true,
    this.transformationController,
    this.posePicking = false,
    this.onDraftPose,
    this.onLocationTap,
    this.onDockTap,
    this.showLocalizationBadge = true,
    this.isMapping = false,
    this.dockPoseOverride,
    this.fitWholeMap = false,
    this.initialPose,
    this.initialPath,
    this.showLaserScan = false,
    this.laserScanTopic = '/scan_filtered',
    this.draftPoseOverride,
    this.dockEditorMode = false,
    this.dockEditorDockPoint,
    this.dockEditorStandoffPoint,
    this.dockEditorActiveIndex = 0,
    this.onDockEditorTap,
  });

  final Ros2 ros2;
  final bool interactive;
  final bool showRobot;

  /// Thumbnail mode ([interactive] false) only. Default behaviour fits the
  /// map's width and, if it's still taller than the container, crops and
  /// pans vertically to keep the robot centred (the Dashboard mini-map:
  /// "where is the robot right now"). Set true to fit the WHOLE map inside
  /// the container instead — never crops, letterboxes on whichever axis has
  /// slack — for previews where every pin/waypoint needs to stay visible
  /// regardless of where the robot happens to be (a mission's route).
  final bool fitWholeMap;

  /// Subscribe to and draw the robot's saved dock pose.
  final bool showDock;

  /// Subscribe to and draw the planner's current path (`/plan`).
  final bool showPath;

  /// Subscribe to and draw `/global_costmap/costmap`.
  final bool showGlobalCostmap;

  /// Subscribe to and draw `/local_costmap/costmap`.
  final bool showLocalCostmap;

  /// Saved locations to draw as pins — each a map with `name`, `x`, `y`
  /// (the same shape SdkApiService.listWaypoints() returns).
  final List<Map<String, dynamic>> locations;

  /// Also connect [locations] with the dashed "visited in this order" line
  /// (see [_OccupancyGridPainter._drawWaypointRoute]). Off by default:
  /// [locations] is used both for a mission's own ordered route (where the
  /// dashes are meaningful — ask mission_detail_screen's route card, the
  /// one caller that sets this true) and for the general "Saved Locations"
  /// map layer (teleop/map screens), whose storage order is arbitrary and
  /// was previously getting the same dashed connector by accident — every
  /// pin joined to every other regardless of any mission, including after
  /// a plain single-pose goal that never involved a mission at all.
  final bool showWaypointRoute;

  /// Whether the optional overlays are currently visible — a "Layers" panel
  /// flips this rather than re-subscribing. Each overlay still needs its
  /// own `show*` flag true to be subscribed to at all.
  final bool showOverlays;

  /// Lets a parent screen drive zoom (+/- buttons) on the InteractiveViewer.
  /// Only meaningful when [interactive] is true and [posePicking] is false.
  final TransformationController? transformationController;

  /// When true, tap+drag on the map picks a position+heading instead of
  /// panning/zooming — see the class doc for why this swaps the whole
  /// interaction mode rather than layering on top of InteractiveViewer.
  final bool posePicking;

  /// Called once when a position is tapped (heading defaults to 0), and
  /// again on every update while the heading handle is being dragged, with
  /// the map-frame pose implied so far. Never called with a stale value —
  /// the parent always has the latest draft to submit when the operator
  /// confirms.
  final void Function(double x, double y, double theta)? onDraftPose;

  /// Called with a saved location's own map (same shape as [locations]'
  /// entries) when the operator taps within a small radius of its pin —
  /// only meaningful when [interactive] and not [posePicking]. Lets a
  /// parent screen (Map View) offer "go here" straight from the map,
  /// matching the same tap-a-location-to-navigate affordance Teleop's own
  /// quick-nav list already has.
  final void Function(Map<String, dynamic> location)? onLocationTap;

  /// Called when the operator taps within a small radius of the dock pin —
  /// only meaningful when [showDock], [interactive], and not [posePicking].
  /// Lets a parent screen (Map View) offer "go to dock" / "Dock" / "Undock"
  /// straight from the map.
  final VoidCallback? onDockTap;

  /// Whether the small built-in "Not localized" badge shows itself when
  /// [showRobot] is on but there's no pose yet. Screens that show their own
  /// bigger, actionable not-localized banner (with a dock-confirm flow) set
  /// this false so the two don't stack.
  final bool showLocalizationBadge;

  /// Whether this view is rendering a SLAM mapping session.
  /// Suppresses AMCL-specific localization badges and prefers SLAM/odom poses.
  final bool isMapping;

  /// A fallback dock position, used to draw the dock pin when [showDock] is
  /// on but the live `/dock_pose` ROS topic hasn't delivered anything (it's
  /// only republished when the dockwatch node freshly (re)detects the dock,
  /// not latched-forever the way `/map` is — a robot that hasn't docked or
  /// undocked recently in this run can have a perfectly real, known dock
  /// pose with nothing currently on the topic for a new subscriber to
  /// catch). Callers that already have SdkApiService fetch this via
  /// `fetchDockPose` and pass it in, the same "genuinely SDK-exclusive data,
  /// passed in by the caller" treatment [locations] already gets. Ignored
  /// once the topic itself delivers a message — that's always fresher.
  final ({double x, double y, double theta})? dockPoseOverride;
  final geometry_msgs.PoseWithCovarianceStamped? initialPose;
  final nav_msgs.Path? initialPath;
  final bool showLaserScan;
  final String laserScanTopic;
  final ({double x, double y, double theta})? draftPoseOverride;
  final bool dockEditorMode;
  final ({double x, double y})? dockEditorDockPoint;
  final ({double x, double y})? dockEditorStandoffPoint;
  final int dockEditorActiveIndex;
  final void Function(double x, double y)? onDockEditorTap;

  @override
  State<OccupancyGridView> createState() => _OccupancyGridViewState();
}

class _OccupancyGridViewState extends State<OccupancyGridView> {
  Subscriber<nav_msgs.OccupancyGrid>? _mapSub;
  Subscriber<geometry_msgs.PoseWithCovarianceStamped>? _poseSub;
  Subscriber<geometry_msgs.PoseStamped>? _dockSub;
  Subscriber<nav_msgs.Path>? _pathSub;
  Subscriber<nav_msgs.OccupancyGrid>? _globalCostmapSub;
  Subscriber<nav_msgs.OccupancyGrid>? _localCostmapSub;
  Subscriber<tf2_msgs.TFMessage>? _tfSub;
  Subscriber<sensor_msgs.LaserScan>? _scanSub;
  sensor_msgs.LaserScan? _scan;
  Subscriber<nav_msgs.Odometry>? _odomSub;
  geometry_msgs.PoseWithCovarianceStamped? _odomPose;

  /// The live `map` -> `odom` transform, tracked only while the local
  /// costmap is shown (it's the only thing here that needs it — see the
  /// class doc). Null until the first `/tf` message carrying that specific
  /// edge arrives (e.g. before AMCL has published one at all), in which
  /// case the local costmap falls back to the old odom==map assumption
  /// rather than not drawing at all.
  _RigidTransform2D? _mapOdomTransform;

  nav_msgs.OccupancyGrid? _grid;
  ui.Image? _image;
  geometry_msgs.PoseWithCovarianceStamped? _pose;
  geometry_msgs.PoseStamped? _dockPose;

  /// Effective pose: uses /amcl_pose when available, otherwise falls back
  /// to /odom (transformed by map->odom if available), guaranteeing the
  /// robot marker is drawn live during SLAM mapping without AMCL.
  geometry_msgs.PoseWithCovarianceStamped? get _effectivePose {
    final amcl = _pose;
    if (amcl != null) return amcl;
    final odom = _odomPose ?? widget.initialPose;
    if (odom == null) return null;
    final tf = _mapOdomTransform;
    if (tf != null) {
      final ox = odom.pose.pose.position.x;
      final oy = odom.pose.pose.position.y;
      final c = cos(tf.theta), s = sin(tf.theta);
      final mapX = tf.x + c * ox - s * oy;
      final mapY = tf.y + s * ox + c * oy;
      final odomYaw = _yawOf(odom.pose.pose.orientation);
      final mapYaw = tf.theta + odomYaw;
      final transformed = geometry_msgs.PoseWithCovarianceStamped()
        ..header = odom.header
        ..pose.pose.position.x = mapX
        ..pose.pose.position.y = mapY
        ..pose.pose.position.z = odom.pose.pose.position.z
        ..pose.pose.orientation = _quaternionFromYaw(mapYaw);
      return transformed;
    }
    return odom;
  }

  /// The live topic value when it has one, else [widget.dockPoseOverride]
  /// (only its position is used — the pin doesn't draw orientation) —
  /// see the class doc on [OccupancyGridView.dockPoseOverride] for why the
  /// topic alone isn't reliable enough on its own.
  geometry_msgs.PoseStamped? get _resolvedDockPose {
    if (_dockPose != null) return _dockPose;
    final override = widget.dockPoseOverride;
    if (override == null) return null;
    return geometry_msgs.PoseStamped(
      pose: geometry_msgs.Pose(
          position: geometry_msgs.Point(x: override.x, y: override.y)),
    );
  }

  nav_msgs.Path? _path;
  bool _building = false;

  _CostmapLayer? _globalCostmap;
  _CostmapLayer? _localCostmap;
  bool _buildingGlobalCostmap = false;
  bool _buildingLocalCostmap = false;

  Offset? _draftPixel;
  double _draftYaw = 0;

  /// Marks the actual painted map image (the `CustomPaint` built by
  /// `contentFor`) so [_globalToContent] can convert a raw pointer position
  /// into content-pixel space via its real `RenderBox`, rather than
  /// re-deriving the transform from [_controller.value] by hand — that
  /// hand-rolled version ignored the `Center` this content is wrapped in
  /// (needed so a map smaller than the viewport starts centred, not pinned
  /// to the top-left), silently placing every picked position off by
  /// however far `Center` had shifted the image — confirmed live: on a map
  /// smaller than the viewport, enough to land the picked position outside
  /// the map entirely. Going through the real `RenderBox` is correct
  /// regardless of `Center`, `InteractiveViewer`'s transform, or anything
  /// else in between, since it reflects however the tree actually laid out
  /// and painted, not a re-derivation of it. Reused by both [posePicking]
  /// and the plain [interactive] branch's own [_handleMapTap].
  final _contentBoxKey = GlobalKey();

  /// Anchors the heading handle (see [posePicking]'s picking branch) to the
  /// draft marker's actual painted position via Flutter's compositing layer
  /// (`CompositedTransformTarget`/`Follower`) instead of computing that
  /// position by hand — the same class of bug [_contentBoxKey] fixes for
  /// taps applied to *where the handle itself ends up drawn*: get it from
  /// Flutter's own transform pipeline, don't re-derive it.
  final _handleLink = LayerLink();

  TransformationController? _ownedController;
  TransformationController get _controller =>
      widget.transformationController ??
      (_ownedController ??= TransformationController());

  @override
  void initState() {
    super.initState();
    _pose = widget.initialPose;
    _path = widget.initialPath;
    // Listened to so the robot marker can counter-scale against the current
    // zoom (see _onViewTransformChanged) — a marker drawn at a fixed size in
    // the image's own pixel space would otherwise grow right along with the
    // map under InteractiveViewer's zoom, quickly overwhelming the view at
    // high zoom instead of staying a legible, constant-size "you are here".
    _controller.addListener(_onViewTransformChanged);
    _subscribeAll();
  }

  void _subscribeMap() {
    _mapSub = Subscriber<nav_msgs.OccupancyGrid>(
      name: '/map',
      type: nav_msgs.OccupancyGrid().fullType,
      ros2: widget.ros2,
      prototype: nav_msgs.OccupancyGrid(),
      // map_server/slam_toolbox latch /map as TRANSIENT_LOCAL — without this
      // a subscriber that (re)joins after the one-time publish never gets it.
      qos: const {'durability': 'transient_local'},
      callback: _onGrid,
    );
  }

  void _subscribeAll() {
    _subscribeMap();
    if (widget.showRobot) _subscribeRobot();
    if (widget.showDock) _subscribeDock();
    if (widget.showPath) _subscribePath();
    if (widget.showGlobalCostmap) _subscribeGlobalCostmap();
    if (widget.showLocalCostmap) _subscribeLocalCostmap();
    if (widget.showLaserScan) _subscribeScan();
    _subscribeTf();
  }

  void _unsubscribeAll() {
    _building = false;
    _buildingGlobalCostmap = false;
    _buildingLocalCostmap = false;
    _mapSub?.unsubscribe();
    _mapSub = null;
    _poseSub?.unsubscribe();
    _poseSub = null;
    _odomSub?.unsubscribe();
    _odomSub = null;
    _odomPose = null;
    _dockSub?.unsubscribe();
    _dockSub = null;
    _pathSub?.unsubscribe();
    _pathSub = null;
    _globalCostmapSub?.unsubscribe();
    _globalCostmapSub = null;
    _localCostmapSub?.unsubscribe();
    _localCostmapSub = null;
    _scanSub?.unsubscribe();
    _scanSub = null;
    _scan = null;
    _tfSub?.unsubscribe();
    _tfSub = null;
    _mapOdomTransform = null;
  }

  // Each show* flag can flip after this widget is already mounted — a
  // Layers panel toggling a checkbox rebuilds the same State object rather
  // than remounting it, so subscribing only in initState() would leave a
  // freshly-checked layer subscribed to nothing. didUpdateWidget (below)
  // calls these the same way initState() does, just reacting to a flag
  // that changed rather than one that started true.
  void _subscribeRobot() {
    _poseSub = Subscriber<geometry_msgs.PoseWithCovarianceStamped>(
      name: '/amcl_pose',
      type: geometry_msgs.PoseWithCovarianceStamped().fullType,
      ros2: widget.ros2,
      prototype: geometry_msgs.PoseWithCovarianceStamped(),
      // AMCL publishes /amcl_pose with TRANSIENT_LOCAL durability — without
      // matching durability, a reconnecting or stationary subscriber never
      // receives the latched pose until the robot physically moves.
      qos: const {'durability': 'transient_local'},
      callback: (msg) {
        if (mounted) setState(() => _pose = msg);
      },
    );
    _odomSub = Subscriber<nav_msgs.Odometry>(
      name: '/odom',
      type: nav_msgs.Odometry().fullType,
      ros2: widget.ros2,
      prototype: nav_msgs.Odometry(),
      qos: const {'reliability': 'best_effort'},
      callback: (msg) {
        if (mounted) {
          final converted = geometry_msgs.PoseWithCovarianceStamped()
            ..header = msg.header
            ..pose = msg.pose;
          setState(() => _odomPose = converted);
        }
      },
    );
    _subscribeTf();
  }

  void _subscribeDock() {
    _dockSub = Subscriber<geometry_msgs.PoseStamped>(
      name: '/dock_pose',
      type: geometry_msgs.PoseStamped().fullType,
      ros2: widget.ros2,
      prototype: geometry_msgs.PoseStamped(),
      qos: const {'durability': 'transient_local'},
      callback: (msg) {
        if (mounted) setState(() => _dockPose = msg);
      },
    );
  }

  void _subscribePath() {
    _pathSub = Subscriber<nav_msgs.Path>(
      name: '/plan',
      type: nav_msgs.Path().fullType,
      ros2: widget.ros2,
      prototype: nav_msgs.Path(),
      callback: (msg) {
        if (mounted) setState(() => _path = msg);
      },
    );
  }

  void _subscribeGlobalCostmap() {
    _globalCostmapSub = Subscriber<nav_msgs.OccupancyGrid>(
      name: '/global_costmap/costmap',
      type: nav_msgs.OccupancyGrid().fullType,
      ros2: widget.ros2,
      prototype: nav_msgs.OccupancyGrid(),
      callback: (grid) => _onCostmap(grid, isGlobal: true),
    );
  }

  void _subscribeLocalCostmap() {
    _localCostmapSub = Subscriber<nav_msgs.OccupancyGrid>(
      name: '/local_costmap/costmap',
      type: nav_msgs.OccupancyGrid().fullType,
      ros2: widget.ros2,
      prototype: nav_msgs.OccupancyGrid(),
      callback: (grid) => _onCostmap(grid, isGlobal: false),
    );
  }

  void _subscribeScan() {
    _scanSub?.unsubscribe();
    _scanSub = Subscriber<sensor_msgs.LaserScan>(
      name: widget.laserScanTopic,
      type: sensor_msgs.LaserScan().fullType,
      ros2: widget.ros2,
      prototype: sensor_msgs.LaserScan(),
      callback: (msg) {
        if (mounted) setState(() => _scan = msg);
      },
    );
  }

  void _subscribeTf() {
    // See the class doc: the local costmap is in `odom`, not `map` — this
    // is what lets _drawCostmapLayer place it correctly instead of
    // assuming the two frames are always identical.
    _tfSub?.unsubscribe();
    _tfSub = Subscriber<tf2_msgs.TFMessage>(
      name: '/tf',
      type: tf2_msgs.TFMessage().fullType,
      ros2: widget.ros2,
      prototype: tf2_msgs.TFMessage(),
      callback: _onTf,
    );
  }

  void _onTf(tf2_msgs.TFMessage msg) {
    for (final t in msg.transforms) {
      if (t.header.frame_id == 'map' && t.child_frame_id == 'odom') {
        final tr = t.transform;
        if (mounted) {
          setState(() => _mapOdomTransform = (
                x: tr.translation.x,
                y: tr.translation.y,
                theta: _yawOf(tr.rotation),
              ));
        }
        return; // /tf carries many other edges (odom->base_link at a much
        // higher rate in particular) — nothing else here is relevant.
      }
    }
  }

  @override
  void didUpdateWidget(covariant OccupancyGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ros2 != oldWidget.ros2) {
      // ConnectionProvider.reconnect() (the app's "Retry" affordance) closes
      // the old Ros2 and swaps in a brand new instance — but this State
      // object survives that rebuild, and every Subscriber above was bound
      // to the *old* one at initState() time. Left alone, they're
      // permanently dead: the map/robot/dock/path/costmaps here would never
      // update again, even though the new connection is live and every
      // other (freshly-mounted) screen using it works fine. Tear down and
      // resubscribe fresh, and drop cached data from the old connection so
      // a stale frame doesn't linger on screen while the new one is still
      // catching up.
      _unsubscribeAll();
      setState(() {
        _grid = null;
        _image = null;
        _pose = null;
        _dockPose = null;
        _path = null;
        _globalCostmap = null;
        _localCostmap = null;
      });
      _subscribeAll();
      return; // the show*-flag diffing below is redundant with the fresh
      // subscribeAll() above, and would just be reasoning about
      // subscriptions that no longer exist.
    }
    if (widget.initialPose != null &&
        (_pose == null || widget.initialPose != oldWidget.initialPose)) {
      _pose = widget.initialPose;
    }
    if (widget.initialPath != null &&
        (_path == null || widget.initialPath != oldWidget.initialPath)) {
      _path = widget.initialPath;
    }
    if (widget.showRobot != oldWidget.showRobot) {
      if (widget.showRobot) {
        _subscribeRobot();
      } else {
        _poseSub?.unsubscribe();
        _poseSub = null;
        _odomSub?.unsubscribe();
        _odomSub = null;
        _pose = null;
        _odomPose = null;
      }
    }
    if (widget.showDock != oldWidget.showDock) {
      if (widget.showDock) {
        _subscribeDock();
      } else {
        _dockSub?.unsubscribe();
        _dockSub = null;
        _dockPose = null;
      }
    }
    if (widget.showPath != oldWidget.showPath) {
      if (widget.showPath) {
        _subscribePath();
      } else {
        _pathSub?.unsubscribe();
        _pathSub = null;
        _path = null;
      }
    }
    if (widget.showGlobalCostmap != oldWidget.showGlobalCostmap) {
      if (widget.showGlobalCostmap) {
        _subscribeGlobalCostmap();
      } else {
        _globalCostmapSub?.unsubscribe();
        _globalCostmapSub = null;
        _globalCostmap = null;
      }
    }
    if (widget.showLocalCostmap != oldWidget.showLocalCostmap) {
      if (widget.showLocalCostmap) {
        _subscribeLocalCostmap();
      } else {
        _localCostmapSub?.unsubscribe();
        _localCostmapSub = null;
        _localCostmap = null;
        _tfSub?.unsubscribe();
        _tfSub = null;
        _mapOdomTransform = null;
      }
    }
    if (widget.showLaserScan != oldWidget.showLaserScan ||
        widget.laserScanTopic != oldWidget.laserScanTopic) {
      if (widget.showLaserScan) {
        _subscribeScan();
      } else {
        _scanSub?.unsubscribe();
        _scanSub = null;
        _scan = null;
      }
    }
  }

  Future<void> _onGrid(nav_msgs.OccupancyGrid grid) async {
    if (_building) return; // drop an overlapping rebuild rather than queue it
    _building = true;
    try {
      final width = grid.info.width;
      final height = grid.info.height;
      if (width <= 0 || height <= 0) return;

      final pixels = Uint8List(width * height * 4);
      for (var row = 0; row < height; row++) {
        // Grid row 0 is the world-bottom row (increasing row = increasing map
        // Y); image row 0 is conventionally the top. Flip here so the
        // rendered map isn't upside down relative to the world frame.
        final destRow = height - 1 - row;
        for (var col = 0; col < width; col++) {
          final value = grid.data[row * width + col];
          final gray =
              value < 0 ? 200 : (255 * (1 - value / 100)).round().clamp(0, 255);
          final i = (destRow * width + col) * 4;
          pixels[i] = gray;
          pixels[i + 1] = gray;
          pixels[i + 2] = gray;
          pixels[i + 3] = 255;
        }
      }

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
      final image = await completer.future;
      if (!mounted) return;
      setState(() {
        _grid = grid;
        _image = image;
      });
    } catch (e) {
      debugPrint('Error decoding map grid: $e');
    } finally {
      _building = false;
    }
  }

  /// Costmap cells become a translucent color ramp (transparent at cost 0,
  /// rising to a capped opacity at cost 100) rather than an opaque image —
  /// the base map underneath needs to stay legible through it. Unknown
  /// cells (-1, common at the edges of the local costmap's rolling window)
  /// are fully transparent rather than drawn as anything.
  Future<void> _onCostmap(nav_msgs.OccupancyGrid grid,
      {required bool isGlobal}) async {
    if (isGlobal ? _buildingGlobalCostmap : _buildingLocalCostmap) return;
    if (isGlobal) {
      _buildingGlobalCostmap = true;
    } else {
      _buildingLocalCostmap = true;
    }
    try {
      final width = grid.info.width;
      final height = grid.info.height;
      if (width <= 0 || height <= 0) return;

      final color = isGlobal ? AppColors.costmapGlobal : AppColors.costmapLocal;
      final colorR = (color.r * 255).round().clamp(0, 255);
      final colorG = (color.g * 255).round().clamp(0, 255);
      final colorB = (color.b * 255).round().clamp(0, 255);
      final pixels = Uint8List(width * height * 4);
      for (var row = 0; row < height; row++) {
        final destRow = height - 1 - row;
        for (var col = 0; col < width; col++) {
          final value = grid.data[row * width + col];
          final i = (destRow * width + col) * 4;
          if (value < 0) continue; // leave fully transparent (alpha already 0)
          final t = (value / 100).clamp(0.0, 1.0);
          pixels[i] = colorR;
          pixels[i + 1] = colorG;
          pixels[i + 2] = colorB;
          pixels[i + 3] = (t * 160).round().clamp(0, 255);
        }
      }

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
      final image = await completer.future;
      if (!mounted) return;
      setState(() {
        final layer = _CostmapLayer(grid: grid, image: image);
        if (isGlobal) {
          _globalCostmap = layer;
        } else {
          _localCostmap = layer;
        }
      });
    } catch (e) {
      debugPrint('Error decoding costmap: $e');
    } finally {
      if (isGlobal) {
        _buildingGlobalCostmap = false;
      } else {
        _buildingLocalCostmap = false;
      }
    }
  }

  /// Converts a raw global pointer position into the base map's own
  /// content-pixel space — the space [_draftPixel], [_pixelToWorld], and
  /// the painted image itself all already share — via [_contentBoxKey]'s
  /// real `RenderBox`. See that field's doc for why this replaced hand
  /// rolled matrix math against [_controller.value].
  Offset? _globalToContent(Offset globalPosition) {
    final box = _contentBoxKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    return box.globalToLocal(globalPosition);
  }

  /// Places (or re-places) the draft pose — a plain tap, so it coexists
  /// with InteractiveViewer's own pan/zoom recognizer instead of competing
  /// with it (see the class doc on [posePicking]). Heading starts at 0 and
  /// is set afterwards by dragging the heading handle, via
  /// [_updateDraftYaw].
  void _placeDraft(Offset globalPosition) {
    final content = _globalToContent(globalPosition);
    if (content == null) return;
    setState(() {
      _draftPixel = content;
      _draftYaw = 0;
    });
    _reportDraft();
  }

  /// Drags the heading handle around the draft marker to set its heading.
  /// Both the marker's position ([_draftPixel]) and the drag pointer's
  /// current position are converted into the same content-pixel space (via
  /// [_globalToContent]) and compared directly there — no need to know
  /// where the handle itself is currently drawn on screen at all, which is
  /// otherwise a surprisingly loaded question once `CompositedTransform*`
  /// (see [_handleLink]) is what's actually placing it. Ignored within a
  /// small dead zone right at the marker so a barely-moved touch doesn't
  /// snap the heading to whatever arbitrary angle a few stray pixels
  /// imply — sized in content pixels scaled by the current zoom so the
  /// dead zone reads as a constant ~6 screen px regardless of zoom level,
  /// same intent as [_OccupancyGridPainter.markerScale].
  void _updateDraftYaw(Offset globalPosition) {
    final origin = _draftPixel;
    final content = _globalToContent(globalPosition);
    if (origin == null || content == null) return;
    final v = content - origin;
    final viewScale = _controller.value.getMaxScaleOnAxis();
    final deadZone = 6.0 / (viewScale > 0 ? viewScale : 1.0);
    if (v.distance < deadZone) return;
    setState(() => _draftYaw = atan2(-v.dy, v.dx));
    _reportDraft();
  }

  void _reportDraft() {
    final grid = _grid;
    final origin = _draftPixel;
    final callback = widget.onDraftPose;
    if (grid == null || origin == null || callback == null) return;
    final world = _pixelToWorld(grid, origin);
    callback(world.dx, world.dy, _draftYaw);
  }

  void _onViewTransformChanged() {
    if (mounted) setState(() {});
  }

  /// When [showRobot] is on but there's genuinely no pose yet (AMCL hasn't
  /// converged — `/amcl_pose` has never published), the marker/centering
  /// logic both correctly draw nothing rather than fabricate a position —
  /// but "nothing drawn" alone reads as a rendering bug, not "the robot
  /// isn't localized". This small badge says so explicitly. Gated on
  /// [showRobot] specifically (not just "pose is null") so it never appears
  /// on views that never asked for a robot marker in the first place (e.g.
  /// Maps List's thumbnail, which passes showRobot: false).
  Widget _withLocalizationBadge(Widget child) {
    if (!widget.showRobot ||
        !widget.showLocalizationBadge ||
        widget.isMapping ||
        _effectivePose != null) {
      return child;
    }
    return Stack(
      children: [
        child,
        Positioned(
          left: AppSpacing.sm,
          top: AppSpacing.sm,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_off_rounded,
                    size: 12, color: AppColors.textSecondary),
                SizedBox(width: 4),
                Text('Not localized',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Hit-tests a tap against every saved location's pin, plus the dock pin.
  /// Converts the raw global tap position into content-pixel space via
  /// [_globalToContent] — the same space [_worldToPixel] positions pins in
  /// — so the comparison is correct at any zoom level, then checks
  /// world-space distance against a tolerance sized in real meters (not
  /// pixels), so the tap target's effective on-screen size shrinks/grows
  /// sensibly with zoom the same way the pin itself visually does. The
  /// dock wins ties — it's a single, deliberately-placed pin, so a tap
  /// equidistant from it and a location pin is more likely aimed at the
  /// dock.
  void _handleMapTap(Offset globalPosition) {
    final grid = _grid;
    final contentPoint = _globalToContent(globalPosition);
    if (grid == null || contentPoint == null) return;
    final tapWorld = _pixelToWorld(grid, contentPoint);
    if (widget.dockEditorMode) {
      widget.onDockEditorTap?.call(tapWorld.dx, tapWorld.dy);
      return;
    }
    const toleranceMeters = 0.6;

    double? dockDist;
    if (widget.onDockTap != null) {
      final dock = _resolvedDockPose;
      if (dock != null) {
        final dx = dock.pose.position.x - tapWorld.dx;
        final dy = dock.pose.position.y - tapWorld.dy;
        dockDist = sqrt(dx * dx + dy * dy);
      }
    }

    Map<String, dynamic>? nearestLocation;
    double? locDist;
    if (widget.onLocationTap != null) {
      for (final loc in widget.locations) {
        if (loc['x'] is! num || loc['y'] is! num) continue;
        final dx = (loc['x'] as num).toDouble() - tapWorld.dx;
        final dy = (loc['y'] as num).toDouble() - tapWorld.dy;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < toleranceMeters && (locDist == null || dist < locDist)) {
          locDist = dist;
          nearestLocation = loc;
        }
      }
    }

    if (dockDist != null &&
        dockDist < toleranceMeters &&
        (locDist == null || dockDist <= locDist)) {
      widget.onDockTap!();
      return;
    }
    if (nearestLocation != null) widget.onLocationTap!(nearestLocation);
  }

  @override
  void dispose() {
    _mapSub?.unsubscribe();
    _poseSub?.unsubscribe();
    _dockSub?.unsubscribe();
    _pathSub?.unsubscribe();
    _globalCostmapSub?.unsubscribe();
    _localCostmapSub?.unsubscribe();
    _tfSub?.unsubscribe();
    _controller.removeListener(_onViewTransformChanged);
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final grid = _grid;
    if (image == null || grid == null) {
      return const Padding(
        padding: EdgeInsets.all(4),
        child: SkeletonBox(
            width: double.infinity, height: double.infinity, radius: 8),
      );
    }

    final showOverlays = widget.showOverlays;

    Offset? effectiveDraftPixel = _draftPixel;
    double effectiveDraftYaw = _draftYaw;
    if (widget.draftPoseOverride != null) {
      effectiveDraftPixel = _worldToPixel(grid, widget.draftPoseOverride!.x, widget.draftPoseOverride!.y);
      effectiveDraftYaw = widget.draftPoseOverride!.theta;
    }

    // Builds the painted map for a given marker counter-scale — a function
    // rather than a single built-once widget, because the right
    // counter-scale differs per branch below and, for the thumbnail branch,
    // isn't known until its LayoutBuilder resolves the viewport size. Takes
    // an optional key so [_contentBoxKey] can mark the actual CustomPaint
    // (its own local space *is* content-pixel space) — see that field's
    // doc.
    Widget contentFor(double markerScale, {Key? key}) => CustomPaint(
          key: key,
          size: Size(image.width.toDouble(), image.height.toDouble()),
          painter: _OccupancyGridPainter(
            image: image,
            grid: grid,
            pose: widget.showRobot ? (_effectivePose ?? widget.initialPose) : null,
            dockPose:
                (widget.showDock && showOverlays && !widget.dockEditorMode) ? _resolvedDockPose : null,
            path: (widget.showPath && showOverlays)
                ? (_path ?? widget.initialPath)
                : null,
            globalCostmap: (widget.showGlobalCostmap && showOverlays)
                ? _globalCostmap
                : null,
            localCostmap: (widget.showLocalCostmap && showOverlays)
                ? _localCostmap
                : null,
            mapOdomTransform: _mapOdomTransform,
            locations: showOverlays ? widget.locations : const [],
            showWaypointRoute: widget.showWaypointRoute,
            draftPixel: widget.posePicking ? effectiveDraftPixel : null,
            draftYaw: effectiveDraftYaw,
            markerScale: markerScale,
            scan: (widget.showLaserScan && showOverlays) ? _scan : null,
            dockEditorMode: widget.dockEditorMode,
            dockEditorDockPoint: widget.dockEditorDockPoint,
            dockEditorStandoffPoint: widget.dockEditorStandoffPoint,
            dockEditorActiveIndex: widget.dockEditorActiveIndex,
          ),
        );

    if (widget.posePicking) {
      // Counter-scaled against the live zoom the same way the interactive
      // branch below does, so the marker stays a constant, legible size
      // instead of growing with the map as the operator zooms in to place
      // it precisely.
      final viewScale = _controller.value.getMaxScaleOnAxis();
      final markerScale = 1 / (viewScale <= 0 ? 1.0 : viewScale);

      // Where the heading handle's anchor point sits, in *content*-pixel
      // space (not screen space — see [_handleLink]'s doc: positioning it
      // is Flutter's job via CompositedTransformTarget/Follower, not ours).
      // Anchored right at the draft marker's own cone tip — _draftConeRadius
      // is exactly how far out the painter draws it — plus a couple of
      // screen px of breathing room, so the handle reads as the marker's
      // own nose rather than an unrelated control floating nearby.
      // markerScale keeps that distance a constant on-screen size
      // regardless of zoom, the same reasoning as the painter's own
      // markerScale keeps drawn marker sizes constant.
      final draft = effectiveDraftPixel;
      const handleScreenDistance = 44.0;
      final handleContentPos = draft == null
          ? null
          : draft +
              Offset(
                handleScreenDistance * markerScale * cos(effectiveDraftYaw),
                -handleScreenDistance * markerScale * sin(effectiveDraftYaw),
              );

      return SizedBox.expand(
        child: Stack(
          children: [
            // Wraps (rather than nests inside) InteractiveViewer so the tap
            // recognizer doesn't compete with its own pan/zoom recognizer —
            // see the class doc on [posePicking].
            GestureDetector(
              onTapUp: (details) => _placeDraft(details.globalPosition),
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 0.2,
                maxScale: 8,
                boundaryMargin: const EdgeInsets.all(200),
                child: Center(
                  // A second, inner Stack — not InteractiveViewer's own
                  // child directly — so the CompositedTransformTarget below
                  // can sit *inside* the transformed content (tracking the
                  // marker through Center + InteractiveViewer's transform
                  // automatically) while still being a completely inert,
                  // non-hit-testing marker (no gesture recognizer of its
                  // own, so unlike the handle itself, nesting it in here
                  // doesn't risk the arena conflict the class doc warns
                  // about).
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      contentFor(markerScale, key: _contentBoxKey),
                      if (handleContentPos != null)
                        Positioned(
                          left: handleContentPos.dx,
                          top: handleContentPos.dy,
                          child: CompositedTransformTarget(
                            link: _handleLink,
                            child: const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (handleContentPos != null)
              CompositedTransformFollower(
                link: _handleLink,
                targetAnchor: Alignment.center,
                followerAnchor: Alignment.center,
                showWhenUnlinked: false,
                child: GestureDetector(
                  // Opaque so this small hit target blocks InteractiveViewer
                  // underneath it — a drag starting here never reaches its
                  // pan recognizer, so there's no gesture-arena race. Safe
                  // to rely on here specifically because this widget is a
                  // sibling of (not nested inside) InteractiveViewer — see
                  // the class doc on [posePicking].
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => _updateDraftYaw(d.globalPosition),
                  onPanUpdate: (d) => _updateDraftYaw(d.globalPosition),
                  // A generous 48px hit area for touch/mouse accuracy, with
                  // an intuitive rotation grab ring.
                  child: Container(
                    width: 48,
                    height: 48,
                    color: Colors.transparent,
                    alignment: Alignment.center,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.sync_rounded,
                            size: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Fades in once, the moment the first grid decodes — the map "arrives"
    // rather than snapping in over the skeleton. Threads a key through to
    // contentFor for the same reason posePicking's branch passes one —
    // [_handleMapTap] below needs it.
    Widget revealedFor(double markerScale, {Key? key}) =>
        FadeSlideIn(offset: 0, child: contentFor(markerScale, key: key));

    if (widget.interactive) {
      // The InteractiveViewer branch has a live, user-driven zoom worth
      // counter-scaling the marker against, so it stays a constant,
      // legible on-screen size instead of growing with the map.
      final viewScale = _controller.value.getMaxScaleOnAxis();
      final markerScale = 1 / (viewScale <= 0 ? 1.0 : viewScale);
      final viewer = InteractiveViewer(
        transformationController: _controller,
        minScale: 0.2,
        maxScale: 8,
        boundaryMargin: const EdgeInsets.all(200),
        child: Center(child: revealedFor(markerScale, key: _contentBoxKey)),
      );
      if (widget.onLocationTap == null && widget.onDockTap == null && !widget.dockEditorMode) {
        return _withLocalizationBadge(viewer);
      }
      // A GestureDetector wrapping InteractiveViewer (rather than nested
      // inside it) sees plain taps without competing with InteractiveViewer's
      // own pan/zoom recognizer — the same "wrap, don't nest" reasoning the
      // class doc gives for why posePicking swaps the whole tree instead.
      return _withLocalizationBadge(GestureDetector(
        onTapUp: (details) => _handleMapTap(details.globalPosition),
        child: viewer,
      ));
    }

    // Thumbnail views (Dashboard's live preview, Maps List's card): the
    // zoom level is always "fit the map's width to the container" — a
    // resolution-independent, predictable scale, not a variable zoom — but
    // for a portrait-shaped map that overflows the container's height,
    // *which* horizontal slice of the map is visible still matters. Rather
    // than defaulting to the top of the map (plain FittedBox's behavior),
    // pan vertically so the robot stays centered in view, clamped so the
    // window never scrolls past the map's own top/bottom edge into blank
    // space. Falls back to vertically centering the whole map when it's not
    // localized yet (nothing to center on) or when the map is short enough
    // to fit without any cropping at all.
    //
    // fitWholeMap (a mission's route preview, _RouteMapCard) skips all of
    // that: it fits both axes and never crops, because the thing that has
    // to stay visible there is every pin along the route, not the robot —
    // which may not even be near any of them.
    return _withLocalizationBadge(LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (!viewport.isFinite || grid.info.width <= 0) {
          return FittedBox(
              fit: BoxFit.fitWidth,
              clipBehavior: Clip.hardEdge,
              child: revealedFor(1.0));
        }
        final scaleW = viewport.width / grid.info.width;
        // fitWholeMap additionally caps scale to the height ratio, so a
        // portrait-shaped map never exceeds the viewport's height either —
        // the whole map fits with no cropping, letterboxed on whichever
        // axis has slack, instead of fitting width and cropping/panning
        // vertically to the robot.
        final scale = widget.fitWholeMap
            ? min(scaleW, viewport.height / grid.info.height)
            : scaleW;
        // Counter-scales the marker against this thumbnail's own fit-width
        // factor — without it, a map with many pixels per meter (a
        // fine-resolution map, scaled down a lot to fit a small preview)
        // draws the marker at its full native size and it reads as
        // oversized; this keeps it the same constant, legible size the
        // interactive view uses at 1x zoom, regardless of the map's
        // resolution or the preview's own size.
        final markerScale = 1 / (scale <= 0 ? 1.0 : scale);
        final mapWidthScaled = grid.info.width * scale;
        final mapHeightScaled = grid.info.height * scale;
        final offsetX =
            widget.fitWholeMap ? (viewport.width - mapWidthScaled) / 2 : 0.0;
        double offsetY;
        final pose = _effectivePose;
        if (widget.fitWholeMap || mapHeightScaled <= viewport.height) {
          offsetY = (viewport.height - mapHeightScaled) / 2;
        } else if (widget.showRobot && pose != null) {
          final robotPixel = _worldToPixel(
              grid, pose.pose.pose.position.x, pose.pose.pose.position.y);
          final desired = viewport.height / 2 - robotPixel.dy * scale;
          offsetY = desired.clamp(viewport.height - mapHeightScaled, 0.0);
        } else {
          offsetY = 0;
        }
        return ClipRect(
          child: OverflowBox(
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            // OverflowBox's default alignment (center) would pre-center the
            // CustomPaint's natural (unscaled) size within the viewport at
            // layout time, and the Transform below would then stack its own
            // translate/scale on top of that — double positioning (the same
            // bug this exact fix addressed for the old center-on-robot
            // preview). topLeft keeps this Transform's local origin
            // coincident with the viewport's, so translate/scale below is
            // the sole source of positioning.
            alignment: Alignment.topLeft,
            child: Transform(
              transform: Matrix4.identity()
                ..translateByDouble(offsetX, offsetY, 0, 1)
                ..scaleByDouble(scale, scale, scale, 1.0),
              child: revealedFor(markerScale),
            ),
          ),
        );
      },
    ));
  }
}

/// A decoded costmap image paired with the grid it came from — needed
/// alongside the image because the costmap's own resolution/origin/size
/// (its footprint in the world) is what positions it, via [_worldToPixel]
/// applied to its corners, not just where the base map happens to be.
class _CostmapLayer {
  const _CostmapLayer({required this.grid, required this.image});

  final nav_msgs.OccupancyGrid grid;
  final ui.Image image;
}

class _OccupancyGridPainter extends CustomPainter {
  _OccupancyGridPainter({
    required this.image,
    required this.grid,
    required this.pose,
    required this.dockPose,
    required this.path,
    required this.globalCostmap,
    required this.localCostmap,
    required this.mapOdomTransform,
    required this.locations,
    required this.showWaypointRoute,
    required this.draftPixel,
    required this.draftYaw,
    this.markerScale = 1.0,
    this.scan,
    this.dockEditorMode = false,
    this.dockEditorDockPoint,
    this.dockEditorStandoffPoint,
    this.dockEditorActiveIndex = 0,
  });

  final ui.Image image;
  final nav_msgs.OccupancyGrid grid;
  final geometry_msgs.PoseWithCovarianceStamped? pose;
  final geometry_msgs.PoseStamped? dockPose;
  final nav_msgs.Path? path;
  final _CostmapLayer? globalCostmap;
  final _CostmapLayer? localCostmap;
  final _RigidTransform2D? mapOdomTransform;
  final List<Map<String, dynamic>> locations;
  final bool showWaypointRoute;
  final Offset? draftPixel;
  final double draftYaw;
  final double markerScale;
  final sensor_msgs.LaserScan? scan;
  final bool dockEditorMode;
  final ({double x, double y})? dockEditorDockPoint;
  final ({double x, double y})? dockEditorStandoffPoint;
  final int dockEditorActiveIndex;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
    final resolution = grid.info.resolution;
    if (resolution <= 0) return;

    final global = globalCostmap;
    if (global != null) _drawCostmapLayer(canvas, global);
    final local = localCostmap;
    if (local != null) {
      _drawCostmapLayer(canvas, local, frameTransform: mapOdomTransform);
    }

    _drawPath(canvas);
    if (showWaypointRoute) _drawWaypointRoute(canvas);

    for (final loc in locations) {
      if (loc['x'] is! num || loc['y'] is! num) continue;
      final center = _worldToPixel(
          grid, (loc['x'] as num).toDouble(), (loc['y'] as num).toDouble());
      _drawPin(canvas, center, AppColors.primary, Icons.place_rounded,
          sizeScale: markerScale);
      final name = loc['name'] as String?;
      if (name != null && name.isNotEmpty) {
        _drawPinLabel(canvas, center, name, sizeScale: markerScale);
      }
    }

    final dock = dockPose;
    if (dock != null) {
      final center =
          _worldToPixel(grid, dock.pose.position.x, dock.pose.position.y);
      _drawPin(canvas, center, AppColors.stateDocking, Icons.ev_station_rounded,
          sizeScale: markerScale);
    }

    final p = pose;
    if (p != null) {
      final center =
          _worldToPixel(grid, p.pose.pose.position.x, p.pose.pose.position.y);
      final yaw = _yawOf(p.pose.pose.orientation);
      _drawRobotMarker(canvas, center, yaw, AppColors.primary,
          sizeScale: markerScale);
    }

    final draft = draftPixel;
    if (draft != null) {
      _drawPickerMarker(canvas, draft, draftYaw, AppColors.accent,
          sizeScale: markerScale);
    }

    final s = scan;
    if (s != null) _drawLaserScan(canvas, s);

    if (dockEditorMode) {
      _drawDockEditor(canvas);
    }
  }

  void _drawLaserScan(Canvas canvas, sensor_msgs.LaserScan s) {
    final p = pose;
    if (p == null) return;
    final robotX = p.pose.pose.position.x;
    final robotY = p.pose.pose.position.y;
    final robotYaw = _yawOf(p.pose.pose.orientation);

    final dotRadius = 1.6 * markerScale;
    final paint = Paint()
      ..color = const Color(0xFFFF2B3C).withValues(alpha: 0.90)
      ..style = PaintingStyle.fill;

    final len = s.ranges.length;
    for (var i = 0; i < len; i++) {
      final r = s.ranges[i];
      if (r.isNaN || r.isInfinite || r < s.range_min || r > s.range_max) {
        continue;
      }
      final beamAngle = s.angle_min + i * s.angle_increment;
      final worldAngle = robotYaw + beamAngle;
      final wx = robotX + r * cos(worldAngle);
      final wy = robotY + r * sin(worldAngle);
      final px = _worldToPixel(grid, wx, wy);
      canvas.drawCircle(px, dotRadius, paint);
    }
  }

  void _drawDockEditor(Canvas canvas) {
    final dockPt = dockEditorDockPoint;
    final standoffPt = dockEditorStandoffPoint;

    Offset? dockPixel;
    Offset? standoffPixel;
    if (dockPt != null) {
      dockPixel = _worldToPixel(grid, dockPt.x, dockPt.y);
    }
    if (standoffPt != null) {
      standoffPixel = _worldToPixel(grid, standoffPt.x, standoffPt.y);
    }

    if (dockPixel != null && standoffPixel != null && dockPt != null && standoffPt != null) {
      final dx = standoffPt.x - dockPt.x;
      final dy = standoffPt.y - dockPt.y;
      final dist = sqrt(dx * dx + dy * dy);
      final dockHeading = atan2(dy, dx);
      final standoffHeading = atan2(-dy, -dx);

      // Connecting guide line
      final linePaint = Paint()
        ..color = AppColors.stateDocking
        ..strokeWidth = 2.5 * markerScale
        ..style = PaintingStyle.stroke;
      canvas.drawLine(dockPixel, standoffPixel, linePaint);

      // Distance badge pill in middle of line
      final midPixel = Offset(
        (dockPixel.dx + standoffPixel.dx) / 2,
        (dockPixel.dy + standoffPixel.dy) / 2,
      );
      final distText = '${(dist * 100).toStringAsFixed(1)} cm (${dist.toStringAsFixed(2)} m)';
      _drawPillLabel(canvas, midPixel, distText, AppColors.stateDocking, sizeScale: markerScale);

      // Dock Marker (⚡) with orientation pointing towards standoff
      _drawDockStationMarker(canvas, dockPixel, dockHeading, isSelected: dockEditorActiveIndex == 0, sizeScale: markerScale);

      // Standoff Marker (🎯) with orientation pointing towards dock
      _drawStandoffPointMarker(canvas, standoffPixel, standoffHeading, isSelected: dockEditorActiveIndex == 1, sizeScale: markerScale);
    } else {
      if (dockPixel != null) {
        _drawDockStationMarker(canvas, dockPixel, 0.0, isSelected: dockEditorActiveIndex == 0, sizeScale: markerScale);
      }
      if (standoffPixel != null) {
        _drawStandoffPointMarker(canvas, standoffPixel, 0.0, isSelected: dockEditorActiveIndex == 1, sizeScale: markerScale);
      }
    }
  }

  void _drawDockStationMarker(Canvas canvas, Offset center, double heading, {required bool isSelected, double sizeScale = 1.0}) {
    final radius = 14 * sizeScale;
    if (isSelected) {
      canvas.drawCircle(center, radius + 8 * sizeScale, Paint()..color = AppColors.stateDocking.withValues(alpha: 0.25));
      canvas.drawCircle(center, radius + 4 * sizeScale, Paint()..color = AppColors.stateDocking.withValues(alpha: 0.45));
    }
    // Directional heading arrow pointing along heading
    final arrowDist = radius + 8 * sizeScale;
    final arrowTip = center + Offset(arrowDist * cos(heading), -arrowDist * sin(heading));
    final arrowLeft = center + Offset((radius + 2 * sizeScale) * cos(heading + 0.5), -(radius + 2 * sizeScale) * sin(heading + 0.5));
    final arrowRight = center + Offset((radius + 2 * sizeScale) * cos(heading - 0.5), -(radius + 2 * sizeScale) * sin(heading - 0.5));
    final arrowPath = Path()..moveTo(arrowTip.dx, arrowTip.dy)..lineTo(arrowLeft.dx, arrowLeft.dy)..lineTo(arrowRight.dx, arrowRight.dy)..close();
    canvas.drawPath(arrowPath, Paint()..color = AppColors.stateDocking);

    _drawPin(canvas, center, AppColors.stateDocking, Icons.ev_station_rounded, sizeScale: sizeScale);
    _drawPinLabel(canvas, center, '1. Dock Station (⚡)', sizeScale: sizeScale);
  }

  void _drawStandoffPointMarker(Canvas canvas, Offset center, double heading, {required bool isSelected, double sizeScale = 1.0}) {
    final radius = 14 * sizeScale;
    if (isSelected) {
      canvas.drawCircle(center, radius + 8 * sizeScale, Paint()..color = AppColors.primary.withValues(alpha: 0.25));
      canvas.drawCircle(center, radius + 4 * sizeScale, Paint()..color = AppColors.primary.withValues(alpha: 0.45));
    }
    // Directional heading arrow pointing along heading
    final arrowDist = radius + 8 * sizeScale;
    final arrowTip = center + Offset(arrowDist * cos(heading), -arrowDist * sin(heading));
    final arrowLeft = center + Offset((radius + 2 * sizeScale) * cos(heading + 0.5), -(radius + 2 * sizeScale) * sin(heading + 0.5));
    final arrowRight = center + Offset((radius + 2 * sizeScale) * cos(heading - 0.5), -(radius + 2 * sizeScale) * sin(heading - 0.5));
    final arrowPath = Path()..moveTo(arrowTip.dx, arrowTip.dy)..lineTo(arrowLeft.dx, arrowLeft.dy)..lineTo(arrowRight.dx, arrowRight.dy)..close();
    canvas.drawPath(arrowPath, Paint()..color = AppColors.primary);

    _drawPin(canvas, center, AppColors.primary, Icons.my_location_rounded, sizeScale: sizeScale);
    _drawPinLabel(canvas, center, '2. Standoff Point (🎯)', sizeScale: sizeScale);
  }

  void _drawPillLabel(Canvas canvas, Offset center, String text, Color color, {double sizeScale = 1.0}) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10 * sizeScale,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    )..layout();

    final pillWidth = textPainter.width + 12 * sizeScale;
    final pillHeight = textPainter.height + 6 * sizeScale;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: pillWidth, height: pillHeight),
      Radius.circular(pillHeight / 2),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.black.withValues(alpha: 0.85));
    canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: 0.9)..style = PaintingStyle.stroke..strokeWidth = 1.2 * sizeScale);
    textPainter.paint(canvas, center - Offset(textPainter.width / 2, textPainter.height / 2));
  }

  /// [frameTransform] is the rigid transform from this layer's own
  /// publishing frame into `map` — null when the layer is already in
  /// `map` (the global costmap, always) or, for the local costmap, until
  /// the first live `/tf` reading arrives (see [OccupancyGridView]'s class
  /// doc), in which case its frame is optimistically treated as `map`
  /// outright rather than not drawing it at all.
  void _drawCostmapLayer(Canvas canvas, _CostmapLayer layer,
      {_RigidTransform2D? frameTransform}) {
    final costGrid = layer.grid;
    final res = costGrid.info.resolution;
    if (res <= 0) return;
    final ox = costGrid.info.origin.position.x;
    final oy = costGrid.info.origin.position.y;
    final w = costGrid.info.width * res;
    final h = costGrid.info.height * res;

    // A point in the layer's own frame -> the base map's pixel space,
    // composing through frameTransform first when the layer isn't already
    // in `map` (a plain rotate-then-translate — frameTransform carries no
    // scale, matching a rigid TF edge).
    Offset toPixel(double x, double y) {
      final t = frameTransform;
      if (t == null) return _worldToPixel(grid, x, y);
      final c = cos(t.theta), s = sin(t.theta);
      return _worldToPixel(grid, t.x + c * x - s * y, t.y + s * x + c * y);
    }

    // The costmap's own footprint, in the base map's pixel space — not
    // assumed to match the base map's own bounds (the local costmap is a
    // window around the robot, sized/positioned independently). Three
    // corners (not just opposite corners of an axis-aligned box, as when
    // there's no rotation to account for) fully determine the affine
    // mapping from the image's own pixel space into the canvas below,
    // including whatever rotation frameTransform carries.
    final imgW = layer.image.width.toDouble();
    final imgH = layer.image.height.toDouble();
    final topLeft = toPixel(ox, oy + h); // image (0, 0)
    final topRight = toPixel(ox + w, oy + h); // image (imgW, 0)
    final bottomLeft = toPixel(ox, oy); // image (0, imgH)
    final u = (topRight - topLeft) / imgW;
    final v = (bottomLeft - topLeft) / imgH;

    canvas.save();
    canvas.transform((Matrix4.identity()
          ..setEntry(0, 0, u.dx)
          ..setEntry(1, 0, u.dy)
          ..setEntry(0, 1, v.dx)
          ..setEntry(1, 1, v.dy)
          ..setEntry(0, 3, topLeft.dx)
          ..setEntry(1, 3, topLeft.dy))
        .storage);
    canvas.drawImageRect(
      layer.image,
      Rect.fromLTWH(0, 0, imgW, imgH),
      Rect.fromLTWH(0, 0, imgW, imgH),
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();
  }

  void _drawPath(Canvas canvas) {
    final poses = path?.poses;
    if (poses == null || poses.length < 2) return;
    final points = poses
        .map((p) => _worldToPixel(grid, p.pose.position.x, p.pose.position.y))
        .toList();
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final pt in points.skip(1)) {
      linePath.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = AppColors.stateExecuting
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// A straight-line, dashed connector between [locations] in list order —
  /// a mission's own planned route (the order its steps visit them in), not
  /// the live `/plan` [_drawPath] draws (nav2's actual planned trajectory
  /// between two poses, curved around obstacles). Dashed and in the pins'
  /// own color specifically so it reads as "the sequence these are visited
  /// in", not mistaken for a real drivable path the robot will follow.
  void _drawWaypointRoute(Canvas canvas) {
    final points = <Offset>[];
    for (final loc in locations) {
      if (loc['x'] is! num || loc['y'] is! num) continue;
      points.add(_worldToPixel(
          grid, (loc['x'] as num).toDouble(), (loc['y'] as num).toDouble()));
    }
    if (points.length < 2) return;
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dashLen = 6.0;
    const gapLen = 5.0;
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      final segment = end - start;
      final length = segment.distance;
      if (length < 1e-6) continue;
      final direction = segment / length;
      var travelled = 0.0;
      while (travelled < length) {
        final dashEnd = min(travelled + dashLen, length);
        canvas.drawLine(
          start + direction * travelled,
          start + direction * dashEnd,
          paint,
        );
        travelled = dashEnd + gapLen;
      }
    }
  }

  /// A dot-plus-direction-cone marker — the same visual language a phone's
  /// "you are here, facing this way" map marker uses, which reads at a
  /// glance far more clearly than a thin line ever did. A white halo under
  /// the dot keeps it visible against both the pale "free space" and the
  /// darker "occupied" regions of the map underneath.
  /// A high-visibility robot marker with a crisp chassis circle, a wide
  /// directional cone, and a prominent forward-pointing arrow chevron that
  /// scales consistently with [sizeScale] so it never disappears when zoomed in.
  void _drawRobotMarker(
    Canvas canvas,
    Offset center,
    double yaw,
    Color color, {
    double dotRadius = _draftDotRadius,
    double coneRadius = _draftConeRadius,
    double sizeScale = 1.0,
  }) {
    final r = dotRadius * sizeScale;
    final strokeW = 2.0 * sizeScale;

    // 1. Soft wide orientation field / headlight cone
    final coneR = coneRadius * sizeScale;
    const coneHalfAngle = 0.52; // ~30° spread
    const segments = 16;
    final conePath = Path()..moveTo(center.dx, center.dy);
    for (var i = 0; i <= segments; i++) {
      final t = -coneHalfAngle + (2 * coneHalfAngle) * (i / segments);
      final angle = yaw + t;
      conePath.lineTo(
          center.dx + coneR * cos(angle), center.dy - coneR * sin(angle));
    }
    conePath.close();
    canvas.drawPath(conePath, Paint()..color = color.withValues(alpha: 0.25));

    // 2. Chassis outer shadow ring
    canvas.drawCircle(
      center,
      r + 2.5 * sizeScale,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    // 3. Robot chassis body disc
    canvas.drawCircle(center, r, Paint()..color = color);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    // 4. Prominent, high-contrast forward-pointing arrow chevron
    // Extends past the front edge of the robot circle along yaw.
    final arrowTipDist = r + 8.0 * sizeScale;
    final arrowBaseDist = r * 0.15;
    final arrowWingDist = r * 0.95;
    const arrowWingAngle = 0.70;

    final tip = center +
        Offset(arrowTipDist * cos(yaw), -arrowTipDist * sin(yaw));
    final leftWing = center +
        Offset(arrowWingDist * cos(yaw + arrowWingAngle),
            -arrowWingDist * sin(yaw + arrowWingAngle));
    final rightWing = center +
        Offset(arrowWingDist * cos(yaw - arrowWingAngle),
            -arrowWingDist * sin(yaw - arrowWingAngle));
    final base = center +
        Offset(arrowBaseDist * cos(yaw), -arrowBaseDist * sin(yaw));

    final arrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(leftWing.dx, leftWing.dy)
      ..lineTo(base.dx, base.dy)
      ..lineTo(rightWing.dx, rightWing.dy)
      ..close();

    // Dark stroke outline around arrow for maximum legibility against any background
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * sizeScale,
    );

    // Solid bright white pointer arrow
    canvas.drawPath(arrowPath, Paint()..color = Colors.white);

    // Center pivot core
    canvas.drawCircle(center, 2.5 * sizeScale, Paint()..color = Colors.white);
  }

  /// Location picker marker: uses the robot marker design (chassis disc,
  /// shock ring, prominent direction chevron arrow, center core), with an
  /// anchor tether line tied from the marker center out to the rotation handle.
  void _drawPickerMarker(
    Canvas canvas,
    Offset center,
    double yaw,
    Color color, {
    double sizeScale = 1.0,
  }) {
    final r = 12.0 * sizeScale;
    final strokeW = 2.0 * sizeScale;
    final anchorDist = 44.0 * sizeScale;
    final anchorPoint =
        center + Offset(anchorDist * cos(yaw), -anchorDist * sin(yaw));

    // 1. Anchor tether line tied from the marker to the rotation anchor node
    canvas.drawLine(
      center,
      anchorPoint,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..strokeWidth = 3.5 * sizeScale
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      center,
      anchorPoint,
      Paint()
        ..color = color
        ..strokeWidth = 2.0 * sizeScale
        ..style = PaintingStyle.stroke,
    );

    // Anchor node base ring tied at the tip
    canvas.drawCircle(
      anchorPoint,
      7.0 * sizeScale,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      anchorPoint,
      4.5 * sizeScale,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * sizeScale,
    );

    // 2. Robot-style Chassis Body Marker
    // Soft outer shadow / glow
    canvas.drawCircle(
      center,
      r + 3.0 * sizeScale,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Translucent outer shock ring
    canvas.drawCircle(
      center,
      r + 1.5 * sizeScale,
      Paint()
        ..color = color.withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * sizeScale,
    );

    // Robot chassis body disc
    canvas.drawCircle(center, r, Paint()..color = color);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    // 3. Prominent forward-pointing arrow chevron on the robot chassis body
    final arrowTipDist = r + 8.0 * sizeScale;
    final arrowBaseDist = r * 0.15;
    final arrowWingDist = r * 0.95;
    const arrowWingAngle = 0.70;

    final tip = center +
        Offset(arrowTipDist * cos(yaw), -arrowTipDist * sin(yaw));
    final leftWing = center +
        Offset(arrowWingDist * cos(yaw + arrowWingAngle),
            -arrowWingDist * sin(yaw + arrowWingAngle));
    final rightWing = center +
        Offset(arrowWingDist * cos(yaw - arrowWingAngle),
            -arrowWingDist * sin(yaw - arrowWingAngle));
    final base = center +
        Offset(arrowBaseDist * cos(yaw), -arrowBaseDist * sin(yaw));

    final arrowPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(leftWing.dx, leftWing.dy)
      ..lineTo(base.dx, base.dy)
      ..lineTo(rightWing.dx, rightWing.dy)
      ..close();

    // Dark stroke outline around arrow for maximum legibility
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * sizeScale,
    );

    // Solid bright white pointer arrow
    canvas.drawPath(arrowPath, Paint()..color = Colors.white);

    // Center pivot core
    canvas.drawCircle(center, 2.5 * sizeScale, Paint()..color = Colors.white);
  }

  /// A colored circle with a real icon glyph on top — location pins get
  /// [Icons.place_rounded], the dock pin [Icons.ev_station_rounded] (the
  /// same glyph used for dock everywhere else in the app), so the two read
  /// as genuinely distinct at a glance rather than "two dots, one with a
  /// smaller dot inside". [sizeScale] counter-scales the pin against the
  /// current view zoom the same way _drawRobotMarker's sizeScale does —
  /// previously fixed at a flat 6px regardless of zoom, so a pin visually
  /// shrank to a speck when zoomed in and ballooned when zoomed out instead
  /// of holding a constant on-screen size like the robot marker already did.
  void _drawPin(Canvas canvas, Offset center, Color color, IconData icon,
      {double sizeScale = 1.0}) {
    final radius = 12 * sizeScale;
    canvas.drawCircle(center, radius, Paint()..color = color);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final textPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: radius * 1.15,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  /// A small pill label centered above a location pin's icon, so a saved
  /// location reads by name at a glance instead of requiring a tap — the
  /// same "name above the marker" convention most map apps use. Drawn with
  /// its own white background (not just outlined text) since the pin sits
  /// on top of the occupancy grid's own black/white/gray palette, where
  /// plain text of either color can disappear depending on what's under it.
  void _drawPinLabel(Canvas canvas, Offset pinCenter, String name,
      {double sizeScale = 1.0}) {
    final radius = 12 * sizeScale;
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: name,
        style: TextStyle(
          fontSize: 11 * sizeScale,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    )..layout(maxWidth: 120 * sizeScale);

    const paddingH = 6.0;
    const paddingV = 3.0;
    final gap = 4 * sizeScale;
    final pillWidth = textPainter.width + paddingH * 2 * sizeScale;
    final pillHeight = textPainter.height + paddingV * 2 * sizeScale;
    final pillCenter =
        Offset(pinCenter.dx, pinCenter.dy - radius - gap - pillHeight / 2);
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pillCenter, width: pillWidth, height: pillHeight),
      Radius.circular(pillHeight / 2),
    );

    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawRRect(pillRect, Paint()..color = Colors.white);
    textPainter.paint(
      canvas,
      pillCenter - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _OccupancyGridPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.pose != pose ||
      oldDelegate.dockPose != dockPose ||
      oldDelegate.path != path ||
      oldDelegate.globalCostmap != globalCostmap ||
      oldDelegate.localCostmap != localCostmap ||
      oldDelegate.mapOdomTransform != mapOdomTransform ||
      oldDelegate.locations != locations ||
      oldDelegate.showWaypointRoute != showWaypointRoute ||
      oldDelegate.draftPixel != draftPixel ||
      oldDelegate.draftYaw != draftYaw ||
      oldDelegate.markerScale != markerScale ||
      oldDelegate.scan != scan ||
      oldDelegate.dockEditorMode != dockEditorMode ||
      oldDelegate.dockEditorDockPoint != dockEditorDockPoint ||
      oldDelegate.dockEditorStandoffPoint != dockEditorStandoffPoint ||
      oldDelegate.dockEditorActiveIndex != dockEditorActiveIndex;
}
