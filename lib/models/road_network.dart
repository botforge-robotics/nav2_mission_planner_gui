import 'package:flutter/material.dart';

/// Represents a topological waypoint node in Nav2 RouteServer's road network.
class RoadNode {
  const RoadNode({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
  });

  final int id;
  final String name;
  final double x;
  final double y;

  Offset get position => Offset(x, y);

  RoadNode copyWith({
    int? id,
    String? name,
    double? x,
    double? y,
  }) {
    return RoadNode(
      id: id ?? this.id,
      name: name ?? this.name,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'x': x,
        'y': y,
      };

  factory RoadNode.fromJson(Map<String, dynamic> json) => RoadNode(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? 'Node ${json['id']}',
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );

  Map<String, dynamic> toGeoJsonFeature() => {
        'type': 'Feature',
        'properties': {
          'id': id,
          'name': name,
          'frame': 'map',
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [x, y],
        },
      };

  static RoadNode? fromGeoJsonFeature(Map<String, dynamic> feature) {
    if (feature['type'] != 'Feature') return null;
    final geom = feature['geometry'] as Map<String, dynamic>?;
    if (geom == null || geom['type'] != 'Point') return null;
    final coords = geom['coordinates'] as List?;
    if (coords == null || coords.length < 2) return null;
    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final id = (props['id'] as num?)?.toInt() ?? 0;
    final name = props['name'] as String? ?? 'Node $id';
    return RoadNode(
      id: id,
      name: name,
      x: (coords[0] as num).toDouble(),
      y: (coords[1] as num).toDouble(),
    );
  }
}

/// Represents a roadway corridor edge connecting two nodes in Nav2 RouteServer.
class RoadEdge {
  const RoadEdge({
    required this.id,
    required this.startId,
    required this.endId,
    this.bidirectional = true,
    this.speedLimit,
    this.cost,
  });

  final int id;
  final int startId;
  final int endId;
  final bool bidirectional;
  final double? speedLimit;
  final double? cost;

  RoadEdge copyWith({
    int? id,
    int? startId,
    int? endId,
    bool? bidirectional,
    double? speedLimit,
    double? cost,
  }) {
    return RoadEdge(
      id: id ?? this.id,
      startId: startId ?? this.startId,
      endId: endId ?? this.endId,
      bidirectional: bidirectional ?? this.bidirectional,
      speedLimit: speedLimit ?? this.speedLimit,
      cost: cost ?? this.cost,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'start_id': startId,
        'end_id': endId,
        'bidirectional': bidirectional,
        if (speedLimit != null) 'speed_limit': speedLimit,
        if (cost != null) 'cost': cost,
      };

  factory RoadEdge.fromJson(Map<String, dynamic> json) => RoadEdge(
        id: (json['id'] as num).toInt(),
        startId: (json['start_id'] as num).toInt(),
        endId: (json['end_id'] as num).toInt(),
        bidirectional: json['bidirectional'] as bool? ?? true,
        speedLimit: (json['speed_limit'] as num?)?.toDouble(),
        cost: (json['cost'] as num?)?.toDouble(),
      );

  List<Map<String, dynamic>> toGeoJsonFeatures(Map<int, RoadNode> nodeMap) {
    final start = nodeMap[startId];
    final end = nodeMap[endId];
    if (start == null || end == null) return const [];

    final metadata = <String, dynamic>{};
    if (speedLimit != null) metadata['speed_limit'] = speedLimit;

    final forward = <String, dynamic>{
      'type': 'Feature',
      'properties': {
        'id': id,
        'startid': startId,
        'endid': endId,
        if (cost != null) 'cost': cost,
        if (metadata.isNotEmpty) 'metadata': metadata,
      },
      'geometry': {
        'type': 'MultiLineString',
        'coordinates': [
          [
            [start.x, start.y],
            [end.x, end.y],
          ]
        ],
      },
    };

    if (!bidirectional) {
      return [forward];
    }

    final reverse = <String, dynamic>{
      'type': 'Feature',
      'properties': {
        'id': id + 100000,
        'startid': endId,
        'endid': startId,
        if (cost != null) 'cost': cost,
        if (metadata.isNotEmpty) 'metadata': metadata,
      },
      'geometry': {
        'type': 'MultiLineString',
        'coordinates': [
          [
            [end.x, end.y],
            [start.x, start.y],
          ]
        ],
      },
    };

    return [forward, reverse];
  }
}

/// A complete Road Network graph for an active floor map.
class RoadNetwork {
  const RoadNetwork({
    required this.mapName,
    this.nodes = const [],
    this.edges = const [],
  });

