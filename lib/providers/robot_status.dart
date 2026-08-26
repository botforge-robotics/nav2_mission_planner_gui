import 'package:flutter/material.dart';

import '../services/sdk_state_service.dart';
import '../theme/app_theme.dart';
import 'robot_telemetry_provider.dart';

/// The robot's status as a person would describe it — not the raw ROS
/// operating mode (idle/mapping/navigation) or lifecycle state, which are
/// implementation concepts. Derived from signals that already exist
/// (telemetry + the SDK's optional state enrichment), no new subscriptions,
/// same reasoning the app's original robot_state.dart used: one consistent
/// precedence order over existing signals rather than each screen deriving
/// its own notion of "what is the robot doing".
enum RobotStatus { idle, charging, charged, moving, mapping, missionInProgress }

/// Above this, the robot counts as "moving" rather than "idle" — odometry
/// noise at a dead stop is rarely exactly zero.
const double _movingThresholdMps = 0.02;

RobotStatus deriveRobotStatus({
  required RobotTelemetryProvider telemetry,
  required SdkState sdkState,
}) {
  if (sdkState.missionStatus == 'running' ||
      sdkState.missionStatus == 'paused') {
    return RobotStatus.missionInProgress;
  }
  if (sdkState.mode == 'mapping') return RobotStatus.mapping;
  if (telemetry.chargeStatus == ChargeStatus.charging)
    return RobotStatus.charging;
  if (telemetry.chargeStatus == ChargeStatus.full) return RobotStatus.charged;
  final speed = telemetry.linearSpeedMps;
  if (speed != null && speed.abs() > _movingThresholdMps)
    return RobotStatus.moving;
  return RobotStatus.idle;
}

extension RobotStatusStyle on RobotStatus {
  String get label => switch (this) {
        RobotStatus.idle => 'IDLE',
        RobotStatus.charging => 'CHARGING',
        RobotStatus.charged => 'CHARGED',
        RobotStatus.moving => 'MOVING',
        RobotStatus.mapping => 'MAPPING',
        RobotStatus.missionInProgress => 'MISSION IN PROGRESS',
      };

  // Reuses AppColors' own robot-state legend rather than a second palette —
  // not a perfect 1:1 (that legend was built for offline/idle/localizing/
  // executing/teleop/docking/fault/e-stopped), so a couple of these are the
  // closest reasonable semantic fit, not a literal named match.
  Color get color => switch (this) {
        RobotStatus.idle => AppColors.stateIdle,
        RobotStatus.charging => AppColors.stateDocking,
        RobotStatus.charged => AppColors.stateCharging,
        RobotStatus.moving => AppColors.stateExecuting,
        RobotStatus.mapping => AppColors.stateTeleop,
        RobotStatus.missionInProgress => AppColors.stateExecuting,
      };
}
