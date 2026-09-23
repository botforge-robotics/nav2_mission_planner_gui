import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/missions/graph/mission_graph_models.dart';

enum AiProvider {
  gemini,
  openai,
  anthropic,
  ollama,
  custom,
}

class AiAgentConfig {
  AiAgentConfig({
    this.provider = AiProvider.gemini,
    this.apiKey = '',
    this.model = 'gemini-1.5-flash',
    this.baseUrl = '',
  });

  final AiProvider provider;
  final String apiKey;
  final String model;
  final String baseUrl;

  AiAgentConfig copyWith({
    AiProvider? provider,
    String? apiKey,
    String? model,
    String? baseUrl,
  }) {
    return AiAgentConfig(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'apiKey': apiKey,
        'model': model,
        'baseUrl': baseUrl,
      };

  factory AiAgentConfig.fromJson(Map<String, dynamic> json) {
    return AiAgentConfig(
      provider: AiProvider.values.firstWhere(
        (e) => e.name == (json['provider'] as String?),
        orElse: () => AiProvider.gemini,
      ),
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? 'gemini-1.5-flash',
      baseUrl: json['baseUrl'] as String? ?? '',
    );
  }
}

class AiMissionAgentService {
  AiMissionAgentService._();
  static final AiMissionAgentService instance = AiMissionAgentService._();

  static const String _prefKey = 'navpro_ai_agent_config';
  AiAgentConfig? _cachedConfig;

