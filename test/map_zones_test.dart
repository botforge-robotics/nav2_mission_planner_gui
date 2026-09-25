import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nav2_mission_planner/models/map_zone.dart';
import 'package:nav2_mission_planner/providers/robot_telemetry_provider.dart';

void main() {
  group('MapZone Model Tests', () {
    test('createDefaultRectangle creates a 4-point rectangle centered on coordinates', () {
      final zone = MapZone.createDefaultRectangle(
        map: 'warehouse_map',
        center: const Offset(5.0, 10.0),
        width: 4.0,
        height: 2.0,
        type: ZoneType.restricted,
        name: 'Keep-Out Zone',
      );

      expect(zone.mapName, equals('warehouse_map'));
      expect(zone.name, equals('Keep-Out Zone'));
      expect(zone.type, equals(ZoneType.restricted));
      expect(zone.points.length, equals(4));

      // Check coordinates around center (5.0, 10.0) with half-width 2.0 and half-height 1.0
      expect(zone.points[0], equals(const Offset(3.0, 9.0)));
      expect(zone.points[1], equals(const Offset(7.0, 9.0)));
      expect(zone.points[2], equals(const Offset(7.0, 11.0)));
      expect(zone.points[3], equals(const Offset(3.0, 11.0)));
    });

    test('toJson and fromJson preserves all zone attributes including speed limit and color', () {
      final zone = MapZone(
        id: 'zone_speed_101',
        name: 'Forklift Slowdown Zone',
        type: ZoneType.speedLimit,
        speedLimitMps: 0.25,
        mapName: 'production_floor',
        customColor: const Color(0xFFFFA500),
        points: const [
          Offset(1.0, 2.0),
          Offset(4.0, 2.0),
          Offset(5.0, 4.0),
          Offset(3.0, 5.0),
          Offset(1.0, 4.0),
        ],
      );

      final json = zone.toJson();
      expect(json['id'], equals('zone_speed_101'));
      expect(json['name'], equals('Forklift Slowdown Zone'));
      expect(json['type'], equals('speed_limit'));
      expect(json['speed_limit_mps'], equals(0.25));
      expect(json['map'], equals('production_floor'));
      expect(json['points'], hasLength(5));

      final restored = MapZone.fromJson(json);
      expect(restored.id, equals(zone.id));
      expect(restored.name, equals(zone.name));
      expect(restored.type, equals(ZoneType.speedLimit));
      expect(restored.speedLimitMps, equals(0.25));
      expect(restored.points.length, equals(5));
      expect(restored.points[0], equals(const Offset(1.0, 2.0)));
      expect(restored.points[2], equals(const Offset(5.0, 4.0)));
    });

    test('contains() correctly classifies points inside and outside polygon', () {
      final zone = MapZone.createDefaultRectangle(
        map: 'map1',
        center: const Offset(0.0, 0.0),
        width: 4.0,
        height: 4.0,
      );

      // Points strictly inside [-2, 2] x [-2, 2]
      expect(zone.contains(const Offset(0.0, 0.0)), isTrue);
      expect(zone.contains(const Offset(1.0, 1.0)), isTrue);
      expect(zone.contains(const Offset(-1.5, 1.5)), isTrue);

      // Points strictly outside
      expect(zone.contains(const Offset(3.0, 0.0)), isFalse);
      expect(zone.contains(const Offset(0.0, 5.0)), isFalse);
      expect(zone.contains(const Offset(-10.0, -10.0)), isFalse);
    });

    test('centroid calculates geometric midpoint of polygon', () {
      final zone = MapZone(
        id: 'z1',
        name: 'Centroid Test',
        type: ZoneType.preferredLane,
        points: const [
          Offset(0.0, 0.0),
          Offset(10.0, 0.0),
          Offset(10.0, 10.0),
          Offset(0.0, 10.0),
        ],
      );

      expect(zone.centroid.dx, closeTo(5.0, 0.001));
      expect(zone.centroid.dy, closeTo(5.0, 0.001));
    });

    test('Node addition transforms rectangle into arbitrary polygon', () {
      final zone = MapZone.createDefaultRectangle(
        map: 'map1',
        center: const Offset(0, 0),
        width: 2.0,
        height: 2.0,
      );
      expect(zone.points.length, equals(4));

      // Insert node between point 0 and 1
      final pts = List<Offset>.from(zone.points);
      final midpoint = Offset(
        (pts[0].dx + pts[1].dx) / 2,
        (pts[0].dy + pts[1].dy) / 2,
      );
      pts.insert(1, midpoint);

      final polygonZone = zone.copyWith(points: pts);
      expect(polygonZone.points.length, equals(5));
      expect(polygonZone.points[1], equals(midpoint));
    });

    test('Edge projection math accurately computes closest point on segment for node insertion', () {
      final p1 = const Offset(0, 0);
      final p2 = const Offset(10, 0);
      final tap = const Offset(3.5, 2.0); // tapped slightly above the horizontal edge at x=3.5

      final seg = p2 - p1;
      final lenSq = seg.dx * seg.dx + seg.dy * seg.dy;
      final t = ((tap.dx - p1.dx) * seg.dx + (tap.dy - p1.dy) * seg.dy) / lenSq;
      final clampedT = t.clamp(0.05, 0.95);
      final projected = p1 + seg * clampedT;

      expect(projected.dx, closeTo(3.5, 0.001));
      expect(projected.dy, closeTo(0.0, 0.001));
      expect((projected - tap).distance, closeTo(2.0, 0.001));
    });

    test('createPreferredLane constructs a parallel corridor polygon from a line segment', () {
      final lane = MapZone.createPreferredLane(
        map: 'map1',
        start: const Offset(0, 0),
        end: const Offset(10, 0),
        width: 1.2,
        name: 'Main Aisle Lane',
      );

      expect(lane.name, equals('Main Aisle Lane'));
      expect(lane.type, equals(ZoneType.preferredLane));
      expect(lane.points.length, equals(4));

      // With horizontal start (0,0) -> end (10,0), perpendicular normal is (0, 1)
      // Half width is 0.6
      expect(lane.points[0], equals(const Offset(0.0, 0.6)));
      expect(lane.points[1], equals(const Offset(10.0, 0.6)));
      expect(lane.points[2], equals(const Offset(10.0, -0.6)));
      expect(lane.points[3], equals(const Offset(0.0, -0.6)));
    });

    test('createDefaultLane creates lane with specified center, length, width, and heading', () {
      final lane = MapZone.createDefaultLane(
        map: 'map1',
        center: const Offset(5, 5),
        length: 4.0,
        width: 1.2,
        heading: 0.0,
      );

      expect(lane.type, equals(ZoneType.preferredLane));
      expect(lane.points.length, equals(4));
      expect(lane.centroid.dx, closeTo(5.0, 0.001));
      expect(lane.centroid.dy, closeTo(5.0, 0.001));
    });

    test('createPolylineLane generates buffered corridor polygon across multiple turns', () {
      // Polyline making a 90-degree right turn: (0,0) -> (5,0) -> (5,5)
      final centerline = [
        const Offset(0, 0),
        const Offset(5, 0),
        const Offset(5, 5),
      ];

      final lane = MapZone.createPolylineLane(
        map: 'warehouse',
        centerline: centerline,
        width: 1.2,
        name: 'Turn Corridor',
      );

      expect(lane.name, equals('Turn Corridor'));
      expect(lane.isCorridorLane, isTrue);
      expect(lane.points.length, equals(6)); // 3 left + 3 right vertices
      expect(lane.laneCenterline.length, equals(3));
      expect(lane.laneWidth, closeTo(1.2, 0.01));

      // Test recovering centerline nodes
      expect(lane.laneCenterline[0].dx, closeTo(0, 0.01));
      expect(lane.laneCenterline[0].dy, closeTo(0, 0.01));
      expect(lane.laneCenterline[1].dx, closeTo(5, 0.01));
      expect(lane.laneCenterline[1].dy, closeTo(0, 0.01));
      expect(lane.laneCenterline[2].dx, closeTo(5, 0.01));
      expect(lane.laneCenterline[2].dy, closeTo(5, 0.01));
    });

    test('withLaneWidth dynamically adjusts corridor width while preserving turns', () {
      final centerline = [
        const Offset(0, 0),
        const Offset(5, 0),
        const Offset(5, 5),
      ];

      final lane = MapZone.createPolylineLane(
        map: 'warehouse',
        centerline: centerline,
        width: 1.0,
      );

      expect(lane.laneWidth, closeTo(1.0, 0.01));

      // Expand width to 2.0m
      final widerLane = lane.withLaneWidth(2.0);
      expect(widerLane.laneWidth, closeTo(2.0, 0.01));
      expect(widerLane.laneCenterline.length, equals(3));
      expect(widerLane.laneCenterline[1].dx, closeTo(5, 0.01));
      expect(widerLane.laneCenterline[1].dy, closeTo(0, 0.01));
    });

    test('withLaneCenterline allows inserting nodes between turns', () {
      final centerline = [
        const Offset(0, 0),
        const Offset(10, 0),
      ];

      final lane = MapZone.createPolylineLane(
        map: 'warehouse',
        centerline: centerline,
        width: 1.2,
      );
      expect(lane.laneCenterline.length, equals(2));

      // Insert midpoint turn node (5, 2)
      final newCenterline = [
        centerline[0],
        const Offset(5, 2),
        centerline[1],
      ];

      final turnedLane = lane.withLaneCenterline(newCenterline);
      expect(turnedLane.laneCenterline.length, equals(3));
      expect(turnedLane.points.length, equals(6));
      expect(turnedLane.laneCenterline[1], equals(const Offset(5, 2)));
      expect(turnedLane.laneWidth, closeTo(1.2, 0.01));
    });
  });

  group('RobotTelemetryProvider System Metrics Tests', () {
    test('updates and formats CPU load and temperatures correctly', () {
      final telemetry = RobotTelemetryProvider();
      expect(telemetry.cpuLoad, isNull);
      expect(telemetry.cpuTemperature, isNull);
      expect(telemetry.batteryTemperature, isNull);

      telemetry.updateSystemMetrics(
        cpuLoadPct: 34.5,
        cpuTempC: 58.2,
        batteryTempC: 31.0,
      );

      expect(telemetry.cpuLoad, equals(34.5));
      expect(telemetry.cpuTemperature, equals(58.2));
      expect(telemetry.batteryTemperature, equals(31.0));
    });
  });
}
