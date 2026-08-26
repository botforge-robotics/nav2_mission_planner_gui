import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:nav_msgs/msg.dart' as nav_msgs;
import 'package:ros2_api/ros2_api.dart';

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
/// [posePicking] swaps the normal pan/zoom InteractiveViewer out for a
/// static, fit-to-screen view with its own tap+drag recognizer — a
/// deliberate choice over trying to disable InteractiveViewer's own
/// recognizer in place: Flutter still runs that recognizer even with
/// panEnabled/scaleEnabled false (its own doc comment says so), so nesting
/// a second pan recognizer inside it risks a gesture-arena conflict. A
/// clean swap avoids that risk entirely, at the cost of losing whatever
/// pan/zoom the user had — reasonable for "pick a point", which wants the
/// whole map visible anyway.
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
    this.showOverlays = true,
    this.transformationController,
    this.posePicking = false,
    this.onDraftPose,
    this.onLocationTap,
    this.onDockTap,
    this.showLocalizationBadge = true,
    this.dockPoseOverride,
  });

  final Ros2 ros2;
  final bool interactive;
  final bool showRobot;

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

  /// Called continuously while picking (on each drag update) and once more
  /// on release, with the map-frame pose implied by the current drag. Never
  /// called with a stale value — the parent always has the latest draft to
  /// submit when the operator confirms.
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

  nav_msgs.OccupancyGrid? _grid;
  ui.Image? _image;
  geometry_msgs.PoseWithCovarianceStamped? _pose;
  geometry_msgs.PoseStamped? _dockPose;

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

  TransformationController? _ownedController;
  TransformationController get _controller =>
      widget.transformationController ??
      (_ownedController ??= TransformationController());

  @override
  void initState() {
    super.initState();
    // Listened to so the robot marker can counter-scale against the current
    // zoom (see _onViewTransformChanged) — a marker drawn at a fixed size in
    // the image's own pixel space would otherwise grow right along with the
    // map under InteractiveViewer's zoom, quickly overwhelming the view at
    // high zoom instead of staying a legible, constant-size "you are here".
    _controller.addListener(_onViewTransformChanged);
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
    if (widget.showRobot) _subscribeRobot();
    if (widget.showDock) _subscribeDock();
    if (widget.showPath) _subscribePath();
    if (widget.showGlobalCostmap) _subscribeGlobalCostmap();
    if (widget.showLocalCostmap) _subscribeLocalCostmap();
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
      callback: (msg) {
        if (mounted) setState(() => _pose = msg);
      },
    );
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

  @override
  void didUpdateWidget(covariant OccupancyGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showRobot != oldWidget.showRobot) {
      if (widget.showRobot) {
        _subscribeRobot();
      } else {
        _poseSub?.unsubscribe();
        _poseSub = null;
        _pose = null;
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
      }
    }
  }

  Future<void> _onGrid(nav_msgs.OccupancyGrid grid) async {
    if (_building) return; // drop an overlapping rebuild rather than queue it
    _building = true;
    final width = grid.info.width;
    final height = grid.info.height;
    if (width <= 0 || height <= 0) {
      _building = false;
      return;
    }

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
    if (!mounted) {
      _building = false;
      return;
    }
    setState(() {
      _grid = grid;
      _image = image;
      _building = false;
    });
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
    final width = grid.info.width;
    final height = grid.info.height;
    if (width <= 0 || height <= 0) {
      if (isGlobal) {
        _buildingGlobalCostmap = false;
      } else {
        _buildingLocalCostmap = false;
      }
      return;
    }

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
    if (!mounted) {
      if (isGlobal) {
        _buildingGlobalCostmap = false;
      } else {
        _buildingLocalCostmap = false;
      }
      return;
    }
    setState(() {
      final layer = _CostmapLayer(grid: grid, image: image);
      if (isGlobal) {
        _globalCostmap = layer;
        _buildingGlobalCostmap = false;
      } else {
        _localCostmap = layer;
        _buildingLocalCostmap = false;
      }
    });
  }

  void _onPanStart(DragStartDetails d) {
    setState(() {
      _draftPixel = d.localPosition;
      _draftYaw = 0;
    });
    _reportDraft();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final origin = _draftPixel;
    if (origin == null) return;
    final delta = d.localPosition - origin;
    if (delta.distance > 4) {
      setState(() => _draftYaw = atan2(-delta.dy, delta.dx));
    }
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
    if (!widget.showRobot || !widget.showLocalizationBadge || _pose != null) {
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

  /// Hit-tests a tap (in the InteractiveViewer's own viewport coordinates)
  /// against every saved location's pin, plus the dock pin. Converts
  /// through the *inverse* of the current view transform to get back to
  /// the image's own pixel space — the same space [_worldToPixel]
  /// positions pins in — so the comparison is correct at any zoom level,
  /// then checks world-space distance against a tolerance sized in real
  /// meters (not pixels), so the tap target's effective on-screen size
  /// shrinks/grows sensibly with zoom the same way the pin itself visually
  /// does. The dock wins ties — it's a single, deliberately-placed pin, so
  /// a tap equidistant from it and a location pin is more likely aimed at
  /// the dock.
  void _handleMapTap(Offset viewportPoint) {
    final grid = _grid;
    if (grid == null) return;
    final inverse = Matrix4.inverted(_controller.value);
    final contentPoint = MatrixUtils.transformPoint(inverse, viewportPoint);
    final tapWorld = _pixelToWorld(grid, contentPoint);
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

    // Builds the painted map for a given marker counter-scale — a function
    // rather than a single built-once widget, because the right
    // counter-scale differs per branch below and, for the thumbnail branch,
    // isn't known until its LayoutBuilder resolves the viewport size.
    Widget contentFor(double markerScale) => CustomPaint(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          painter: _OccupancyGridPainter(
            image: image,
            grid: grid,
            pose: widget.showRobot ? _pose : null,
            dockPose:
                (widget.showDock && showOverlays) ? _resolvedDockPose : null,
            path: (widget.showPath && showOverlays) ? _path : null,
            globalCostmap: (widget.showGlobalCostmap && showOverlays)
                ? _globalCostmap
                : null,
            localCostmap: (widget.showLocalCostmap && showOverlays)
                ? _localCostmap
                : null,
            locations: showOverlays ? widget.locations : const [],
            draftPixel: widget.posePicking ? _draftPixel : null,
            draftYaw: _draftYaw,
            markerScale: markerScale,
          ),
        );

    if (widget.posePicking) {
      // FittedBox alone, inside a Stack's loose (unbounded-leaning)
      // constraints, sizes itself to its child's natural size rather than
      // filling the viewport — SizedBox.expand forces it to actually fill
      // the space this map view has, the same as the InteractiveViewer
      // branch below already does implicitly.
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.contain,
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            child: contentFor(1.0),
          ),
        ),
      );
    }

    // Fades in once, the moment the first grid decodes — the map "arrives"
    // rather than snapping in over the skeleton.
    Widget revealedFor(double markerScale) =>
        FadeSlideIn(offset: 0, child: contentFor(markerScale));

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
        child: Center(child: revealedFor(markerScale)),
      );
      if (widget.onLocationTap == null && widget.onDockTap == null) {
        return _withLocalizationBadge(viewer);
      }
      // A GestureDetector wrapping InteractiveViewer (rather than nested
      // inside it) sees plain taps without competing with InteractiveViewer's
      // own pan/zoom recognizer — the same "wrap, don't nest" reasoning the
      // class doc gives for why posePicking swaps the whole tree instead.
      return _withLocalizationBadge(GestureDetector(
        onTapUp: (details) => _handleMapTap(details.localPosition),
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
    return _withLocalizationBadge(LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (!viewport.isFinite || grid.info.width <= 0) {
          return FittedBox(
              fit: BoxFit.fitWidth,
              clipBehavior: Clip.hardEdge,
              child: revealedFor(1.0));
        }
        final scale = viewport.width / grid.info.width;
        // Counter-scales the marker against this thumbnail's own fit-width
        // factor — without it, a map with many pixels per meter (a
        // fine-resolution map, scaled down a lot to fit a small preview)
        // draws the marker at its full native size and it reads as
        // oversized; this keeps it the same constant, legible size the
        // interactive view uses at 1x zoom, regardless of the map's
        // resolution or the preview's own size.
        final markerScale = 1 / (scale <= 0 ? 1.0 : scale);
        final mapHeightScaled = grid.info.height * scale;
        double offsetY;
        final pose = _pose;
        if (mapHeightScaled <= viewport.height) {
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
                ..translateByDouble(0, offsetY, 0, 1)
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
    required this.locations,
    required this.draftPixel,
    required this.draftYaw,
    this.markerScale = 1.0,
  });

  final ui.Image image;
  final nav_msgs.OccupancyGrid grid;
  final geometry_msgs.PoseWithCovarianceStamped? pose;
  final geometry_msgs.PoseStamped? dockPose;
  final nav_msgs.Path? path;
  final _CostmapLayer? globalCostmap;
  final _CostmapLayer? localCostmap;
  final List<Map<String, dynamic>> locations;
  final Offset? draftPixel;
  final double draftYaw;

  /// Multiplies the robot marker's radius — the inverse of the current view
  /// zoom, so the marker's on-screen size stays constant instead of growing
  /// with the map as the operator zooms in. 1.0 outside an interactive,
  /// user-zoomable view (see OccupancyGridView.build).
  final double markerScale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
    final resolution = grid.info.resolution;
    if (resolution <= 0) return;

    final global = globalCostmap;
    if (global != null) _drawCostmapLayer(canvas, global);
    final local = localCostmap;
    if (local != null) _drawCostmapLayer(canvas, local);

    _drawPath(canvas);

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
      final q = p.pose.pose.orientation;
      final yaw =
          atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z));
      _drawRobotMarker(canvas, center, yaw, AppColors.primary,
          sizeScale: markerScale);
    }

    final draft = draftPixel;
    if (draft != null) {
      _drawRobotMarker(canvas, draft, draftYaw, AppColors.accent,
          dotRadius: 7, coneRadius: 20, sizeScale: markerScale);
    }
  }

  void _drawCostmapLayer(Canvas canvas, _CostmapLayer layer) {
    final costGrid = layer.grid;
    final res = costGrid.info.resolution;
    if (res <= 0) return;
    final ox = costGrid.info.origin.position.x;
    final oy = costGrid.info.origin.position.y;
    final w = costGrid.info.width * res;
    final h = costGrid.info.height * res;
    // The costmap's own footprint, in the base map's pixel space — not
    // assumed to match the base map's own bounds (the local costmap is a
    // window around the robot, sized/positioned independently).
    final topLeft = _worldToPixel(grid, ox, oy + h);
    final bottomRight = _worldToPixel(grid, ox + w, oy);
    final dest = Rect.fromPoints(topLeft, bottomRight);
    canvas.drawImageRect(
      layer.image,
      Rect.fromLTWH(
          0, 0, layer.image.width.toDouble(), layer.image.height.toDouble()),
      dest,
      Paint()..filterQuality = FilterQuality.low,
    );
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

  /// A dot-plus-direction-cone marker — the same visual language a phone's
  /// "you are here, facing this way" map marker uses, which reads at a
  /// glance far more clearly than a thin line ever did. A white halo under
  /// the dot keeps it visible against both the pale "free space" and the
  /// darker "occupied" regions of the map underneath.
  void _drawRobotMarker(
    Canvas canvas,
    Offset center,
    double yaw,
    Color color, {
    double dotRadius = 9,
    double coneRadius = 26,
    double sizeScale = 1.0,
  }) {
    dotRadius *= sizeScale;
    coneRadius *= sizeScale;
    const coneHalfAngle = 0.5; // ~28.6°, ~57° total spread
    const segments = 12;

    final conePath = Path()..moveTo(center.dx, center.dy);
    for (var i = 0; i <= segments; i++) {
      final t = -coneHalfAngle + (2 * coneHalfAngle) * (i / segments);
      final angle = yaw + t;
      // Canvas Y grows downward while yaw is measured counter-clockwise
      // from +X in the world frame — negate the Y term to match.
      conePath.lineTo(center.dx + coneRadius * cos(angle),
          center.dy - coneRadius * sin(angle));
    }
    conePath.close();
    canvas.drawPath(conePath, Paint()..color = color.withValues(alpha: 0.28));

    canvas.drawCircle(center, dotRadius + 3,
        Paint()..color = Colors.white.withValues(alpha: 0.9));
    canvas.drawCircle(center, dotRadius, Paint()..color = color);
    canvas.drawCircle(
      center,
      dotRadius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
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
      oldDelegate.locations != locations ||
      oldDelegate.draftPixel != draftPixel ||
      oldDelegate.draftYaw != draftYaw ||
      oldDelegate.markerScale != markerScale;
}
