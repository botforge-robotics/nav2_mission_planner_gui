import 'package:flutter/material.dart';

import '../services/sdk_api_service.dart';

/// Fetches and parses the robot's known dock pose from the SDK. Returns
/// null if none is known yet or the SDK isn't reachable — callers treat
/// that as "nothing to show/use" rather than surfacing an error, since a
/// robot that's never docked genuinely has no dock pose yet.
Future<({double x, double y, double theta})?> fetchDockPose(
    SdkApiService api) async {
  try {
    final resp = await api.dockPose();
    final data = resp['data'] as Map<String, dynamic>?;
    if (data == null) return null;
    return (
      x: (data['x'] as num).toDouble(),
      y: (data['y'] as num).toDouble(),
      theta: (data['theta'] as num?)?.toDouble() ?? 0,
    );
  } on SdkApiException {
    return null;
  }
}

/// Reads the robot's saved dock pose and seeds AMCL's belief with it — the
/// "Robot at Dock" localize option, shared by Map View's own Localize
/// button and [NotLocalizedBanner]'s dock-confirm flow rather than
/// duplicated between them. Reports success/failure via a SnackBar itself
/// (both call sites want the same feedback), and returns whether it
/// succeeded so callers can react (e.g. dismiss a banner only on success).
Future<bool> localizeAtDock({
  required BuildContext context,
  required SdkApiService api,
}) async {
  final dock = await fetchDockPose(api);
  if (dock == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No dock pose is known yet.')));
    }
    return false;
  }
  try {
    await api.localize(dock.x, dock.y, theta: dock.theta);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Localized to the dock position.')));
    }
    return true;
  } on SdkApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          e.isUnreachable
              ? "Localizing needs navpro-sdk.service — it isn't reachable right now."
              : e.message,
        ),
      ));
    }
    return false;
  }
}
