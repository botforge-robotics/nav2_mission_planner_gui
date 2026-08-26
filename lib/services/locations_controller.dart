import 'package:flutter/foundation.dart';

import 'sdk_api_service.dart';

/// Saved locations, shared live across every mounted screen — mirrors
/// [MapLayersController]'s own shape/reasoning (see that file). Before this,
/// every screen that shows locations (Locations list, Teleop's live map,
/// Map View, the Mission editor) fetched its own private copy once on
/// mount; adding a location on one screen (or one device) never reached any
/// other already-open screen until it happened to remount and re-fetch —
/// reported directly: a location added from the PC app didn't show up on a
/// phone connected to the same robot without restarting it.
///
/// A single shared [ValueNotifier] fixes both cases at once: every screen
/// listening via [ValueListenableBuilder] rebuilds the instant [refresh]
/// updates the value, and [refresh] is called both on each screen's own
/// load *and* right after Add/Delete Location succeeds — so the screen that
/// made the change sees it applied everywhere it's visible, not just in
/// its own local state.
class LocationsController extends ValueNotifier<List<Map<String, dynamic>>?> {
  LocationsController._() : super(null);

  static final instance = LocationsController._();

  /// Fetches the current list from the SDK and publishes it. Best-effort on
  /// failure — keeps whatever was last known rather than clearing it, since
  /// a transient SDK hiccup shouldn't blank out every location pin on
  /// screen; callers that need to show their own error state should catch
  /// [SdkApiException] from their own separate call instead of relying on
  /// this one.
  Future<void> refresh(SdkApiService api) async {
    try {
      value = await api.listWaypoints();
    } on SdkApiException {
      // Keep the last known value — see doc above.
    }
  }
}
