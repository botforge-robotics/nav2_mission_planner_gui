import 'package:shared_preferences/shared_preferences.dart';

/// Persists Map View's Layers panel selection across app sessions —
/// requested explicitly ("remember layer toggles for further session")
/// rather than resetting to the dock/locations default every time the
/// screen reopens. Same minimal SharedPreferences-store shape as
/// [RobotConnectionStore]: stores each layer's name (matching
/// [_Layer.values.byName] on the read side), not an int/bitmask, so adding a
/// new layer later can't shift the meaning of an old saved value.
class MapLayersStore {
  static const _key = 'map_view_layers';

  Future<Set<String>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_key);
    return saved?.toSet();
  }

  Future<void> save(Iterable<String> layerNames) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, layerNames.toList());
  }
}
