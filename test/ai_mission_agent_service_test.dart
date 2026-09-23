import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nav2_mission_planner/services/ai_mission_agent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AiMissionAgentService', () {
    test('Synthesizes hospital medicine delivery mission with complete safety fallbacks', () async {
      final service = AiMissionAgentService.instance;
      final graph = await service.generateMissionGraph(
        userPrompt: 'go to pharmacy ask them to room 102 patient medicines if medicine available give to patient and take feedback come back',
        availableWaypoints: ['Dock', 'Pharmacy', 'Room 101', 'Room 102'],
      );

      // Verify graph structure
      expect(graph.name, contains('Pharmacy'));
      expect(graph.name, contains('Room 102'));
      expect(graph.nodes.isNotEmpty, true);
      expect(graph.edges.isNotEmpty, true);

      // Verify critical safety nodes
      final nodeTypes = graph.nodes.map((n) => n.type).toSet();
      expect(nodeTypes.contains('start'), true, reason: 'Must have start node');
      expect(nodeTypes.contains('battery_guard'), true, reason: 'Must check battery before dispatch');
      expect(nodeTypes.contains('navigate_waypoint'), true, reason: 'Must navigate to pharmacy and patient');
      expect(nodeTypes.contains('ui_choice'), true, reason: 'Must ask pharmacist if medicines are ready');
      expect(nodeTypes.contains('parallel'), true, reason: 'Must run voice and interaction in parallel');
      expect(nodeTypes.contains('ui_speech'), true, reason: 'Must speak voice announcement');
      expect(nodeTypes.contains('ui_interaction'), true, reason: 'Must present patient receipt/feedback form');
      expect(nodeTypes.contains('dock'), true, reason: 'Must return to charging dock');
      expect(nodeTypes.contains('end'), true, reason: 'Must terminate at end sink');

      // Verify fail-safe edges
      final edgePorts = graph.edges.map((e) => '${e.fromPort}->${e.toPort}').toSet();
      expect(edgePorts.contains('low_battery->in'), true, reason: 'Battery guard low_battery fallback edge');
      expect(edgePorts.contains('failed->in'), true, reason: 'Navigation failed recovery edge');
      expect(edgePorts.contains('timeout->in'), true, reason: 'Navigation / dialog timeout edge');

      // Verify layout positions (no (0,0) overlapping nodes)
      for (final n in graph.nodes) {
        expect(n.position.dx > 0, true, reason: 'Node ${n.id} x position must be > 0');
        expect(n.position.dy > 0, true, reason: 'Node ${n.id} y position must be > 0');
      }
    });

    test('Synthesizes patrol loop mission with safety guards', () async {
      final service = AiMissionAgentService.instance;
      final graph = await service.generateMissionGraph(
        userPrompt: 'Patrol Reception and Lab in a loop with battery check and return to dock',
        availableWaypoints: ['Dock', 'Reception', 'Lab'],
      );

      expect(graph.nodes.any((n) => n.type == 'battery_guard'), true);
      expect(graph.nodes.any((n) => n.type == 'dock'), true);
    });

    test('Verifies all 14 AI providers have valid display names and model suggestions', () {
      expect(AiProvider.values.length, 14);
      for (final p in AiProvider.values) {
        expect(p.displayName.isNotEmpty, true, reason: 'Provider ${p.name} must have a display name');
        expect(p.defaultModels.isNotEmpty, true, reason: 'Provider ${p.name} must have default models');
      }
    });

    test('applyCleanGraphLayout spaces nodes cleanly and aligns terminal nodes', () async {
      final service = AiMissionAgentService.instance;
      final graph = await service.generateMissionGraph(
        userPrompt: 'Go to Pharmacy, then go to Room 102, then dock',
        availableWaypoints: ['Pharmacy', 'Room 102', 'Dock'],
      );

      AiMissionAgentService.applyCleanGraphLayout(graph);

      // Verify no two nodes share the same position
      final positions = graph.nodes.map((n) => '${n.position.dx.round()},${n.position.dy.round()}').toList();
      final uniquePositions = positions.toSet();
      expect(uniquePositions.length, positions.length, reason: 'Every node must have a unique coordinate on the canvas');

      // Verify start node is at leftmost column and dock/end are further right
      final startNode = graph.nodes.firstWhere((n) => n.type == 'start');
      final endNodes = graph.nodes.where((n) => n.type == 'end' || n.type == 'dock');
      for (final endNode in endNodes) {
        expect(endNode.position.dx > startNode.position.dx, true);
      }
    });
  });
}
