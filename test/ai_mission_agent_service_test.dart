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

    test('Synthesizes industrial material logistics mission for factory/warehouse without medical fallback', () async {
      final service = AiMissionAgentService.instance;
      final prompt = 'industrial work space go to bay1 ask if any raw material is out of stock collect informaton procure it from store room and deliver to bay1 along with collect 10 units raspbeery pi5 and deliver to workstation. at end return to dock';
      final graph = await service.generateMissionGraph(
        userPrompt: prompt,
        availableWaypoints: ['Dock', 'Bay 1', 'Store Room', 'Workstation'],
      );

      // Verify domain and name
      expect(graph.name, contains('Industrial Material Logistics'));

      // Verify that NO hospital or medical terms leaked into nodes
      for (final n in graph.nodes) {
        final label = n.label.toLowerCase();
        final paramsStr = n.params.toString().toLowerCase();
        expect(label.contains('hospital'), false, reason: 'Node label "${n.label}" must not contain hospital');
        expect(label.contains('pharmacy'), false, reason: 'Node label "${n.label}" must not contain pharmacy');
        expect(label.contains('patient'), false, reason: 'Node label "${n.label}" must not contain patient');
        expect(paramsStr.contains('prescription'), false, reason: 'Params must not contain prescription');
      }

      // Verify concrete industrial nodes
      final nodeTypes = graph.nodes.map((n) => n.type).toSet();
      expect(nodeTypes.contains('start'), true);
      expect(nodeTypes.contains('battery_guard'), true);
      expect(nodeTypes.contains('navigate_waypoint'), true);
      expect(nodeTypes.contains('ui_choice'), true);
      expect(nodeTypes.contains('ui_interaction'), true);
      expect(nodeTypes.contains('dock'), true);

      // Verify waypoints navigated
      final navWaypoints = graph.nodes
          .where((n) => n.type == 'navigate_waypoint')
          .map((n) => (n.params['waypoint'] ?? n.label).toString().toLowerCase())
          .toList();
      expect(navWaypoints.any((w) => w.contains('bay 1') || w.contains('bay1')), true, reason: 'Must navigate to Bay 1');
      expect(navWaypoints.any((w) => w.contains('store room')), true, reason: 'Must navigate to Store Room');
      expect(navWaypoints.any((w) => w.contains('workstation')), true, reason: 'Must navigate to Workstation');

      // Verify error recovery edges exist
      final edgePorts = graph.edges.map((e) => '${e.fromPort}->${e.toPort}').toSet();
      expect(edgePorts.contains('low_battery->in'), true);
      expect(edgePorts.contains('failed->in'), true);
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

    test('Verifies VoiceTranscriptionProvider definitions and serialization', () {
      expect(VoiceTranscriptionProvider.values.length, 3);
      for (final v in VoiceTranscriptionProvider.values) {
        expect(v.displayName.isNotEmpty, true);
        expect(v.shortName.isNotEmpty, true);
        expect(v.modelName.isNotEmpty, true);
        expect(v.description.isNotEmpty, true);
      }

      // Test config JSON serialization
      final cfg = AiAgentConfig(
        provider: AiProvider.openai,
        apiKey: 'test-key',
        voiceProvider: VoiceTranscriptionProvider.groqWhisper,
        voiceApiKey: 'gsk-voice-key',
      );
      final json = cfg.toJson();
      expect(json['voiceProvider'], 'groqWhisper');
      expect(json['voiceApiKey'], 'gsk-voice-key');

      final restored = AiAgentConfig.fromJson(json);
      expect(restored.voiceProvider, VoiceTranscriptionProvider.groqWhisper);
      expect(restored.voiceApiKey, 'gsk-voice-key');
    });

    test('testVoiceConnection validates missing API key', () async {
      final service = AiMissionAgentService.instance;
      final res = await service.testVoiceConnection(
        provider: VoiceTranscriptionProvider.groqWhisper,
        apiKey: '',
      );
      expect(res['success'], false);
      expect(res['message'], contains('required'));
    });

    test('Synthesizes mission with interval trigger on start node when asked every X minutes', () async {
      final service = AiMissionAgentService.instance;
      final graph = await service.generateMissionGraph(
        userPrompt: 'Patrol Reception and Lab every 45 minutes with battery check and return to dock',
        availableWaypoints: ['Dock', 'Reception', 'Lab'],
      );

      final startNode = graph.nodes.firstWhere((n) => n.type == 'start');
      expect(startNode.params['trigger'], 'interval');
      expect(startNode.params['interval_minutes'], 45);
      expect(startNode.params['enabled'], true);
    });

    test('Synthesizes mission with clock alarm schedule trigger on start node when asked at specific time', () async {
      final service = AiMissionAgentService.instance;
      final graph = await service.generateMissionGraph(
        userPrompt: 'Patrol Reception and Lab at 8:30 AM on weekdays',
        availableWaypoints: ['Dock', 'Reception', 'Lab'],
      );

      final startNode = graph.nodes.firstWhere((n) => n.type == 'start');
      expect(startNode.params['trigger'], 'schedule');
      expect(startNode.params['schedule_hour'], 8);
      expect(startNode.params['schedule_minute'], 30);
      expect(startNode.params['schedule_type'], 'weekly');
      expect(startNode.params['weekdays'], [0, 1, 2, 3, 4]);
    });

    test('AiAgentConfig isConfigured correctly validates credentials and local providers', () {
      // Default config without API key is not configured
      final emptyGemini = AiAgentConfig(provider: AiProvider.gemini, apiKey: '');
      expect(emptyGemini.isConfigured, false);

      // Cloud provider with API key is configured
      final configuredGemini = AiAgentConfig(provider: AiProvider.gemini, apiKey: 'AIzaSyFakeKey123');
      expect(configuredGemini.isConfigured, true);

      final emptyOpenAi = AiAgentConfig(provider: AiProvider.openai, apiKey: '   ');
      expect(emptyOpenAi.isConfigured, false);

      final configuredOpenAi = AiAgentConfig(provider: AiProvider.openai, apiKey: 'sk-proj-xyz');
      expect(configuredOpenAi.isConfigured, true);

      // Local providers (Ollama, LM Studio) do not require cloud API key
      final localOllama = AiAgentConfig(provider: AiProvider.ollama, apiKey: '');
      expect(localOllama.isConfigured, true);

      final localLmStudio = AiAgentConfig(provider: AiProvider.lmstudio, apiKey: '');
      expect(localLmStudio.isConfigured, true);
    });
  });
}
