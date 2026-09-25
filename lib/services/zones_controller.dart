import 'package:flutter/foundation.dart';

import '../models/map_zone.dart';
import 'sdk_api_service.dart';

/// Central state controller for map zones (Restricted, Speed Limits, Preferred Lanes, Work Zones),
/// synchronizing with the robot's persistent storage as the single source of truth.
class ZonesController extends ValueNotifier<List<MapZone>> {
  ZonesController._() : super(const []);

  static final instance = ZonesController._();

  String? _currentMap;
  String? get currentMap => _currentMap;

  /// Fetches zones for [map] (or currently loaded map if null) from the robot SDK.
  Future<void> refresh(SdkApiService api, {String? map}) async {
    try {
      final targetMap = map ?? await api.getCurrentMap() ?? 'default';
      _currentMap = targetMap;
      final rawList = await api.listZones(map: targetMap);
      value = rawList.map((e) => MapZone.fromJson(e)).toList();
    } catch (_) {
      // Retain last known zones on network glitch
    }
  }

  /// Saves or updates a zone on the robot for the specified map.
  Future<bool> saveZone(SdkApiService api, MapZone zone, {String? map}) async {
    try {
      final targetMap = map ?? zone.mapName ?? _currentMap ?? 'default';
      final zoneData = zone.toJson();
      zoneData['map'] = targetMap;
      await api.saveZone(zoneData, map: targetMap);
      await refresh(api, map: targetMap);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes a zone by [zoneId] from the robot for the specified map.
  Future<bool> deleteZone(SdkApiService api, String zoneId, {String? map}) async {
    try {
      final targetMap = map ?? _currentMap ?? 'default';
      await api.deleteZone(zoneId, map: targetMap);
      await refresh(api, map: targetMap);
      return true;
    } catch (_) {
      return false;
    }
  }
}
