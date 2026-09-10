import 'dart:async';
import 'package:flutter/foundation.dart';

/// Tracks mode changes that take time on the robot (e.g. stopping SLAM mapping
/// or switching onto a new map). The Raspberry Pi typically takes 10-15 seconds
/// to kill slam_toolbox and settle into idle/navigation. During this window,
/// this tracker informs the UI to show an animated transition state rather
/// than misleading the user with "Mapping in progress".
class ModeTransitionTracker {
  ModeTransitionTracker._();
  static final ModeTransitionTracker instance = ModeTransitionTracker._();

  /// Target mode being transitioned to (e.g. 'idle' or 'navigation'), or null if settled.
  final ValueNotifier<String?> transitioningTo = ValueNotifier<String?>(null);
  Timer? _expireTimer;

  bool get isTransitioning => transitioningTo.value != null;
  bool get isStoppingMapping =>
      transitioningTo.value == 'idle' || transitioningTo.value == 'navigation';

  /// Call this when the user cancels or finishes mapping.
  void startStoppingMapping({
    String targetMode = 'idle',
    Duration duration = const Duration(seconds: 15),
  }) {
    transitioningTo.value = targetMode;
    _expireTimer?.cancel();
    _expireTimer = Timer(duration, () {
      transitioningTo.value = null;
    });
  }

  /// Call whenever fresh SDK state mode is received from /api/v1/state or /api/v1/mode.
  void onSdkModeUpdated(String? currentMode) {
    if (transitioningTo.value != null) {
      // If the robot's real mode has stopped being 'mapping', the transition is complete!
      if (currentMode != null && currentMode != 'mapping') {
        _expireTimer?.cancel();
        transitioningTo.value = null;
      }
    }
  }

  void clear() {
    _expireTimer?.cancel();
    transitioningTo.value = null;
  }
}
