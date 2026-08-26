import 'package:flutter/material.dart';

import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/action_feedback.dart';

/// The dock pin's own tap action on the map — "Go to Dock" (a plain nav
/// goal at the dock's pose, useful for parking near it without actually
/// docking), "Dock" (the real docking maneuver), or "Undock" — the same
/// three actions Teleop's own Dock/Undock control and Map View's Localize
/// menu expose, reached directly from the map instead.
Future<void> showDockActionSheet({
  required BuildContext context,
  required SdkApiService api,
  required ({double x, double y, double theta})? dockPose,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Dock',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
        if (dockPose != null)
          ListTile(
            leading:
                const Icon(Icons.navigation_rounded, color: AppColors.primary),
            title: const Text('Go to Dock'),
            subtitle: const Text("Navigate to the dock's position"),
            onTap: () => Navigator.of(sheetContext).pop('goto'),
          ),
        ListTile(
          leading: const Icon(Icons.ev_station_rounded,
              color: AppColors.stateDocking),
          title: const Text('Dock'),
          subtitle: const Text('Navigate to the dock and dock'),
          onTap: () => Navigator.of(sheetContext).pop('dock'),
        ),
        ListTile(
          leading:
              const Icon(Icons.logout_rounded, color: AppColors.textSecondary),
          title: const Text('Undock'),
          subtitle: const Text('Leave the dock'),
          onTap: () => Navigator.of(sheetContext).pop('undock'),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;

  String successMessage;
  Future<void> Function() action;
  switch (choice) {
    case 'goto':
      if (dockPose == null) return;
      action =
          () => api.goToPose(dockPose.x, dockPose.y, theta: dockPose.theta);
      successMessage = 'Heading to the dock position…';
    case 'dock':
      action = api.dock;
      successMessage = 'Heading to the dock…';
    case 'undock':
      action = api.undock;
      successMessage = 'Undocking…';
    default:
      return;
  }

  // The request only confirms the goal was *accepted* — briefly watch the
  // real outcome and report it, and automatically retry a real failure (up
  // to 3 attempts total, never on a timeout — that just means it's still in
  // progress), rather than leaving "Heading to…"/"Undocking…" as the last
  // word if it's aborted moments later.
  await retryOnFailure(
    context: context,
    actionLabel: choice == 'goto'
        ? 'Navigation'
        : choice == 'dock'
            ? 'Docking'
            : 'Undocking',
    attempt: (attemptNumber) async {
      try {
        await action();
      } on SdkApiException catch (e) {
        if (!context.mounted) return ActionOutcome.failed;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            e.isUnreachable
                ? "Needs navpro-sdk.service — it isn't reachable right now."
                : e.message,
          ),
        ));
        return ActionOutcome.failed;
      }
      if (!context.mounted) return ActionOutcome.timedOut;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(attemptNumber == 1
              ? successMessage
              : '$successMessage (attempt $attemptNumber)')));
      if (choice == 'goto') {
        return watchAndReportOutcome(
          context: context,
          fetchStatus: api.navigationStatus,
          isDone: (s) =>
              const {'succeeded', 'failed', 'canceled'}.contains(s['state']),
          isOk: (s) => s['state'] == 'succeeded',
          describe: (s) => s['state'] == 'succeeded'
              ? 'Reached the dock position.'
              : 'Could not reach the dock position'
                  '${s['message'] != null && (s['message'] as String).isNotEmpty ? ' — ${s['message']}' : '.'}',
        );
      }
      return watchAndReportOutcome(
        context: context,
        fetchStatus: api.dockStatus,
        isDone: (s) =>
            const {'docked', 'undocked', 'failed'}.contains(s['operation']),
        isOk: (s) => s['operation'] != 'failed',
        describe: (s) => s['operation'] == 'failed'
            ? 'Dock operation failed'
                '${s['message'] != null && (s['message'] as String).isNotEmpty ? ' — ${s['message']}' : '.'}'
            : s['operation'] == 'docked'
                ? 'Docked.'
                : 'Undocked.',
        timeout: const Duration(seconds: 60),
      );
    },
  );
}
