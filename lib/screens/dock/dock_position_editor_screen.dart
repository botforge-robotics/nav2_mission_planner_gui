import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/locations_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map/micro_adjustment_hud.dart';
import '../../widgets/map/occupancy_grid_view.dart';

/// Visual Dock & Standoff Position Editor.
///
/// Places 2 markers on the map connected by a line:
/// - Marker 1: Dock Station (⚡) - physical charger contact pose
/// - Marker 2: Standoff Point (🎯) - approach staging pose
///
/// Orientation is automatically computed:
/// - Dock orientation faces toward the Standoff point
/// - Standoff orientation faces directly toward the Dock point
///
/// The distance between them is displayed continuously along the line,
/// and either point can be nudged using precision 5mm arrow buttons.
class DockPositionEditorScreen extends StatefulWidget {
  const DockPositionEditorScreen({super.key});

  @override
  State<DockPositionEditorScreen> createState() =>
      _DockPositionEditorScreenState();
}

class _DockPositionEditorScreenState extends State<DockPositionEditorScreen> {
  ({double x, double y})? _dockPoint;
  ({double x, double y})? _standoffPoint;

  // 0 = Dock Point, 1 = Standoff Point
  int _activePointIndex = 0;
  bool _saving = false;
  bool _loading = true;

  // Undo history stack
  final List<({({double x, double y})? dock, ({double x, double y})? standoff, int activeIndex})> _history = [];

  void _pushHistory() {
    _history.add((
      dock: _dockPoint,
      standoff: _standoffPoint,
      activeIndex: _activePointIndex,
    ));
    if (_history.length > 50) _history.removeAt(0);
  }