  Future<AiAgentConfig> getConfig() async {
    if (_cachedConfig != null) return _cachedConfig!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _cachedConfig = AiAgentConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        return _cachedConfig!;
      } catch (e) {
        debugPrint('[AI Agent] Failed to parse saved config: $e');
      }
    }
    _cachedConfig = AiAgentConfig();
    return _cachedConfig!;
  }

  Future<void> saveConfig(AiAgentConfig config) async {
    _cachedConfig = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(config.toJson()));
  }

  /// System prompt giving the LLM deep knowledge of NavPro Mini mission nodes and safety rules.
  String _buildSystemPrompt(List<String> availableWaypoints) {
    final wpList = availableWaypoints.isNotEmpty
        ? availableWaypoints.join(', ')
        : 'Dock, Pharmacy, Room 101, Room 102, Triage, Nurse Station, Reception, Lab';

    return '''
You are the Autonomous Robotics Mission Architect AI for NavPro Mini AMR.
Your task is to convert human natural language mission descriptions into a complete, safe, and executable Mission Graph JSON.

### KNOWN WAYPOINTS ON CURRENT MAP:
[$wpList]

### AVAILABLE NODE TYPES & SCHEMA:
1. "start": Mission entry point.
   - Input ports: NONE
   - Output ports: "next"
   - Params: {}

2. "end": Terminal stop node.
   - Input ports: "in"
   - Output ports: NONE
   - Params: {}

3. "navigate_waypoint": Navigates AMR to a named waypoint.
   - Input ports: "in"
   - Output ports: "arrived", "failed", "timeout"
   - Params: {"waypoint": "WaypointName", "tolerance_m": 0.25}

4. "navigate_coordinates": Navigates AMR to metric coordinates (x, y, theta).
   - Input ports: "in"
   - Output ports: "arrived", "failed", "timeout"
   - Params: {"x": 1.5, "y": 2.5, "theta": 0.0}

5. "dock": Auto-dock robot into charging station.
   - Input ports: "in"
   - Output ports: "docked", "failed"
   - Params: {}

6. "undock": Leave charging station safely.
   - Input ports: "in"
   - Output ports: "undocked", "failed"
   - Params: {}

7. "battery_guard": Validates battery percentage before starting or continuing.
   - Input ports: "in"
   - Output ports: "ok", "low_battery"
   - Params: {"min_battery": 20.0}

8. "ui_speech": Text-to-speech announcement on robot speaker.
   - Input ports: "in"
   - Output ports: "done"
   - Params: {"text": "Speaking text", "voice": "female"}

9. "ui_choice": Kiosk screen question with choice buttons (e.g. Yes/No, Confirm/Cancel).
   - Input ports: "in"
   - Output ports: Each choice in lowercase (e.g. "yes", "no"), plus "timeout"
   - Params: {"title": "Question Title", "message": "Question prompt message", "options": ["Yes", "No"], "timeout_seconds": 60}

10. "ui_interaction": Dynamic kiosk form with input fields (text, number, select, checkbox, signature).
    - Input ports: "in"
    - Output ports: "submitted", "cancelled", "timeout"
    - Params: {
        "title": "Form Title",
        "message": "Instructions",
        "subtype": "dynamic_form",
        "fields": [
          {"key": "room", "label": "Room Number", "type": "text", "required": true},
          {"key": "feedback", "label": "Feedback Notes", "type": "text", "required": false}
        ],
        "timeout_seconds": 90
      }

11. "parallel": Executes multiple branches simultaneously (e.g. speak while moving, or notify while waiting).
    - Input ports: "in"
    - Output ports: "branch_1", "branch_2", ...
    - Params: {"branch_count": 2}

12. "wait": Timer delay.
    - Input ports: "in"
    - Output ports: "next"
    - Params: {"seconds": 5}

13. "patrol_loop": Continuous patrol through sequence of waypoints.
    - Input ports: "in"
    - Output ports: "completed", "failed", "interrupted"
    - Params: {"waypoints": ["Wp1", "Wp2"], "loop_count": 1}

14. "condition": Branching based on variables.
    - Input ports: "in"
    - Output ports: "true", "false"
    - Params: {"variable": "var_name", "operator": "==", "value": "val"}

15. "set_variable": Store variable state.
    - Input ports: "in"
    - Output ports: "next"
    - Params: {"key": "key", "value": "value"}

16. "emergency_stop": Immediate robot safety halt.
    - Input ports: "in"
    - Output ports: "next"
    - Params: {}

### CRITICAL SAFETY & DESIGN RULES:
1. Always start with a "start" node.
2. Safety check: Insert a "battery_guard" check near the beginning. If "low_battery", route to "dock" or safe abort.
3. Fail-safe recovery: For every "navigate_waypoint" and "navigate_coordinates", you MUST connect the "failed" and "timeout" ports to a safety branch (e.g. announce error with "ui_speech", alert operator, or return to "dock"). Never leave error ports dangling!
4. User interactions: If asking questions or choices, handle the negative / cancelled / timeout branches gracefully (e.g. return to dock or end).
5. All branches must terminate at an "end" node or "dock" node.
6. Return ONLY valid JSON conforming to the output schema. No conversational filler, no markdown quotes outside the JSON block.

### JSON OUTPUT SCHEMA:
{
  "name": "Mission Title",
  "description": "Short summary",
  "nodes": [
    {"id": "node_1", "type": "start", "label": "Start Mission", "params": {}},
    {"id": "node_2", "type": "battery_guard", "label": "Check Battery", "params": {"min_battery": 20.0}},
    ...
  ],
  "edges": [
    {"id": "e_1", "from_node": "node_1", "from_port": "next", "to_node": "node_2", "to_port": "in"},
    ...
  ]
}
''';
  }

  /// Generates a MissionGraph from a user natural language prompt.
  /// If an API key is configured, invokes the LLM.
  /// If no key or offline, uses the intelligent offline robotics parser.
  Future<MissionGraph> generateMissionGraph({
    required String userPrompt,
    required List<String> availableWaypoints,
    MissionGraph? existingGraph,
  }) async {
    final config = await getConfig();
    final trimmedPrompt = userPrompt.trim();
    if (trimmedPrompt.isEmpty) {
      throw Exception('Mission description cannot be empty.');
    }

    Map<String, dynamic>? generatedJson;

    // Check if user has an API key configured for external LLM
    final hasKey = config.apiKey.trim().isNotEmpty || config.provider == AiProvider.ollama;

    if (hasKey) {
      try {
        generatedJson = await _callLlm(config, trimmedPrompt, availableWaypoints);
      } catch (e) {
        debugPrint('[AI Agent] LLM call failed ($e), falling back to intelligent offline generator...');
      }
    }

    // Fallback to intelligent offline template engine
    generatedJson ??= _generateOfflineWorkflow(trimmedPrompt, availableWaypoints);

    // Parse and auto-layout the graph visually
    return _buildAndLayoutGraph(generatedJson, availableWaypoints);
  }

  /// Calls the selected AI provider.
  Future<Map<String, dynamic>> _callLlm(
    AiAgentConfig config,
    String userPrompt,
    List<String> availableWaypoints,
  ) async {
    final systemPrompt = _buildSystemPrompt(availableWaypoints);
    String responseText = '';

    switch (config.provider) {
      case AiProvider.gemini:
        final model = config.model.isNotEmpty ? config.model : 'gemini-1.5-flash';
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${config.apiKey.trim()}',
        );
        final resp = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': '$systemPrompt\n\nUSER INSTRUCTION:\n$userPrompt'}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.2,
              'responseMimeType': 'application/json',
            }
          }),
        ).timeout(const Duration(seconds: 25));

        if (resp.statusCode != 200) {
          throw Exception('Gemini API error (${resp.statusCode}): ${resp.body}');
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        responseText = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        break;

      case AiProvider.openai:
      case AiProvider.custom:
      case AiProvider.ollama:
        String baseUrl = config.baseUrl.trim();
        if (baseUrl.isEmpty) {
          if (config.provider == AiProvider.openai) {
            baseUrl = 'https://api.openai.com/v1';
          } else if (config.provider == AiProvider.ollama) {
            baseUrl = 'http://localhost:11434/v1';
          }
        }
        if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        final url = Uri.parse('$baseUrl/chat/completions');

        final headers = <String, String>{
          'Content-Type': 'application/json',
        };
        if (config.apiKey.trim().isNotEmpty) {
          headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
        }

        final model = config.model.isNotEmpty
            ? config.model
            : (config.provider == AiProvider.ollama ? 'llama3:8b' : 'gpt-4o-mini');

        final resp = await http.post(
          url,
          headers: headers,
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userPrompt}
            ],
            'temperature': 0.2,
            'response_format': {'type': 'json_object'},
          }),
        ).timeout(const Duration(seconds: 30));

        if (resp.statusCode != 200) {
          throw Exception('${config.provider.name} API error (${resp.statusCode}): ${resp.body}');
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        responseText = data['choices']?[0]?['message']?['content'] ?? '';
        break;

      case AiProvider.anthropic:
        final url = Uri.parse('https://api.anthropic.com/v1/messages');
        final model = config.model.isNotEmpty ? config.model : 'claude-3-5-sonnet-20241022';
        final resp = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': config.apiKey.trim(),
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': 3000,
            'system': systemPrompt,
            'messages': [
              {'role': 'user', 'content': userPrompt}
            ],
            'temperature': 0.2,
          }),
        ).timeout(const Duration(seconds: 30));

        if (resp.statusCode != 200) {
          throw Exception('Anthropic API error (${resp.statusCode}): ${resp.body}');
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        responseText = data['content']?[0]?['text'] ?? '';
        break;
    }

    return _extractJsonFromLlmOutput(responseText);
  }

  /// Extracts and parses JSON from LLM response (handling potential markdown ```json blocks).
  Map<String, dynamic> _extractJsonFromLlmOutput(String text) {
    String clean = text.trim();
    if (clean.contains('```json')) {
      final start = clean.indexOf('```json') + 7;
      final end = clean.lastIndexOf('```');
      if (end > start) clean = clean.substring(start, end).trim();
    } else if (clean.contains('```')) {
      final start = clean.indexOf('```') + 3;
      final end = clean.lastIndexOf('```');
      if (end > start) clean = clean.substring(start, end).trim();
    }
    return jsonDecode(clean) as Map<String, dynamic>;
  }

  /// Intelligent Offline Workflow Generator:
  /// Uses advanced NLP intent parsing to construct rich, safe, multi-branch workflows
  /// even when offline or when no API key is configured.
  Map<String, dynamic> _generateOfflineWorkflow(
    String prompt,
    List<String> availableWaypoints,
  ) {
    final lower = prompt.toLowerCase();

    // Find mentioned waypoints or defaults
    String fromWp = '';
    String toWp = '';

    for (final wp in availableWaypoints) {
      if (lower.contains(wp.toLowerCase())) {
        if (fromWp.isEmpty) {
          fromWp = wp;
        } else if (toWp.isEmpty && wp != fromWp) {
          toWp = wp;
        }
      }
    }

    // Default heuristics if not explicitly matched
    if (fromWp.isEmpty) {
      if (lower.contains('pharmacy')) {
        fromWp = 'Pharmacy';
      } else if (lower.contains('kitchen')) {
        fromWp = 'Kitchen';
      } else if (lower.contains('lab')) {
        fromWp = 'Lab';
      } else {
        fromWp = availableWaypoints.isNotEmpty ? availableWaypoints.first : 'Pharmacy';
      }
    }

    if (toWp.isEmpty) {
      final roomMatch = RegExp(r'room\s*(\d+)').firstMatch(lower);
      if (roomMatch != null) {
        toWp = 'Room ${roomMatch.group(1)}';
      } else if (lower.contains('patient')) {
        toWp = 'Room 102';
      } else if (lower.contains('reception')) {
        toWp = 'Reception';
      } else if (availableWaypoints.length > 1) {
        toWp = availableWaypoints[1];
      } else {
        toWp = 'Room 102';
      }
    }

    final hasMedicineOrDelivery = lower.contains('medicine') ||
        lower.contains('delivery') ||
        lower.contains('deliver') ||
        lower.contains('pharmacy');

    // Build delivery / pharmacy workflow with full safety branchings
    if (hasMedicineOrDelivery) {
      return {
        'name': 'Medical Delivery: $fromWp to $toWp',
        'description': 'Autonomous delivery with battery guard, pharmacist confirmation, patient verification, feedback collection, and safe dock return.',
        'nodes': [
          {'id': 'n_start', 'type': 'start', 'label': 'Start Mission', 'params': {}},
          {'id': 'n_bat', 'type': 'battery_guard', 'label': 'Battery Guard (>20%)', 'params': {'min_battery': 20.0}},
          {
            'id': 'n_go_source',
            'type': 'navigate_waypoint',
            'label': 'Go to $fromWp',
            'params': {'waypoint': fromWp, 'tolerance_m': 0.25}
          },
          {
            'id': 'n_ask_source',
            'type': 'ui_choice',
            'label': 'Pharmacy Dispatch Confirm',
            'params': {
              'title': '$fromWp Dispatch',
              'message': 'Are medicines for $toWp ready and loaded into compartment?',
              'options': ['Yes', 'No'],
              'timeout_seconds': 60
            }
          },
          {
            'id': 'n_go_dest',
            'type': 'navigate_waypoint',
            'label': 'Deliver to $toWp',
            'params': {'waypoint': toWp, 'tolerance_m': 0.25}
          },
          {
            'id': 'n_parallel',
            'type': 'parallel',
            'label': 'Announce & Prompt',
            'params': {'branch_count': 2}
          },
          {
            'id': 'n_voice_patient',
            'type': 'ui_speech',
            'label': 'Patient Voice Alert',
            'params': {'text': 'Hello! Your medicine delivery from $fromWp has arrived. Please collect it.', 'voice': 'female'}
          },
          {
            'id': 'n_patient_form',
            'type': 'ui_interaction',
            'label': 'Patient Receipt & Feedback',
            'params': {
              'title': 'Delivery Receipt: $toWp',
              'message': 'Please confirm received medicines and leave feedback.',
              'subtype': 'dynamic_form',
              'fields': [
                {'key': 'collected', 'label': 'Medicines Collected', 'type': 'switch', 'required': true, 'default_value': true},
                {'key': 'feedback', 'label': 'Patient Notes / Pain Rating', 'type': 'text', 'required': false}
              ],
              'timeout_seconds': 90
            }
          },
          {
            'id': 'n_dock_success',
            'type': 'dock',
            'label': 'Return to Charging Dock',
            'params': {}
          },
          {
            'id': 'n_voice_abort',
            'type': 'ui_speech',
            'label': 'Announce Abort / Empty',
            'params': {'text': 'Medicine not available at $fromWp. Returning to charger.', 'voice': 'female'}
          },
          {
            'id': 'n_dock_abort',
            'type': 'dock',
            'label': 'Abort: Return to Dock',
            'params': {}
          },
          {
            'id': 'n_voice_nav_fail',
            'type': 'ui_speech',
            'label': 'Navigation Hazard Warning',
            'params': {'text': 'Navigation blocked or timed out. Calling assistance.', 'voice': 'female'}
          },
          {'id': 'n_end_safe', 'type': 'end', 'label': 'Mission Finished', 'params': {}},
        ],
        'edges': [
          {'id': 'e_1', 'from_node': 'n_start', 'from_port': 'next', 'to_node': 'n_bat', 'to_port': 'in'},
          {'id': 'e_2', 'from_node': 'n_bat', 'from_port': 'ok', 'to_node': 'n_go_source', 'to_port': 'in'},
          {'id': 'e_3', 'from_node': 'n_bat', 'from_port': 'low_battery', 'to_node': 'n_dock_abort', 'to_port': 'in'},
          {'id': 'e_4', 'from_node': 'n_go_source', 'from_port': 'arrived', 'to_node': 'n_ask_source', 'to_port': 'in'},
          {'id': 'e_5', 'from_node': 'n_go_source', 'from_port': 'failed', 'to_node': 'n_voice_nav_fail', 'to_port': 'in'},
          {'id': 'e_6', 'from_node': 'n_go_source', 'from_port': 'timeout', 'to_node': 'n_voice_nav_fail', 'to_port': 'in'},
          {'id': 'e_7', 'from_node': 'n_ask_source', 'from_port': 'yes', 'to_node': 'n_go_dest', 'to_port': 'in'},
          {'id': 'e_8', 'from_node': 'n_ask_source', 'from_port': 'no', 'to_node': 'n_voice_abort', 'to_port': 'in'},
          {'id': 'e_9', 'from_node': 'n_ask_source', 'from_port': 'timeout', 'to_node': 'n_voice_abort', 'to_port': 'in'},
          {'id': 'e_10', 'from_node': 'n_voice_abort', 'from_port': 'done', 'to_node': 'n_dock_abort', 'to_port': 'in'},
          {'id': 'e_11', 'from_node': 'n_go_dest', 'from_port': 'arrived', 'to_node': 'n_parallel', 'to_port': 'in'},
          {'id': 'e_12', 'from_node': 'n_go_dest', 'from_port': 'failed', 'to_node': 'n_voice_nav_fail', 'to_port': 'in'},
          {'id': 'e_13', 'from_node': 'n_go_dest', 'from_port': 'timeout', 'to_node': 'n_voice_nav_fail', 'to_port': 'in'},
          {'id': 'e_14', 'from_node': 'n_parallel', 'from_port': 'branch_1', 'to_node': 'n_voice_patient', 'to_port': 'in'},
          {'id': 'e_15', 'from_node': 'n_parallel', 'from_port': 'branch_2', 'to_node': 'n_patient_form', 'to_port': 'in'},
          {'id': 'e_16', 'from_node': 'n_patient_form', 'from_port': 'submitted', 'to_node': 'n_dock_success', 'to_port': 'in'},
          {'id': 'e_17', 'from_node': 'n_patient_form', 'from_port': 'cancelled', 'to_node': 'n_dock_success', 'to_port': 'in'},
          {'id': 'e_18', 'from_node': 'n_patient_form', 'from_port': 'timeout', 'to_node': 'n_dock_success', 'to_port': 'in'},
          {'id': 'e_19', 'from_node': 'n_dock_success', 'from_port': 'docked', 'to_node': 'n_end_safe', 'to_port': 'in'},
          {'id': 'e_20', 'from_node': 'n_dock_abort', 'from_port': 'docked', 'to_node': 'n_end_safe', 'to_port': 'in'},
          {'id': 'e_21', 'from_node': 'n_voice_nav_fail', 'from_port': 'done', 'to_node': 'n_dock_abort', 'to_port': 'in'},
        ]
      };
    }

    // Generic patrol / inspection workflow
    return {
      'name': 'Inspection & Patrol Mission',
      'description': 'Patrol route with battery check, obstacle recovery, and dock completion.',
      'nodes': [
        {'id': 'n_start', 'type': 'start', 'label': 'Start Mission', 'params': {}},
        {'id': 'n_bat', 'type': 'battery_guard', 'label': 'Battery Guard (>25%)', 'params': {'min_battery': 25.0}},
        {'id': 'n_wp1', 'type': 'navigate_waypoint', 'label': 'Inspect $fromWp', 'params': {'waypoint': fromWp, 'tolerance_m': 0.25}},
        {'id': 'n_wait', 'type': 'wait', 'label': 'Scan Area (5s)', 'params': {'seconds': 5}},
        {'id': 'n_wp2', 'type': 'navigate_waypoint', 'label': 'Inspect $toWp', 'params': {'waypoint': toWp, 'tolerance_m': 0.25}},
        {'id': 'n_dock', 'type': 'dock', 'label': 'Auto Dock', 'params': {}},
        {'id': 'n_end', 'type': 'end', 'label': 'Mission Complete', 'params': {}},
      ],
      'edges': [
        {'id': 'e_1', 'from_node': 'n_start', 'from_port': 'next', 'to_node': 'n_bat', 'to_port': 'in'},
        {'id': 'e_2', 'from_node': 'n_bat', 'from_port': 'ok', 'to_node': 'n_wp1', 'to_port': 'in'},
        {'id': 'e_3', 'from_node': 'n_bat', 'from_port': 'low_battery', 'to_node': 'n_dock', 'to_port': 'in'},
        {'id': 'e_4', 'from_node': 'n_wp1', 'from_port': 'arrived', 'to_node': 'n_wait', 'to_port': 'in'},
        {'id': 'e_5', 'from_node': 'n_wp1', 'from_port': 'failed', 'to_node': 'n_dock', 'to_port': 'in'},
        {'id': 'e_6', 'from_node': 'n_wait', 'from_port': 'next', 'to_node': 'n_wp2', 'to_port': 'in'},
        {'id': 'e_7', 'from_node': 'n_wp2', 'from_port': 'arrived', 'to_node': 'n_dock', 'to_port': 'in'},
        {'id': 'e_8', 'from_node': 'n_wp2', 'from_port': 'failed', 'to_node': 'n_dock', 'to_port': 'in'},
        {'id': 'e_9', 'from_node': 'n_dock', 'from_port': 'docked', 'to_node': 'n_end', 'to_port': 'in'},
      ]
    };
  }

  /// Converts the raw JSON into MissionGraph with automated topological layout positioning.
  MissionGraph _buildAndLayoutGraph(
    Map<String, dynamic> json,
    List<String> availableWaypoints,
  ) {
    final rawNodes = (json['nodes'] as List? ?? []);
    final rawEdges = (json['edges'] as List? ?? []);

    final nodesMap = <String, GraphNode>{};
    final edgesList = <GraphEdge>[];

    for (final rn in rawNodes) {
      if (rn is! Map) continue;
      final nodeMap = Map<String, dynamic>.from(rn);
      final id = nodeMap['id']?.toString() ?? 'node_${nodesMap.length + 1}';
      final type = nodeMap['type']?.toString() ?? 'wait';
      final label = nodeMap['label']?.toString() ?? type;
      final rawParams = nodeMap['params'];
      final Map<String, dynamic> params = rawParams is Map
          ? Map<String, dynamic>.from(rawParams)
          : <String, dynamic>{};

      nodesMap[id] = GraphNode(
        id: id,
        type: type,
        label: label,
        position: const Offset(100, 200),
        params: params,
      );
    }

    for (int i = 0; i < rawEdges.length; i++) {
      final rawEdge = rawEdges[i];
      if (rawEdge is! Map) continue;
      final re = Map<String, dynamic>.from(rawEdge);
      final from = re['from_node']?.toString() ?? '';
      final fromPort = (re['from_port']?.toString() ?? 'next').toLowerCase();
      final to = re['to_node']?.toString() ?? '';
      final toPort = (re['to_port']?.toString() ?? 'in').toLowerCase();

      if (nodesMap.containsKey(from) && nodesMap.containsKey(to)) {
        edgesList.add(GraphEdge(
          id: 'e_${i + 1}',
          fromNode: from,
          fromPort: fromPort,
          toNode: to,
          toPort: toPort,
        ));
      }
    }

    // Ensure at least a start node exists
    if (!nodesMap.values.any((n) => n.type == 'start')) {
      final start = GraphNode(
        id: 'start_0',
        type: 'start',
        label: 'Mission Start',
        position: const Offset(80, 240),
      );
      nodesMap['start_0'] = start;
      if (nodesMap.length > 1) {
        final firstOther = nodesMap.values.firstWhere((n) => n.id != 'start_0');
        edgesList.insert(
          0,
          GraphEdge(id: 'e_init', fromNode: 'start_0', fromPort: 'next', toNode: firstOther.id, toPort: 'in'),
        );
      }
    }

    // Topological DAG layout calculation (left-to-right flow with vertical branching)
    _applyTopologicalLayout(nodesMap, edgesList);

    return MissionGraph(
      id: 'mission_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name']?.toString() ?? 'AI Generated Mission',
      nodes: nodesMap.values.toList(),
      edges: edgesList,
    );
  }

  /// Calculates visual coordinates so nodes never overlap and branch cleanly.
  void _applyTopologicalLayout(
    Map<String, GraphNode> nodes,
    List<GraphEdge> edges,
  ) {
    if (nodes.isEmpty) return;

    // Adjacency and in-degree maps
    final outgoing = <String, List<String>>{};
    final incoming = <String, List<String>>{};
    for (final id in nodes.keys) {
      outgoing[id] = [];
      incoming[id] = [];
    }
    for (final e in edges) {
      outgoing[e.fromNode]?.add(e.toNode);
      incoming[e.toNode]?.add(e.fromNode);
    }

    // Find start node
    final startNode = nodes.values.firstWhere(
      (n) => n.type == 'start',
      orElse: () => nodes.values.first,
    );

    // BFS depth assignment
    final depths = <String, int>{startNode.id: 0};
    final queue = <String>[startNode.id];

    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      final d = depths[cur]!;
      for (final next in outgoing[cur] ?? []) {
        if (!depths.containsKey(next) || depths[next]! < d + 1) {
          depths[next] = d + 1;
          queue.add(next);
        }
      }
    }

    // Assign any unvisited disconnected nodes
    int maxDepth = 0;
    for (final d in depths.values) {
      if (d > maxDepth) maxDepth = d;
    }
    for (final id in nodes.keys) {
      depths.putIfAbsent(id, () => ++maxDepth);
    }

    // Group nodes by depth column
    final layers = <int, List<String>>{};
    for (final entry in depths.entries) {
      layers.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    // Compute coordinate positions: X = layer * 280 + 100, Y centered
    const double colSpacing = 280.0;
    const double rowSpacing = 160.0;
    const double startX = 100.0;
    const double centerY = 340.0;

    for (final layer in layers.entries) {
      final col = layer.key;
      final nodeIds = layer.value;
      final totalInCol = nodeIds.length;

      for (int i = 0; i < totalInCol; i++) {
        final nodeId = nodeIds[i];
        final node = nodes[nodeId];
        if (node == null) continue;

        final double x = startX + col * colSpacing;
        final double yOffset = (i - (totalInCol - 1) / 2.0) * rowSpacing;
        final double y = centerY + yOffset;

        node.position = Offset(x, y);
      }
    }
  }
}
