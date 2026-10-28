import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';

import '../../providers/robot_telemetry_provider.dart';
import '../../services/locations_controller.dart';
import '../../services/route_estimate_service.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/action_feedback.dart';

/// The "pick a location → see distance/time → confirm → go" flow shared by
/// Teleop's quick-nav list and Map View's location pins — one shared sheet
/// so both entry points behave identically rather than growing two
/// slightly-different confirmation UIs. Shows the real, planner-computed
/// route distance/ETA when it can (via [RouteEstimateService]), falling
/// back to an honest straight-line distance (clearly labeled as such) when
/// the route can't be computed — not localized yet, goal unreachable, or
/// the planner call times out — since none of those should block sending
/// the goal, only the estimate shown alongside it.
Future<void> showGoToConfirmSheet({
  required BuildContext context,
  required Ros2 ros2,
  required SdkApiService api,
  required String locationName,
  required double targetX,
  required double targetY,
  double? currentX,
  double? currentY,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _GoToConfirmSheet(
      callerContext: context,
      ros2: ros2,
      api: api,
      locationName: locationName,
      targetX: targetX,
      targetY: targetY,
      currentX: currentX,
      currentY: currentY,
    ),
  );
}

class _GoToConfirmSheet extends StatefulWidget {
  const _GoToConfirmSheet({
    required this.callerContext,
    required this.ros2,
    required this.api,
    required this.locationName,
    required this.targetX,
    required this.targetY,
    required this.currentX,
    required this.currentY,
  });

  /// The screen's own context (Teleop, Map View, …) that opened this sheet
  /// — used to show the post-send outcome snackbar, since this widget's own
  /// `context` stops being mounted the instant `_send` pops the sheet.
  final BuildContext callerContext;
  final Ros2 ros2;
  final SdkApiService api;
  final String locationName;
  final double targetX;
  final double targetY;
  final double? currentX;
  final double? currentY;

  @override
  State<_GoToConfirmSheet> createState() => _GoToConfirmSheetState();
}

class _GoToConfirmSheetState extends State<_GoToConfirmSheet> {
  bool _computing = true;
  RouteEstimate? _estimate;
  bool _sending = false;
  String? _sendError;
  String _routingMode = 'free_space';
  String _reroutePolicy = 'wait_then_reroute';

  double? get _straightLineMeters {
    final x = widget.currentX, y = widget.currentY;
    if (x == null || y == null) return null;
    return sqrt(pow(widget.targetX - x, 2) + pow(widget.targetY - y, 2));
  }

  @override
  void initState() {
    super.initState();
    if (widget.currentX != null && widget.currentY != null) {
      _computeRoute();
    } else {
      _computing = false;
    }
  }

