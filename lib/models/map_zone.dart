import 'dart:math';
import 'package:flutter/material.dart';

enum ZoneType {
  restricted,
  speedLimit,
  preferredLane,
  workZone;

  String get key => switch (this) {
        ZoneType.restricted => 'restricted',
        ZoneType.speedLimit => 'speed_limit',
        ZoneType.preferredLane => 'preferred_lane',
        ZoneType.workZone => 'work_zone',
      };

  String get label => switch (this) {
        ZoneType.restricted => 'Restricted (Keep-Out)',
        ZoneType.speedLimit => 'Speed Limit Zone',
        ZoneType.preferredLane => 'Preferred Lane',
        ZoneType.workZone => 'Work / Caution Zone',
      };

  Color get defaultColor => switch (this) {
        ZoneType.restricted => const Color(0xFFEF4444),
        ZoneType.speedLimit => const Color(0xFFF59E0B),
        ZoneType.preferredLane => const Color(0xFF3B82F6),
        ZoneType.workZone => const Color(0xFF8B5CF6),
      };

  String get description => switch (this) {
        ZoneType.restricted =>
          'Keep-out area. Nav2 marks this entire polygon as an impassable obstacle where the robot is forbidden to navigate or enter.',
        ZoneType.speedLimit =>
          'Speed throttling area. Caps the robot\'s maximum linear speed inside this polygon (default 0.08 m/s for safe maneuvering).',
        ZoneType.preferredLane =>
          'Preferred navigation lane. The route planner assigns lower traversal cost to guide the robot along designated tracks.',
        ZoneType.workZone =>
          'Active work / caution zone. Robot operates with increased obstacle clearance and heightened vigilance around temporary activity.',
      };

  IconData get icon => switch (this) {
        ZoneType.restricted => Icons.block_rounded,
        ZoneType.speedLimit => Icons.speed_rounded,
        ZoneType.preferredLane => Icons.alt_route_rounded,
        ZoneType.workZone => Icons.construction_rounded,
      };

  static ZoneType fromKey(String? key) => switch (key) {
        'speed_limit' => ZoneType.speedLimit,
        'preferred_lane' => ZoneType.preferredLane,
        'work_zone' || 'caution' => ZoneType.workZone,
        _ => ZoneType.restricted,
      };
}

class MapZone {
  const MapZone({
    required this.id,
    required this.name,
    required this.type,
    required this.points,
    this.speedLimitMps,
    this.customColor,
    this.mapName,
  });

  final String id;
  final String name;
  final ZoneType type;
  final List<Offset> points;
  final double? speedLimitMps;
  final Color? customColor;
  final String? mapName;

  Color get color => customColor ?? type.defaultColor;
  IconData get icon => type.icon;
  String get typeLabel => type.label;

  MapZone copyWith({
    String? id,
    String? name,
    ZoneType? type,
    List<Offset>? points,
    double? speedLimitMps,
    Color? customColor,
    String? mapName,
  }) {
    return MapZone(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      points: points ?? List.of(this.points),
      speedLimitMps: speedLimitMps ?? this.speedLimitMps,
      customColor: customColor ?? this.customColor,
      mapName: mapName ?? this.mapName,
    );
  }

  /// Calculates geometric centroid of polygon for label placement.
  Offset get centroid {
    if (points.isEmpty) return Offset.zero;
    double sumX = 0;
    double sumY = 0;
    for (final p in points) {
      sumX += p.dx;
      sumY += p.dy;
    }
    return Offset(sumX / points.length, sumY / points.length);
  }

