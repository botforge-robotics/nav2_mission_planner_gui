import 'dart:math';
import 'package:flutter/foundation.dart';

import '../utils/localize_at_dock.dart';
import 'locations_controller.dart';
import 'sdk_api_service.dart';

class DockPoseData {
  final ({double x, double y, double theta})? dock;
  final ({double x, double y, double theta})? standoff;

  const DockPoseData({this.dock, this.standoff});

  DockPoseData copyWith({
    ({double x, double y, double theta})? dock,
    ({double x, double y, double theta})? standoff,
  }) {
    return DockPoseData(
      dock: dock ?? this.dock,
      standoff: standoff ?? this.standoff,
    );
  }
}

/// Shared controller for the robot's dock and standoff poses.
/// Mirrors [LocationsController] and [MapLayersController] so any change to
/// dock/standoff positions (e.g. from DockPositionEditorScreen) propagates
/// immediately to Dashboard, Teleop, and MapView without requiring remounts.
class DockPoseController extends ValueNotifier<DockPoseData> {
  DockPoseController._() : super(const DockPoseData());

  static final instance = DockPoseController._();

  /// Updates the value directly for instant optimistic UI updates
  void update({
    ({double x, double y, double theta})? dock,
    ({double x, double y, double theta})? standoff,
  }) {
    value = DockPoseData(dock: dock, standoff: standoff);
  }

  /// Fetches dock pose and resolves standoff from waypoints or geometric default.
  Future<void> refresh(SdkApiService api) async {
    try {
      final dock = await fetchDockPose(api);
      if (dock == null) {
        value = const DockPoseData();
        return;
      }

      final standoff = (
        x: dock.x + 0.70 * cos(dock.theta),
        y: dock.y + 0.70 * sin(dock.theta),
        theta: dock.theta,
      );

      value = DockPoseData(dock: dock, standoff: standoff);
    } catch (_) {
      // Keep last known value on transient errors
    }
  }
}