  void _undo() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    setState(() {
      _dockPoint = prev.dock;
      _standoffPoint = prev.standoff;
      _activePointIndex = prev.activeIndex;
    });
  }

  SdkApiService? get _api {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    return ip == null ? null : SdkApiService(ip);
  }

  @override
  void initState() {
    super.initState();
    _loadInitialPositions();
  }

  Future<void> _loadInitialPositions() async {
    final api = _api;
    if (api != null) {
      try {
        final dockData = await api.dockPose();
        final x = (dockData['x'] as num?)?.toDouble();
        final y = (dockData['y'] as num?)?.toDouble();
        if (x != null && y != null) {
          _dockPoint = (x: x, y: y);
        }
      } catch (_) {
        // No dock pose configured yet
      }

      // Check for saved standoff waypoint
      try {
        final locs = await api.listWaypoints();
        for (final loc in locs) {
          final name = (loc['name'] as String?)?.toLowerCase() ?? '';
          if (name.contains('standoff') || name.contains('staging')) {
            final x = (loc['x'] as num?)?.toDouble();
            final y = (loc['y'] as num?)?.toDouble();
            if (x != null && y != null) {
              _standoffPoint = (x: x, y: y);
              break;
            }
          }
        }
      } catch (_) {}
    }

    // Default standoff if dock exists but standoff doesn't
    if (_dockPoint != null && _standoffPoint == null) {
      _standoffPoint = (x: _dockPoint!.x + 0.65, y: _dockPoint!.y);
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  double get _distance {
    if (_dockPoint == null || _standoffPoint == null) return 0.0;
    final dx = _standoffPoint!.x - _dockPoint!.x;
    final dy = _standoffPoint!.y - _dockPoint!.y;
    return sqrt(dx * dx + dy * dy);
  }

  double get _dockAngle {
    if (_dockPoint == null || _standoffPoint == null) return 0.0;
    return atan2(_standoffPoint!.y - _dockPoint!.y, _standoffPoint!.x - _dockPoint!.x);
  }

  double get _standoffAngle {
    if (_dockPoint == null || _standoffPoint == null) return 0.0;
    // Points in reverse direction: toward dock
    return atan2(_dockPoint!.y - _standoffPoint!.y, _dockPoint!.x - _standoffPoint!.x);
  }

  void _onMapTap(double wx, double wy) {
    _pushHistory();
    setState(() {
      if (_activePointIndex == 0) {
        _dockPoint = (x: wx, y: wy);
        if (_standoffPoint == null) {
          _activePointIndex = 1; // prompt user to tap standoff next
        }
      } else {
        _standoffPoint = (x: wx, y: wy);
      }
    });
  }

  void _onNudge(double dx, double dy) {
    _pushHistory();
    setState(() {
      if (_activePointIndex == 0 && _dockPoint != null) {
        _dockPoint = (x: _dockPoint!.x + dx, y: _dockPoint!.y + dy);
      } else if (_activePointIndex == 1 && _standoffPoint != null) {
        _standoffPoint = (x: _standoffPoint!.x + dx, y: _standoffPoint!.y + dy);
      }
    });
  }

  Future<void> _save() async {
    if (_dockPoint == null || _standoffPoint == null) return;
    setState(() => _saving = true);
    final api = _api;
    if (api == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Robot SDK is not connected.')),
      );
      setState(() => _saving = false);
      return;
    }

    try {
      // 1. Set dock pose on robot
      await api.setDockPose(
        x: _dockPoint!.x,
        y: _dockPoint!.y,
        theta: _dockAngle,
      );

      // 2. Save/update "Dock Standoff" waypoint
      await api.saveWaypoint(
        'Dock Standoff',
        x: _standoffPoint!.x,
        y: _standoffPoint!.y,
        theta: _standoffAngle,
      );
      await LocationsController.instance.refresh(api);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dock and Standoff poses saved successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save dock pose: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ros2 = context.watch<ConnectionProvider>().ros2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dock & Standoff Pose Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            tooltip: _history.isNotEmpty ? 'Undo (${_history.length})' : 'Undo',
            onPressed: _history.isNotEmpty ? _undo : null,
          ),
          if (_dockPoint != null && _standoffPoint != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Save Positions'),
              ),
            ),
        ],
      ),
      body: ros2 == null
          ? const Center(child: Text('Not connected to robot.'))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    // Interactive Map with Dock Editor Layer
                    Positioned.fill(
                      child: OccupancyGridView(
                        ros2: ros2,
                        interactive: true,
                        showDock: false, // hidden in favor of our active editor markers
                        showLaserScan: true,
                        dockEditorMode: true,
                        dockEditorDockPoint: _dockPoint,
                        dockEditorStandoffPoint: _standoffPoint,
                        dockEditorActiveIndex: _activePointIndex,
                        onDockEditorTap: _onMapTap,
                      ),
                    ),

                    // Top Control / Status HUD Bar
                    Positioned(
                      top: AppSpacing.sm,
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        color: AppColors.surface.withValues(alpha: 0.95),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  // Point selection tabs
                                  Expanded(
                                    child: SegmentedButton<int>(
                                      segments: [
                                        ButtonSegment(
                                          value: 0,
                                          icon: const Icon(Icons.ev_station_rounded,
                                              color: AppColors.stateDocking),
                                          label: Text(_dockPoint != null
                                              ? (_activePointIndex == 0 ? '1. Dock Station (Active)' : '1. Re-edit Dock')
                                              : '1. Place Dock'),
                                        ),
                                        ButtonSegment(
                                          value: 1,
                                          icon: const Icon(Icons.my_location_rounded,
                                              color: AppColors.primary),
                                          label: Text(_standoffPoint != null
                                              ? (_activePointIndex == 1 ? '2. Standoff (Active)' : '2. Re-edit Standoff')
                                              : '2. Place Standoff'),
                                        ),
                                      ],
                                      selected: {_activePointIndex},
                                      onSelectionChanged: (newSel) => setState(
                                          () => _activePointIndex = newSel.first),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  OutlinedButton.icon(
                                    onPressed: _history.isNotEmpty ? _undo : null,
                                    icon: const Icon(Icons.undo_rounded, size: 16),
                                    label: const Text('Undo'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      minimumSize: const Size(0, 40),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xs),

                              // Real-time telemetry readouts
                              Wrap(
                                spacing: 16,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (_dockPoint != null)
                                    Text(
                                      '⚡ Dock: (${_dockPoint!.x.toStringAsFixed(3)}, ${_dockPoint!.y.toStringAsFixed(3)}) θ: ${(_dockAngle * 180 / pi).toStringAsFixed(1)}°',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.stateDocking),
                                    ),
                                  if (_standoffPoint != null)
                                    Text(
                                      '🎯 Standoff: (${_standoffPoint!.x.toStringAsFixed(3)}, ${_standoffPoint!.y.toStringAsFixed(3)}) θ: ${(_standoffAngle * 180 / pi).toStringAsFixed(1)}°',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary),
                                    ),
                                  if (_dockPoint != null && _standoffPoint != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceSunken,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: Text(
                                        '📏 Separation: ${(_distance * 100).toStringAsFixed(1)} cm (${_distance.toStringAsFixed(3)} m)',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Floating 5mm Micro-Adjustment D-Pad HUD
                    Positioned(
                      bottom: AppSpacing.md,
                      right: AppSpacing.md,
                      child: MicroAdjustmentHud(
                        title: _activePointIndex == 0
                            ? 'Nudge Dock (⚡)'
                            : 'Nudge Standoff (🎯)',
                        showRotation: false, // auto-computed towards each other!
                        onNudge: _onNudge,
                      ),
                    ),

                    // Bottom info & quick switch banner
                    Positioned(
                      bottom: AppSpacing.md,
                      left: AppSpacing.md,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _dockPoint == null
                                  ? 'Tap map to place the Dock Station'
                                  : _standoffPoint == null
                                      ? 'Tap map to place the Standoff Point'
                                      : (_activePointIndex == 0
                                          ? 'Editing Dock Station (⚡)'
                                          : 'Editing Standoff Point (🎯)'),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary),
                            ),
                            if (_dockPoint != null && _standoffPoint != null) ...[
                              const SizedBox(width: 8),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => setState(() =>
                                    _activePointIndex =
                                        _activePointIndex == 0 ? 1 : 0),
                                icon: Icon(
                                  _activePointIndex == 0
                                      ? Icons.arrow_forward_rounded
                                      : Icons.arrow_back_rounded,
                                  size: 14,
                                ),
                                label: Text(
                                  _activePointIndex == 0
                                      ? 'Switch to Standoff'
                                      : 'Re-edit Dock',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
