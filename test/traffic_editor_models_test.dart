import 'package:flutter_test/flutter_test.dart';
import 'package:nav2_mission_planner/models/traffic_editor_models.dart';

void main() {
  group('Traffic Editor Models & Renaming', () {
    test('EditorVertex retains renamed name and serializes to JSON and building YAML', () {
      final vertex = EditorVertex(
        id: 'v_123',
        x: 5.25,
        y: -3.50,
        name: 'wp_1',
      );

      expect(vertex.name, 'wp_1');

      // Rename vertex
      vertex.name = 'Main_Intersection';
      expect(vertex.name, 'Main_Intersection');

      final json = vertex.toJson();
      expect(json['name'], 'Main_Intersection');

      final restored = EditorVertex.fromJson(json);
      expect(restored.name, 'Main_Intersection');
      expect(restored.x, 5.25);
      expect(restored.y, -3.50);
    });

    test('RmfLevelGraph exports renamed intersection vertices to building YAML', () {
      final v1 = EditorVertex(id: 'v_1', x: 0.0, y: 0.0, name: 'North_Entry');
      final v2 = EditorVertex(id: 'v_2', x: 10.0, y: 0.0, name: 'Intersection_Center');
      final v3 = EditorVertex(id: 'v_3', x: 10.0, y: 10.0, name: 'South_Exit');

      final lane1 = EditorEdge(id: 'l_1', startVertexId: 'v_1', endVertexId: 'v_2', width: 0.40);
      final lane2 = EditorEdge(id: 'l_2', startVertexId: 'v_2', endVertexId: 'v_3', width: 0.40);

      final graph = RmfLevelGraph(
        name: 'L1',
        vertices: [v1, v2, v3],
        lanes: [lane1, lane2],
      );

      final yaml = graph.toBuildingYamlString('Campus');
      expect(yaml, contains('Intersection_Center'));
      expect(yaml, contains('North_Entry'));
      expect(yaml, contains('South_Exit'));
    });
  });
}