  final String mapName;
  final List<RoadNode> nodes;
  final List<RoadEdge> edges;

  bool get isEmpty => nodes.isEmpty && edges.isEmpty;
  bool get isNotEmpty => !isEmpty;

  Map<int, RoadNode> get nodeMap => {for (final n in nodes) n.id: n};

  int get nextAvailableNodeId {
    if (nodes.isEmpty) return 1;
    final maxId = nodes.map((n) => n.id).reduce((a, b) => a > b ? a : b);
    return maxId + 1;
  }

  int get nextAvailableEdgeId {
    if (edges.isEmpty) return 1;
    final maxId = edges.map((e) => e.id).reduce((a, b) => a > b ? a : b);
    return maxId + 1;
  }

  RoadNetwork copyWith({
    String? mapName,
    List<RoadNode>? nodes,
    List<RoadEdge>? edges,
  }) {
    return RoadNetwork(
      mapName: mapName ?? this.mapName,
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
    );
  }

  Map<String, dynamic> toJson() => {
        'map': mapName,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
      };

  factory RoadNetwork.fromJson(Map<String, dynamic> json) => RoadNetwork(
        mapName: json['map'] as String? ?? 'default',
        nodes: (json['nodes'] as List?)
                ?.map((n) => RoadNode.fromJson(n as Map<String, dynamic>))
                .toList() ??
            const [],
        edges: (json['edges'] as List?)
                ?.map((e) => RoadEdge.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toGeoJson() {
    final nMap = nodeMap;
    final features = <Map<String, dynamic>>[];

    for (final node in nodes) {
      features.add(node.toGeoJsonFeature());
    }

    for (final edge in edges) {
      features.addAll(edge.toGeoJsonFeatures(nMap));
    }

    return {
      'type': 'FeatureCollection',
      'name': 'graph',
      'crs': {
        'type': 'name',
        'properties': {'name': 'urn:ogc:def:crs:EPSG::3857'},
      },
      'features': features,
    };
  }

  factory RoadNetwork.fromGeoJson(String mapName, Map<String, dynamic> geoJson) {
    final rawFeatures = geoJson['features'] as List? ?? [];
    final nodesList = <RoadNode>[];
    final edgesMap = <String, RoadEdge>{};

    for (final item in rawFeatures) {
      if (item is! Map<String, dynamic>) continue;
      final geom = item['geometry'] as Map<String, dynamic>?;
      final geomType = geom?['type'] as String?;

      if (geomType == 'Point') {
        final node = RoadNode.fromGeoJsonFeature(item);
        if (node != null) nodesList.add(node);
      } else if (geomType == 'MultiLineString' || geomType == 'LineString') {
        final props = item['properties'] as Map<String, dynamic>? ?? {};
        final rawId = (props['id'] as num?)?.toInt() ?? 0;
        final startId = (props['startid'] as num?)?.toInt();
        final endId = (props['endid'] as num?)?.toInt();
        if (startId == null || endId == null) continue;

        // Skip synthesized reverse edge features (> 100000)
        final effectiveId = rawId >= 100000 ? rawId - 100000 : rawId;
        final pairKey = startId < endId ? '$startId-$endId' : '$endId-$startId';

        final meta = props['metadata'] as Map<String, dynamic>? ?? {};
        final speed = (meta['speed_limit'] as num?)?.toDouble();
        final cost = (props['cost'] as num?)?.toDouble();

        if (edgesMap.containsKey(pairKey)) {
          // If both directions exist, it is bidirectional
          final existing = edgesMap[pairKey]!;
          edgesMap[pairKey] = existing.copyWith(bidirectional: true);
        } else {
          edgesMap[pairKey] = RoadEdge(
            id: effectiveId > 0 ? effectiveId : edgesMap.length + 1,
            startId: startId,
            endId: endId,
            bidirectional: props['bidirectional'] == true,
            speedLimit: speed,
            cost: cost,
          );
        }
      }
    }

    return RoadNetwork(
      mapName: mapName,
      nodes: nodesList,
      edges: edgesMap.values.toList(),
    );
  }
}
