import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The real result of a watched dock/undock/goto attempt — [timedOut] is
/// deliberately distinct from [failed]: a timeout means the operation may
/// still genuinely be running (a long leg, a slow dock approach), so
/// [retryOnFailure] never resends on it — only on a definite, Nav2-reported
/// failure.
enum ActionOutcome { succeeded, failed, timedOut }

/// Briefly polls a status endpoint after firing a dock/undock/navigate
/// request and reports the *real* outcome — success or failure — via a
/// snackbar, instead of leaving the caller's own "Heading to…"/"Docking…"
/// snackbar as the last word.
///
/// Every dock/undock/goto call in this app returns as soon as the goal is
/// *accepted* (see navpromini_sdk's own docs), not when it finishes — a
/// docking maneuver or a cross-room drive takes tens of seconds to minutes.
/// Without this, a goal that's accepted and then aborted by Nav2 minutes
/// later (an obstacle, an unreachable pose) reads as the whole feature
/// having silently done nothing — the app never says another word about it.
/// Confirmed via the SDK's own /navigation/status: a real aborted goal from
/// a prior attempt was sitting there with no UI ever having surfaced it.
///
/// Deliberately short and best-effort: if the operation is still running
/// when [timeout] elapses (normal for a long leg), this stays silent rather
/// than wrongly reporting a failure — a caller that wants to keep watching
/// longer (Missions' own detail screen) already has its own polling loop
/// for that.
///
/// Returns the real [ActionOutcome] so callers (see [retryOnFailure]) can
/// act on it, not just display it.
Future<ActionOutcome> watchAndReportOutcome({
  required BuildContext context,
  required Future<Map<String, dynamic>> Function() fetchStatus,
  required bool Function(Map<String, dynamic> status) isDone,
  required bool Function(Map<String, dynamic> status) isOk,
  required String Function(Map<String, dynamic> status) describe,
  Duration interval = const Duration(seconds: 1),
  Duration timeout = const Duration(seconds: 20),
  bool showResult = true,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future.delayed(interval);
    Map<String, dynamic> status;
    try {
      status = await fetchStatus();
    } catch (_) {
      continue; // Transient poll failure — keep trying within the window.
    }
    if (!isDone(status)) continue;
    final ok = isOk(status);
    if (showResult && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(describe(status)),
        backgroundColor: ok ? null : AppColors.danger,
      ));
    }
    return ok ? ActionOutcome.succeeded : ActionOutcome.failed;
  }
  return ActionOutcome.timedOut;
}

/// Automatically retries a dock/undock/goto [attempt] up to [maxAttempts]
/// times total, but only on a definite [ActionOutcome.failed] — never on a
/// timeout, since the operation may genuinely still be in progress and
/// resending would double-fire it (a real risk: two overlapping dock goals
/// fighting each other).
///
/// Between attempts, shows a snackbar with a real "Cancel" action — tapping
/// it stops any further retries, satisfying "retry unless the user cancels"
/// honestly rather than silently taking control away from them. There's a
/// short pause after each failure specifically to give that Cancel action a
/// real window to be tapped before the next attempt fires.
///
/// [attempt] owns sending the request and watching its outcome for one try
/// — including catching its own [SdkApiException]-style errors, since a
/// send failure (robot briefly unreachable mid-retry) is just as retryable
/// here as a Nav2-reported failure.
Future<void> retryOnFailure({
  required BuildContext context,
  required Future<ActionOutcome> Function(int attemptNumber) attempt,
  required String actionLabel,
  int maxAttempts = 3,
}) async {
  var cancelled = false;
  for (var i = 1; i <= maxAttempts; i++) {
    if (cancelled) return;
    final outcome = await attempt(i);
    if (outcome != ActionOutcome.failed) return;
    if (i == maxAttempts || cancelled) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$actionLabel failed — retrying (${i + 1}/$maxAttempts)…'),
      backgroundColor: AppColors.danger,
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'Cancel',
        textColor: AppColors.textOnPrimary,
        onPressed: () => cancelled = true,
      ),
    ));
    // Gives the Cancel action above a real window to land before the next
    // attempt fires — retrying instantly would make it un-tappable in
    // practice.
    await Future.delayed(const Duration(seconds: 3));
  }
}
