import 'package:flutter/foundation.dart';

import 'map_layers_store.dart';

/// Which optional map overlays can be shown — dock, saved locations, the
/// planner's current path, and both costmaps.
enum MapLayer { dock, locations, path, globalCostmap, localCostmap }

/// The single, app-wide "which overlays are visible" selection — shared by
/// every live map view (Map View, Teleop, Create Map, Dashboard's
/// preview), not scoped to whichever screen last opened the Layers panel.
/// Toggling a layer anywhere updates every currently-mounted map instance
/// immediately (they all listen to this same ValueNotifier) and persists
/// via [MapLayersStore] for next launch.
///
/// A plain module-level singleton rather than a Provider-scoped value is
/// deliberate, the same reasoning [NotLocalizedBanner]'s shared dismissal
/// flag uses: these map views appear across screens reached both via
/// AppShell's own IndexedStack tabs and via Navigator.push (Map View,
/// Create Map), so a provider scoped to one screen's subtree can't be the
/// single source of truth for all of them — that exact shape of bug
/// crashed Map View earlier this session (see main.dart's
/// MaterialApp.builder fix) before RobotTelemetryProvider was moved above
/// the Navigator; a static sidesteps the whole class of bug by
/// construction instead.
class MapLayersController extends ValueNotifier<Set<MapLayer>> {
  MapLayersController._() : super({MapLayer.dock, MapLayer.locations}) {
    _load();
  }

  static final instance = MapLayersController._();

  final _store = MapLayersStore();

  // Dock/locations on by default — the two lightweight, always-useful
  // layers. Both costmaps and the planned path start off: they're a lot
  // more visually busy, and only meaningful while navigation is actively
  // planning, so they're opt-in rather than on by default. Overwritten
  // below by whatever was saved from a previous session, if anything.
  Future<void> _load() async {
    final saved = await _store.load();
    if (saved == null) return;
    value = saved
        .map((name) => MapLayer.values.asNameMap()[name])
        .whereType<MapLayer>()
        .toSet();
  }

  bool contains(MapLayer layer) => value.contains(layer);

  void setVisible(MapLayer layer, bool visible) {
    final next = Set<MapLayer>.from(value);
    if (visible) {
      next.add(layer);
    } else {
      next.remove(layer);
    }
    value = next;
    _store.save(next.map((l) => l.name));
  }
}