  Future<void> _computeRoute() async {
    final estimate = await RouteEstimateService(widget.ros2).estimate(
      fromX: widget.currentX!,
      fromY: widget.currentY!,
      toX: widget.targetX,
      toY: widget.targetY,
    );
    if (!mounted) return;
    setState(() {
      _estimate = estimate;
      _computing = false;
    });
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await widget.api.goToWaypoint(
        widget.locationName,
        replace: true,
        routingMode: _routingMode,
        reroutePolicy: _reroutePolicy,
      );
    } on SdkApiException catch (e) {
      // If the robot accepted the goal and started moving despite an HTTP timeout or transient error, proceed.
      bool activated = false;
      try {
        final status = await widget.api.navigationStatus();
        final dockStatus = await widget.api.dockStatus();
        final navState = status['state'] as String?;
        final dockOp = dockStatus['operation'] as String?;
        if (navState == 'active' ||
            dockOp == 'undocking' ||
            dockOp == 'navigating' ||
            dockOp == 'staging') {
          activated = true;
        }
      } catch (_) {}

      if (!activated) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _sendError = e.isUnreachable
              ? "Navigation needs navpro-sdk.service — it isn't reachable right now."
              : e.message;
        });
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    final caller = widget.callerContext;
    if (!caller.mounted) return;
    ScaffoldMessenger.of(caller).showSnackBar(
        SnackBar(content: Text('Heading to "${widget.locationName}"…')));
    // The request above only confirms the goal was *accepted* — briefly
    // watch the real outcome too, and retry a real failure automatically
    // (never a timeout — that just means the leg is still in progress),
    // rather than leaving "Heading to…" as the last word if Nav2 aborts the
    // goal moments later (a real, observed case: a goal can fail minutes in
    // with nothing in the app ever saying so).
    await retryOnFailure(
      context: caller,
      actionLabel: 'Navigation',
      attempt: (attemptNumber) async {
        if (attemptNumber > 1) {
          try {
            await widget.api.goToWaypoint(
              widget.locationName,
              replace: true,
              routingMode: _routingMode,
              reroutePolicy: _reroutePolicy,
            );
          } on SdkApiException catch (e) {
            if (!caller.mounted) return ActionOutcome.failed;
            ScaffoldMessenger.of(caller).showSnackBar(SnackBar(
              content: Text(e.isUnreachable
                  ? "Navigation needs navpro-sdk.service — it isn't reachable right now."
                  : e.message),
            ));
            return ActionOutcome.failed;
          }
        }
        if (!caller.mounted) return ActionOutcome.failed;
        return watchAndReportOutcome(
          context: caller,
          actionLabel: 'Navigation to "${widget.locationName}"',
          fetchStatus: widget.api.navigationStatus,
          isDone: (s) =>
              const {'succeeded', 'failed', 'canceled'}.contains(s['state']),
          isOk: (s) => s['state'] == 'succeeded',
          describe: (s) => s['state'] == 'succeeded'
              ? 'Reached "${widget.locationName}".'
              : 'Could not reach "${widget.locationName}"'
                  '${s['message'] != null && (s['message'] as String).isNotEmpty ? ' — ${s['message']}' : '.'}',
        );
      },
    );
    if (caller.mounted) {
      try {
        caller.read<RobotTelemetryProvider>().clearPath();
      } catch (_) {}
    }
    if (!mounted) return;
  }

  String _formatEta(double seconds) {
    if (seconds < 60) return '~${seconds.round()}s';
    final minutes = seconds / 60;
    return '~${minutes.toStringAsFixed(minutes < 10 ? 1 : 0)} min';
  }

  Widget _distanceLine(AppColorsTheme colors) {
    final straightLine = _straightLineMeters;
    if (straightLine == null) {
      return Text(
        "Position not localized yet — sending will still work, "
        "there's just no distance estimate to show.",
        style: TextStyle(color: colors.textSecondary),
      );
    }
    final estimate = _estimate;
    if (_computing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('≈ ${straightLine.toStringAsFixed(1)} m straight-line',
              style: TextStyle(color: colors.textSecondary)),
          const SizedBox(width: AppSpacing.sm),
          const SizedBox(
              height: 12,
              width: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5)),
          const SizedBox(width: AppSpacing.xs),
          Text('calculating route…',
              style: TextStyle(color: colors.textSecondary, fontSize: 12)),
        ],
      );
    }
    if (estimate != null) {
      return Text(
        '${estimate.distanceMeters.toStringAsFixed(1)} m route · '
        '${_formatEta(estimate.etaSeconds)}',
        style: TextStyle(fontWeight: FontWeight.w600, color: colors.textPrimary),
      );
    }
    return Text(
      "≈ ${straightLine.toStringAsFixed(1)} m straight-line "
      "(couldn't compute a route)",
      style: TextStyle(color: colors.textSecondary),
    );
  }

  Future<void> _deleteLocation() async {
    final name = widget.locationName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Location'),
        content: Text('Are you sure you want to remove "$name" from this map?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.deleteWaypoint(name);
      if (!mounted) return;
      Navigator.of(context).pop();
      final caller = widget.callerContext;
      if (caller.mounted) {
        ScaffoldMessenger.of(caller).showSnackBar(
          SnackBar(content: Text('Location "$name" deleted')),
        );
      }
      await LocationsController.instance.refresh(widget.api);
    } catch (e) {
      if (mounted) {
        setState(() => _sendError = 'Failed to delete location: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Go to "${widget.locationName}"?',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: colors.textPrimary)),
              ),
              if (widget.locationName.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger, size: 20),
                  tooltip: 'Delete location from map',
                  onPressed: _sending ? null : _deleteLocation,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _distanceLine(colors),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Routing Mode',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary)),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'free_space',
                          label: Text(
                            'Free Space',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _routingMode == 'free_space'
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                          ),
                          icon: Icon(
                            Icons.explore_outlined,
                            size: 14,
                            color: _routingMode == 'free_space'
                                ? colors.primary
                                : colors.textSecondary,
                          ),
                        ),
                        ButtonSegment(
                          value: 'road_network',
                          label: Text(
                            'Road Network',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _routingMode == 'road_network'
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                          ),
                          icon: Icon(
                            Icons.alt_route_rounded,
                            size: 14,
                            color: _routingMode == 'road_network'
                                ? colors.primary
                                : colors.textSecondary,
                          ),
                        ),
                      ],
                      selected: {_routingMode},
                      onSelectionChanged: (set) => setState(() => _routingMode = set.first),
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return colors.primary.withValues(alpha: 0.18);
                          }
                          return colors.surface;
                        }),
                        side: WidgetStateProperty.all(BorderSide(color: colors.border)),
                      ),
                    ),
                  ],
                ),
                if (_routingMode == 'road_network') ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Blockage Policy:',
                          style: TextStyle(fontSize: 11, color: colors.textSecondary)),
                      DropdownButton<String>(
                        value: _reroutePolicy,
                        isDense: true,
                        dropdownColor: colors.surface,
                        iconEnabledColor: colors.primary,
                        underline: const SizedBox(),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary),
                        items: [
                          DropdownMenuItem(
                            value: 'wait_then_reroute',
                            child: Text('Wait 5s & Detour',
                                style: TextStyle(color: colors.textPrimary)),
                          ),
                          DropdownMenuItem(
                            value: 'immediate',
                            child: Text('Immediate Detour',
                                style: TextStyle(color: colors.textPrimary)),
                          ),
                          DropdownMenuItem(
                            value: 'halt_only',
                            child: Text('Halt & Wait Only',
                                style: TextStyle(color: colors.textPrimary)),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _reroutePolicy = val);
                        },
                      ),
                    ],
                  ),
                  Text(
                    _reroutePolicy == 'wait_then_reroute'
                        ? 'Pauses up to 5s for passing people; if blocked, reroutes via graph.'
                        : _reroutePolicy == 'immediate'
                            ? 'Immediately detours onto alternate road when obstacle is detected.'
                            : 'Stops and waits for road to clear without taking detours.',
                    style: TextStyle(fontSize: 10, color: colors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          if (_sendError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_sendError!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _sending ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.textOnPrimary),
                        )
                      : const Text('Go'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
