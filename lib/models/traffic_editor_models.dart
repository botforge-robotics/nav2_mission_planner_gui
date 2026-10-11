/// RMF Traffic Editor data models matching the official specification
/// from https://github.com/open-rmf/rmf_traffic_editor (.building.yaml schema).
library;

enum TrafficFeatureType {
  select,
  vertex,
  lane,
  wall,
  door,
  measurement,
  model,
}

enum DoorType {
  singleSliding,
  doubleSliding,
  singleTelescoping,
  doubleTelescoping,
  singleSwing,
  doubleSwing;

  String get label => switch (this) {
        DoorType.singleSliding => 'Single Sliding',
        DoorType.doubleSliding => 'Double Sliding',
        DoorType.singleTelescoping => 'Single Telescoping',
        DoorType.doubleTelescoping => 'Double Telescoping',
        DoorType.singleSwing => 'Single Swing',
        DoorType.doubleSwing => 'Double Swing',
      };

  String get key => switch (this) {
        DoorType.singleSliding => 'single_sliding',
        DoorType.doubleSliding => 'double_sliding',
        DoorType.singleTelescoping => 'single_telescoping',
        DoorType.doubleTelescoping => 'double_telescoping',
        DoorType.singleSwing => 'single_swing',
        DoorType.doubleSwing => 'double_swing',
      };
}

class EditorVertex {
  final String id;
  double x;
  double y;
  String name;
  bool isCharger;
  bool isParking;
  bool isHoldingPoint;
  String? dockName;
  String? mergerGroup;
  double? standoffDistance;
  double? standoffAngle;
  double? standoffX;
  double? standoffY;

  EditorVertex({
    required this.id,
    required this.x,
    required this.y,
    this.name = '',
    this.isCharger = false,
    this.isParking = false,
    this.isHoldingPoint = false,
    this.dockName,
    this.mergerGroup,
    this.standoffDistance,
    this.standoffAngle,
    this.standoffX,
    this.standoffY,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'name': name,
        'is_charger': isCharger,
        'is_parking': isParking,
        'is_holding_point': isHoldingPoint,
        if (dockName != null) 'dock_name': dockName,
        if (standoffDistance != null) 'standoff_distance': standoffDistance,
        if (standoffAngle != null) 'standoff_angle': standoffAngle,
        if (standoffX != null) 'standoff_x': standoffX,
        if (standoffY != null) 'standoff_y': standoffY,
      };

  factory EditorVertex.fromJson(Map<String, dynamic> json) => EditorVertex(
        id: json['id'] as String? ?? 'v_${DateTime.now().microsecondsSinceEpoch}',
        x: (json['x'] as num?)?.toDouble() ?? 0.0,
        y: (json['y'] as num?)?.toDouble() ?? 0.0,
        name: json['name'] as String? ?? '',
        isCharger: json['is_charger'] == true || json['isCharger'] == true,
        isParking: json['is_parking'] == true || json['isParking'] == true,
        isHoldingPoint: json['is_holding_point'] == true || json['isHoldingPoint'] == true,
        dockName: json['dock_name'] as String? ?? json['dockName'] as String?,
        standoffDistance: (json['standoff_distance'] as num?)?.toDouble(),
        standoffAngle: (json['standoff_angle'] as num?)?.toDouble(),
        standoffX: (json['standoff_x'] as num?)?.toDouble(),
        standoffY: (json['standoff_y'] as num?)?.toDouble(),
      );

  EditorVertex clone() => EditorVertex(
        id: id,
        x: x,
        y: y,
        name: name,
        isCharger: isCharger,
        isParking: isParking,
        isHoldingPoint: isHoldingPoint,
        dockName: dockName,
        mergerGroup: mergerGroup,
        standoffDistance: standoffDistance,
        standoffAngle: standoffAngle,
        standoffX: standoffX,
        standoffY: standoffY,
      );
}

class EditorEdge {
  final String id;
  final String startVertexId;
  final String endVertexId;
  bool bidirectional;
  double speedLimit; // m/s
  int orientationConstraint; // 0 = none, 1 = forward, 2 = reverse
  String? demoMockName;