  /// Ray-casting point-in-polygon test.
  bool contains(Offset test) {
    if (points.length < 3) return false;
    bool inside = false;
    int j = points.length - 1;
    for (int i = 0; i < points.length; i++) {
      final pi = points[i];
      final pj = points[j];
      if ((pi.dy > test.dy) != (pj.dy > test.dy) &&
          test.dx < (pj.dx - pi.dx) * (test.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  factory MapZone.createDefaultRectangle({
    required String map,
    required Offset center,
    double width = 2.0,
    double height = 2.0,
    ZoneType type = ZoneType.restricted,
    String? name,
    double? speedLimitMps,
  }) {
    final hw = width / 2;
    final hh = height / 2;
    final id = 'zone_${DateTime.now().millisecondsSinceEpoch}';
    final defaultName = name ??
        switch (type) {
          ZoneType.restricted => 'Restricted Zone',
          ZoneType.speedLimit => 'Speed Limit Zone',
          ZoneType.preferredLane => 'Preferred Lane',
          ZoneType.workZone => 'Caution Zone',
        };

    return MapZone(
      id: id,
      name: defaultName,
      type: type,
      mapName: map,
      speedLimitMps: speedLimitMps ?? (type == ZoneType.speedLimit ? 0.08 : null),
      points: [
        Offset(center.dx - hw, center.dy - hh),
        Offset(center.dx + hw, center.dy - hh),
        Offset(center.dx + hw, center.dy + hh),
        Offset(center.dx - hw, center.dy + hh),
      ],
    );
  }

  /// Buffers an arbitrary polyline [centerline] of 2 or more points into a corridor polygon
  /// of width [width] (half-width = width / 2).
  static List<Offset> bufferPolyline(List<Offset> centerline, double width) {
    if (centerline.length < 2) return [];
    final halfWidth = width / 2;
    final n = centerline.length;

    // Segment directions and left normal vectors
    final List<Offset> segNormals = [];
    for (int i = 0; i < n - 1; i++) {
      final d = centerline[i + 1] - centerline[i];
      final len = d.distance;
      if (len > 0.0001) {
        segNormals.add(Offset(-d.dy / len, d.dx / len));
      } else {
        segNormals.add(const Offset(0, 1));
      }
    }

    final List<Offset> leftPoints = [];
    final List<Offset> rightPoints = [];

    for (int i = 0; i < n; i++) {
      Offset vNorm;
      if (i == 0) {
        vNorm = segNormals[0];
      } else if (i == n - 1) {
        vNorm = segNormals[n - 2];
      } else {
        final n1 = segNormals[i - 1];
        final n2 = segNormals[i];
        final avg = (n1 + n2) / 2;
        final avgLen = avg.distance;
        if (avgLen > 0.001) {
          // Clamp miter scale to avoid huge spikes on tight turns
          final miterScale = (1.0 / avgLen).clamp(0.5, 2.5);
          vNorm = (avg / avgLen) * miterScale;
        } else {
          vNorm = n1;
        }
      }
      leftPoints.add(centerline[i] + vNorm * halfWidth);
      rightPoints.add(centerline[i] - vNorm * halfWidth);
    }

    // Polygon boundary: left points forward, then right points backward
    return [...leftPoints, ...rightPoints.reversed];
  }

  /// Creates a Preferred Lane zone from an arbitrary polyline of 2 or more points
  /// buffered by [width] into a parallel corridor polygon.
  factory MapZone.createPolylineLane({
    required String map,
    required List<Offset> centerline,
    double width = 1.2,
    String? name,
  }) {
    final buffered = bufferPolyline(centerline, width);
    final id = 'lane_${DateTime.now().millisecondsSinceEpoch}';
    return MapZone(
      id: id,
      name: name ?? 'Preferred Lane',
      type: ZoneType.preferredLane,
      mapName: map,
      points: buffered,
    );
  }

  /// Creates a Preferred Lane zone using a single centerline segment
  /// ([start] -> [end]) buffered by [width] into a parallel corridor polygon.
  factory MapZone.createPreferredLane({
    required String map,
    required Offset start,
    required Offset end,
    double width = 1.2,
    String? name,
  }) {
    return MapZone.createPolylineLane(
      map: map,
      centerline: [start, end],
      width: width,
      name: name,
    );
  }

  /// Creates a Preferred Lane centered at [center], aligned with [heading] (in radians),
  /// with specified [length] (default 4.0m) and [width] (default 1.2m).
  factory MapZone.createDefaultLane({
    required String map,
    required Offset center,
    double length = 4.0,
    double width = 1.2,
    double heading = 0.0,
    String? name,
  }) {
    final halfLen = length / 2;
    final cosH = cos(heading);
    final sinH = sin(heading);
    final start = Offset(center.dx - cosH * halfLen, center.dy - sinH * halfLen);
    final end = Offset(center.dx + cosH * halfLen, center.dy + sinH * halfLen);
    return MapZone.createPreferredLane(
      map: map,
      start: start,
      end: end,
      width: width,
      name: name,
    );
  }

  /// Returns true if this zone is a Preferred Lane with a valid corridor polygon.
  bool get isCorridorLane =>
      type == ZoneType.preferredLane &&
      points.length >= 4 &&
      points.length % 2 == 0;

  /// Extracts the centerline turn nodes from the corridor polygon points.
  List<Offset> get laneCenterline {
    if (!isCorridorLane) return points;
    final k = points.length ~/ 2;
    final List<Offset> centerline = [];
    for (int i = 0; i < k; i++) {
      final left = points[i];
      final right = points[points.length - 1 - i];
      centerline.add((left + right) / 2);
    }
    return centerline;
  }

  /// Extracts the current corridor width of the lane in meters.
  double get laneWidth {
    if (!isCorridorLane) return 1.2;
    final left = points.first;
    final right = points.last;
    return (left - right).distance;
  }

  /// Re-buffers this lane with a new corridor [width], keeping its centerline intact.
  MapZone withLaneWidth(double width) {
    if (!isCorridorLane) return this;
    final cl = laneCenterline;
    final newPoints = bufferPolyline(cl, width);
    return copyWith(points: newPoints);
  }

  /// Re-buffers this lane with an updated centerline, keeping its corridor width.
  MapZone withLaneCenterline(List<Offset> newCenterline, {double? width}) {
    final w = width ?? laneWidth;
    final newPoints = bufferPolyline(newCenterline, w);
    return copyWith(points: newPoints);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.key,
      'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      if (speedLimitMps != null) 'speed_limit_mps': speedLimitMps,
      if (customColor != null)
        'color': '#${customColor!.toARGB32().toRadixString(16).padLeft(8, '0')}',
      if (mapName != null) 'map': mapName,
    };
  }

  factory MapZone.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List? ?? [];
    final pts = <Offset>[];
    for (final rp in rawPoints) {
      if (rp is Map && rp['x'] is num && rp['y'] is num) {
        pts.add(Offset((rp['x'] as num).toDouble(), (rp['y'] as num).toDouble()));
      }
    }
    Color? col;
    final colorStr = json['color'] as String?;
    if (colorStr != null && colorStr.startsWith('#')) {
      final hex = colorStr.replaceAll('#', '');
      if (hex.length == 6) {
        col = Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 8) {
        col = Color(int.parse(hex, radix: 16));
      }
    }

    return MapZone(
      id: json['id'] as String? ?? 'zone_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Zone',
      type: ZoneType.fromKey(json['type'] as String?),
      points: pts,
      speedLimitMps: (json['speed_limit_mps'] as num?)?.toDouble(),
      customColor: col,
      mapName: json['map'] as String?,
    );
  }
}
