import 'package:flutter/foundation.dart';

import '../models/road_network.dart';
import 'sdk_api_service.dart';

/// Central state controller for Road Network topology (Nodes, Edges, Speed Limits),
/// synchronizing with the robot's SQLite central store as the single source of truth.
class RoadNetworkController extends ValueNotifier<RoadNetwork?> {
  RoadNetworkController._() : super(null);

  static final instance = RoadNetworkController._();

  String? _currentMap;
  String? get currentMap => _currentMap;

  /// Fetches road network for [map] (or currently loaded map if null) from robot SDK.
  Future<void> refresh(SdkApiService api, {String? map}) async {
    try {
      final targetMap = map ?? await api.getCurrentMap() ?? 'default';
      _currentMap = targetMap;
      final resp = await api.getRoadNetwork(mapName: targetMap);
      final geoJson = resp['geojson'] as Map<String, dynamic>?;
      if (geoJson != null) {
        value = RoadNetwork.fromGeoJson(targetMap, geoJson);
      } else {
        value = RoadNetwork(mapName: targetMap);
      }
    } catch (_) {
      // Retain last known state on network glitch
    }
  }

  /// Saves or updates the road network on the robot for the specified map.
  Future<bool> saveRoadNetwork(
    SdkApiService api,
    RoadNetwork network, {
    String? map,
  }) async {
    try {
      final targetMap = (map != null && map.isNotEmpty)
          ? map
          : (network.mapName.isNotEmpty ? network.mapName : (_currentMap ?? 'default'));
      final geoJson = network.toGeoJson();
      await api.saveRoadNetwork(geoJson, mapName: targetMap);
      value = network.copyWith(mapName: targetMap);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes the road network for the specified map from robot central storage.
  Future<bool> deleteRoadNetwork(SdkApiService api, {String? map}) async {
    try {
      final targetMap = map ?? _currentMap ?? 'default';
      await api.deleteRoadNetwork(mapName: targetMap);
      value = RoadNetwork(mapName: targetMap);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Manually triggers immediate road rerouting via RouteServer.
  Future<bool> triggerReroute(SdkApiService api) async {
    try {
      final resp = await api.triggerRoadReroute();
      return resp['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