  EditorEdge({
    required this.id,
    required this.startVertexId,
    required this.endVertexId,
    this.bidirectional = true,
    this.speedLimit = 0.0,
    this.orientationConstraint = 0,
    this.demoMockName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'start_idx': startVertexId,
        'end_idx': endVertexId,
        'bidirectional': bidirectional,
        'speed_limit': speedLimit,
        'orientation_constraint': orientationConstraint,
      };

  factory EditorEdge.fromJson(Map<String, dynamic> json) => EditorEdge(
        id: json['id'] as String? ?? 'edge_${DateTime.now().microsecondsSinceEpoch}',
        startVertexId: json['start_idx'] as String? ?? json['fromId'] as String? ?? '',
        endVertexId: json['end_idx'] as String? ?? json['toId'] as String? ?? '',
        bidirectional: json['bidirectional'] != false,
        speedLimit: (json['speed_limit'] as num?)?.toDouble() ?? 0.0,
        orientationConstraint: json['orientation_constraint'] as int? ?? 0,
      );

  EditorEdge clone() => EditorEdge(
        id: id,
        startVertexId: startVertexId,
        endVertexId: endVertexId,
        bidirectional: bidirectional,
        speedLimit: speedLimit,
        orientationConstraint: orientationConstraint,
        demoMockName: demoMockName,
      );
}

class EditorWall {
  final String id;
  final String startVertexId;
  final String endVertexId;
  double thickness; // in meters (default 0.15m = 15cm)

  EditorWall({
    required this.id,
    required this.startVertexId,
    required this.endVertexId,
    this.thickness = 0.15,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'start_idx': startVertexId,
        'end_idx': endVertexId,
        'thickness': thickness,
      };

  factory EditorWall.fromJson(Map<String, dynamic> json) => EditorWall(
        id: json['id'] as String? ?? 'wall_${DateTime.now().microsecondsSinceEpoch}',
        startVertexId: json['start_idx'] as String? ?? '',
        endVertexId: json['end_idx'] as String? ?? '',
        thickness: (json['thickness'] as num?)?.toDouble() ?? 0.15,
      );

  EditorWall clone() => EditorWall(
        id: id,
        startVertexId: startVertexId,
        endVertexId: endVertexId,
        thickness: thickness,
      );
}

class EditorDoor {
  final String id;
  final String name;
  final String startVertexId;
  final String endVertexId;
  DoorType doorType;
  double motionTime; // in seconds

  EditorDoor({
    required this.id,
    this.name = 'door',
    required this.startVertexId,
    required this.endVertexId,
    this.doorType = DoorType.singleSliding,
    this.motionTime = 5.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'start_idx': startVertexId,
        'end_idx': endVertexId,
        'door_type': doorType.key,
        'motion_time': motionTime,
      };

  factory EditorDoor.fromJson(Map<String, dynamic> json) {
    DoorType dt = DoorType.singleSliding;
    final typeKey = json['door_type'] as String? ?? '';
    for (final t in DoorType.values) {
      if (t.key == typeKey) {
        dt = t;
        break;
      }
    }
    return EditorDoor(
      id: json['id'] as String? ?? 'door_${DateTime.now().microsecondsSinceEpoch}',
      name: json['name'] as String? ?? 'door',
      startVertexId: json['start_idx'] as String? ?? '',
      endVertexId: json['end_idx'] as String? ?? '',
      doorType: dt,
      motionTime: (json['motion_time'] as num?)?.toDouble() ?? 5.0,
    );
  }

  EditorDoor clone() => EditorDoor(
        id: id,
        name: name,
        startVertexId: startVertexId,
        endVertexId: endVertexId,
        doorType: doorType,
        motionTime: motionTime,
      );
}

class EditorMeasurement {
  final String id;
  final String startVertexId;
  final String endVertexId;
  double distanceMeters;

  EditorMeasurement({
    required this.id,
    required this.startVertexId,
    required this.endVertexId,
    required this.distanceMeters,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'start_idx': startVertexId,
        'end_idx': endVertexId,
        'distance': distanceMeters,
      };

  factory EditorMeasurement.fromJson(Map<String, dynamic> json) => EditorMeasurement(
        id: json['id'] as String? ?? 'meas_${DateTime.now().microsecondsSinceEpoch}',
        startVertexId: json['start_idx'] as String? ?? '',
        endVertexId: json['end_idx'] as String? ?? '',
        distanceMeters: (json['distance'] as num?)?.toDouble() ?? 1.0,
      );

  EditorMeasurement clone() => EditorMeasurement(
        id: id,
        startVertexId: startVertexId,
        endVertexId: endVertexId,
        distanceMeters: distanceMeters,
      );
}

/// A complete Building Level representation compliant with Open-RMF traffic editor
class RmfLevelGraph {
  final String name;
  final List<EditorVertex> vertices;
  final List<EditorEdge> lanes;
  final List<EditorWall> walls;
  final List<EditorDoor> doors;
  final List<EditorMeasurement> measurements;

