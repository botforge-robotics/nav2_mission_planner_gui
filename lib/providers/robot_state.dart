import 'package:flutter/widgets.dart' show Color;
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/services/docking_service.dart';
import 'package:nav2_mission_planner/services/launch_service.dart';
import 'package:nav2_mission_planner/services/mission_execution_service.dart';
import 'package:nav2_mission_planner/theme/app_colors.dart';

/// The robot-state legend from the redesign reference — one enum, one
/// derivation function, reused by every status chip (Dashboard, Robot
/// Status, Alerts, nav-rail badges) instead of each consumer re-deriving
/// its own notion of "what is the robot doing" ad hoc. See
/// `AppStatusColors` (lib/theme/app_colors.dart) for the color each state
/// maps to.
///
/// [fault] and [eStopped] exist for legend completeness only — no
/// diagnostics/fault or E-STOP signal is subscribed anywhere in this app
/// today, so [deriveRobotState] never returns them. Wiring those up is new
/// ROS integration, not something this derivation can infer.
enum RobotState {
  offline,
  idle,
  localizing,
  executing,
  teleop,
  docking,
  charging,
  fault,
  eStopped,
}

/// Computes the current [RobotState] from the existing services that each
/// already track their own slice of it — no new ROS subscriptions, just one
/// consistent precedence order over signals that already exist:
/// [ConnectionProvider] (offline), [DockingService] (docking/charging),
/// [MissionExecutionService] (executing), [LaunchManager] + [poseReceived]
/// (localizing — an approximation, see below), and [teleopActive].
///
/// Precedence (highest first) matches what's most useful to surface when
/// more than one is true at once — e.g. a mission that involves docking
/// should still read as "docking", not "executing".
RobotState deriveRobotState({
  required ConnectionProvider connection,
  required LaunchManager launchManager,
  required MissionExecutionService missionExecution,
  required DockingService docking,
  required bool poseReceived,
  required bool teleopActive,
}) {
  if (!connection.isConnected) return RobotState.offline;
  if (docking.isBusy) return RobotState.docking;
  if (docking.isDocked) return RobotState.charging;
  if (teleopActive) return RobotState.teleop;
  if (missionExecution.isRunning) return RobotState.executing;
  // Approximation only: no AMCL covariance/confidence is read anywhere in
  // this app today, so "localizing" here just means "a navigation session
  // is up but no pose has arrived yet" — coarser than a true localization-
  // quality signal. Present it as such in the UI, not as a precise
  // "localizing: NN% confidence" readout.
  if (launchManager.activeSession == SessionType.navigation && !poseReceived) {
    return RobotState.localizing;
  }
  return RobotState.idle;
}

/// Maps a [RobotState] onto its legend color (see [AppStatusColors]) — one
/// place, reused by every status pill/chip instead of each screen
/// re-deriving its own switch, the same duplication risk this whole token
/// set exists to avoid.
Color robotStateColor(RobotState state, AppStatusColors colors) =>
    switch (state) {
      RobotState.offline => colors.offline,
      RobotState.idle => colors.idle,
      RobotState.localizing => colors.localizing,
      RobotState.executing => colors.executing,
      RobotState.teleop => colors.teleop,
      RobotState.docking => colors.docking,
      RobotState.charging => colors.charging,
      RobotState.fault => colors.fault,
      RobotState.eStopped => colors.eStopped,
    };

/// Human-readable label for a [RobotState], reused the same way as
/// [robotStateColor].
String robotStateLabel(RobotState state) => switch (state) {
      RobotState.offline => 'Offline',
      RobotState.idle => 'Idle',
      RobotState.localizing => 'Localizing',
      RobotState.executing => 'Executing',
      RobotState.teleop => 'Teleop',
      RobotState.docking => 'Docking',
      RobotState.charging => 'Charging',
      RobotState.fault => 'Fault',
      RobotState.eStopped => 'E-Stopped',
    };
