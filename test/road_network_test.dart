import 'package:flutter_test/flutter_test.dart';
import 'package:nav2_mission_planner/models/road_network.dart';

void main() {
  group('RoadNode serialization', () {
    test('converts to and from GeoJSON Point Feature', () {
      final node = RoadNode(id: 42, name: 'Warehouse Entrance', x: 12.34, y: 56.78);
      final feature = node.toGeoJsonFeature();

      expect(feature['type'], 'Feature');
      expect(feature['geometry']['type'], 'Point');
      expect(feature['geometry']['coordinates'], [12.34, 56.78]);
      expect(feature['properties']['id'], 42);
      expect(feature['properties']['name'], 'Warehouse Entrance');

      final reconstructed = RoadNode.fromGeoJsonFeature(feature);
      expect(reconstructed, isNotNull);
      expect(reconstructed!.id, 42);
      expect(reconstructed.name, 'Warehouse Entrance');
      expect(reconstructed.x, closeTo(12.34, 0.001));
      expect(reconstructed.y, closeTo(56.78, 0.001));
    });
  });

  group('RoadEdge serialization', () {
    test('converts unidirectional edge to single MultiLineString Feature', () {
      final edge = RoadEdge(
        id: 10,
        startId: 1,
        endId: 2,
        bidirectional: false,
        speedLimit: 0.35,
      );
      final nodes = {
        1: RoadNode(id: 1, name: 'N1', x: 0.0, y: 0.0),
        2: RoadNode(id: 2, name: 'N2', x: 2.0, y: 2.0),
      };

      final features = edge.toGeoJsonFeatures(nodes);
      expect(features.length, 1);
      final f = features.first;
      expect(f['type'], 'Feature');
      expect(f['geometry']['type'], 'MultiLineString');
      expect(f['geometry']['coordinates'], [
        [[0.0, 0.0], [2.0, 2.0]],
      ]);
      expect(f['properties']['id'], 10);
      expect(f['properties']['startid'], 1);
      expect(f['properties']['endid'], 2);
      expect(f['properties']['metadata']['speed_limit'], 0.35);
    });

    test('converts bidirectional edge to 2 directed MultiLineString Features', () {
      final edge = RoadEdge(
        id: 20,
        startId: 3,
        endId: 4,
        bidirectional: true,
        speedLimit: 0.5,
      );
      final nodes = {
        3: RoadNode(id: 3, name: 'N3', x: 1.0, y: 1.0),
        4: RoadNode(id: 4, name: 'N4', x: 4.0, y: 5.0),
      };

      final features = edge.toGeoJsonFeatures(nodes);
      expect(features.length, 2);

      // Forward feature
      final fwd = features[0];
      expect(fwd['properties']['startid'], 3);
      expect(fwd['properties']['endid'], 4);
      expect(fwd['geometry']['coordinates'], [
        [[1.0, 1.0], [4.0, 5.0]],
      ]);

      // Reverse feature
      final rev = features[1];
      expect(rev['properties']['startid'], 4);
      expect(rev['properties']['endid'], 3);
      expect(rev['geometry']['coordinates'], [
        [[4.0, 5.0], [1.0, 1.0]],
      ]);
    });
  });

  group('RoadNetwork serialization & helpers', () {
    test('roundtrips complete RoadNetwork via GeoJSON FeatureCollection', () {
      final network = RoadNetwork(
        mapName: 'office_floor1',
        nodes: [
          RoadNode(id: 1, name: 'Dock', x: 0.0, y: 0.0),
          RoadNode(id: 2, name: 'Hallway', x: 5.0, y: 0.0),
          RoadNode(id: 3, name: 'Lab', x: 5.0, y: 5.0),
        ],
        edges: [
          RoadEdge(id: 1, startId: 1, endId: 2, bidirectional: true, speedLimit: 0.4),
          RoadEdge(id: 2, startId: 2, endId: 3, bidirectional: false),
        ],
      );

      final geoJson = network.toGeoJson();
      expect(geoJson['type'], 'FeatureCollection');
      final features = geoJson['features'] as List;
      // 3 nodes + 2 for edge 1 (bidirectional) + 1 for edge 2 = 6 features
      expect(features.length, 6);

      final reconstructed = RoadNetwork.fromGeoJson('office_floor1', geoJson);
      expect(reconstructed.mapName, 'office_floor1');
      expect(reconstructed.nodes.length, 3);
      expect(reconstructed.edges.length, 2);

      // Check node restoration
      final n1 = reconstructed.nodeMap[1];
      expect(n1?.name, 'Dock');
      expect(n1?.x, 0.0);

      // Check bidirectional edge deduplication and restoration
      final e1 = reconstructed.edges.firstWhere((e) => e.startId == 1 && e.endId == 2);
      expect(e1.bidirectional, isTrue);
      expect(e1.speedLimit, closeTo(0.4, 0.01));

      final e2 = reconstructed.edges.firstWhere((e) => e.startId == 2 && e.endId == 3);
      expect(e2.bidirectional, isFalse);
      expect(e2.speedLimit, isNull);
    });

    test('generates next available node and edge IDs correctly', () {
      final network = RoadNetwork(
        mapName: 'test',
        nodes: [
          RoadNode(id: 1, name: 'N1', x: 0, y: 0),
          RoadNode(id: 5, name: 'N5', x: 1, y: 1),
        ],
        edges: [
          RoadEdge(id: 3, startId: 1, endId: 5, bidirectional: true),
        ],
      );

      expect(network.nextAvailableNodeId, 6);
      expect(network.nextAvailableEdgeId, 4);
    });

    test('handles empty network safely', () {
      final empty = RoadNetwork(mapName: 'empty');
      expect(empty.nextAvailableNodeId, 1);
      expect(empty.nextAvailableEdgeId, 1);
      expect(empty.nodeMap[1], isNull);

      final geoJson = empty.toGeoJson();
      expect(geoJson['features'], isEmpty);

      final parsed = RoadNetwork.fromGeoJson('empty', geoJson);
      expect(parsed.nodes, isEmpty);
      expect(parsed.edges, isEmpty);
    });

    test('formats road nodes cleanly for direct go navigation target maps', () {
      final node = RoadNode(id: 3, name: 'Node 3', x: 9.03, y: 3.46);
      final directGoData = {
        'name': node.name,
        'x': node.x,
        'y': node.y,
        'theta': 0.0,
        'node_id': node.id,
        'is_node': true,
      };

      expect(directGoData['is_node'], isTrue);
      expect(directGoData['name'], 'Node 3');
      expect(directGoData['x'], 9.03);
      expect(directGoData['y'], 3.46);
      expect(directGoData['theta'], 0.0);
      expect(directGoData['node_id'], 3);
    });
  });
}