  RmfLevelGraph({
    required this.name,
    List<EditorVertex>? vertices,
    List<EditorEdge>? lanes,
    List<EditorWall>? walls,
    List<EditorDoor>? doors,
    List<EditorMeasurement>? measurements,
  })  : vertices = vertices ?? [],
        lanes = lanes ?? [],
        walls = walls ?? [],
        doors = doors ?? [],
        measurements = measurements ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'vertices': vertices.map((v) => v.toJson()).toList(),
        'lanes': lanes.map((l) => l.toJson()).toList(),
        'walls': walls.map((w) => w.toJson()).toList(),
        'doors': doors.map((d) => d.toJson()).toList(),
        'measurements': measurements.map((m) => m.toJson()).toList(),
      };

  factory RmfLevelGraph.fromJson(Map<String, dynamic> json, {String defaultName = 'L1'}) {
    final name = json['name'] as String? ?? defaultName;
    final rawVertices = (json['vertices'] as List? ?? json['waypoints'] as List? ?? []).cast<Map<String, dynamic>>();
    final rawLanes = (json['lanes'] as List? ?? []).cast<Map<String, dynamic>>();
    final rawWalls = (json['walls'] as List? ?? []).cast<Map<String, dynamic>>();
    final rawDoors = (json['doors'] as List? ?? []).cast<Map<String, dynamic>>();
    final rawMeasurements = (json['measurements'] as List? ?? []).cast<Map<String, dynamic>>();

    return RmfLevelGraph(
      name: name,
      vertices: rawVertices.map((v) => EditorVertex.fromJson(v)).toList(),
      lanes: rawLanes.map((l) => EditorEdge.fromJson(l)).toList(),
      walls: rawWalls.map((w) => EditorWall.fromJson(w)).toList(),
      doors: rawDoors.map((d) => EditorDoor.fromJson(d)).toList(),
      measurements: rawMeasurements.map((m) => EditorMeasurement.fromJson(m)).toList(),
    );
  }

  /// Exports level into standard RMF building.yaml string
  String toBuildingYamlString(String buildingName) {
    final buffer = StringBuffer();
    buffer.writeln('building_name: $buildingName');
    buffer.writeln('levels:');
    buffer.writeln('  $name:');
    buffer.writeln('    vertices:');
    for (final v in vertices) {
      buffer.writeln('      - [${v.x.toStringAsFixed(3)}, ${v.y.toStringAsFixed(3)}, 0, "${v.name}", {is_charger: ${v.isCharger}, is_parking: ${v.isParking}, is_holding_point: ${v.isHoldingPoint}}]');
    }
    buffer.writeln('    lanes:');
    for (final l in lanes) {
      final startIdx = vertices.indexWhere((v) => v.id == l.startVertexId);
      final endIdx = vertices.indexWhere((v) => v.id == l.endVertexId);
      if (startIdx >= 0 && endIdx >= 0) {
        buffer.writeln('      - [$startIdx, $endIdx, {bidirectional: ${l.bidirectional}, speed_limit: ${l.speedLimit}}]');
      }
    }
    buffer.writeln('    walls:');
    for (final w in walls) {
      final startIdx = vertices.indexWhere((v) => v.id == w.startVertexId);
      final endIdx = vertices.indexWhere((v) => v.id == w.endVertexId);
      if (startIdx >= 0 && endIdx >= 0) {
        buffer.writeln('      - [$startIdx, $endIdx, {thickness: ${w.thickness}}]');
      }
    }
    buffer.writeln('    doors:');
    for (final d in doors) {
      final startIdx = vertices.indexWhere((v) => v.id == d.startVertexId);
      final endIdx = vertices.indexWhere((v) => v.id == d.endVertexId);
      if (startIdx >= 0 && endIdx >= 0) {
        buffer.writeln('      - [$startIdx, $endIdx, {type: "${d.doorType.key}", name: "${d.name}", motion_time: ${d.motionTime}}]');
      }
    }
    return buffer.toString();
  }
}
