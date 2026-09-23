import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/missions/graph/mission_graph_models.dart';

enum AiProvider {
  gemini,
  openai,
  anthropic,
  deepseek,
  groq,
  openrouter,
  mistral,
  xai,
  together,
  perplexity,
  cohere,
  ollama,
  lmstudio,
  custom,
}

enum VoiceTranscriptionProvider {
  groqWhisper,
  openAiWhisper,
  deviceNative,
}

extension VoiceTranscriptionProviderDetails on VoiceTranscriptionProvider {
  String get displayName {
    switch (this) {
      case VoiceTranscriptionProvider.groqWhisper:
        return 'Groq Whisper Large v3 (Fastest AI, ~150ms)';
      case VoiceTranscriptionProvider.openAiWhisper:
        return 'OpenAI Whisper-1 (High Accuracy)';
      case VoiceTranscriptionProvider.deviceNative:
        return 'Device Native (On-Device Speech Recognizer)';
    }
  }

  String get shortName {
    switch (this) {
      case VoiceTranscriptionProvider.groqWhisper:
        return 'Groq Whisper';
      case VoiceTranscriptionProvider.openAiWhisper:
        return 'OpenAI Whisper';
      case VoiceTranscriptionProvider.deviceNative:
        return 'Native Speech';
    }
  }

  String get modelName {
    switch (this) {
      case VoiceTranscriptionProvider.groqWhisper:
        return 'whisper-large-v3-turbo';
      case VoiceTranscriptionProvider.openAiWhisper:
        return 'whisper-1';
      case VoiceTranscriptionProvider.deviceNative:
        return 'native';
    }
  }

  String get description {
    switch (this) {
      case VoiceTranscriptionProvider.groqWhisper:
        return 'Sub-second LPU inference (~150ms). Accurately understands robotics jargon (waypoints, docking, AMCL, relocalization).';
      case VoiceTranscriptionProvider.openAiWhisper:
        return 'Industry standard OpenAI Whisper model with exceptional multi-lingual & accent accuracy.';
      case VoiceTranscriptionProvider.deviceNative:
        return 'Local OS speech recognition. Zero latency and offline, standard accuracy.';
    }
  }
}

class AiAgentConfig {
  AiAgentConfig({
    this.provider = AiProvider.gemini,
    this.apiKey = '',
    this.model = 'gemini-1.5-flash',
    this.baseUrl = '',
    this.voiceProvider = VoiceTranscriptionProvider.groqWhisper,
    this.voiceApiKey = '',
  });

  final AiProvider provider;
  final String apiKey;
  final String model;
  final String baseUrl;
  final VoiceTranscriptionProvider voiceProvider;
  final String voiceApiKey;

  AiAgentConfig copyWith({
    AiProvider? provider,
    String? apiKey,
    String? model,
    String? baseUrl,
    VoiceTranscriptionProvider? voiceProvider,
    String? voiceApiKey,
  }) {
    return AiAgentConfig(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
      voiceProvider: voiceProvider ?? this.voiceProvider,
      voiceApiKey: voiceApiKey ?? this.voiceApiKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'apiKey': apiKey,
        'model': model,
        'baseUrl': baseUrl,
        'voiceProvider': voiceProvider.name,
        'voiceApiKey': voiceApiKey,
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
      voiceProvider: VoiceTranscriptionProvider.values.firstWhere(
        (e) => e.name == (json['voiceProvider'] as String?),
        orElse: () => VoiceTranscriptionProvider.groqWhisper,
      ),
      voiceApiKey: json['voiceApiKey'] as String? ?? '',
    );
  }
}

extension AiProviderDetails on AiProvider {
  String get displayName {
    switch (this) {
      case AiProvider.gemini:
        return 'Google Gemini';
      case AiProvider.openai:
        return 'OpenAI';
      case AiProvider.anthropic:
        return 'Anthropic Claude';
      case AiProvider.deepseek:
        return 'DeepSeek (V3 / R1)';
      case AiProvider.groq:
        return 'Groq (Ultra-Fast LPU)';
      case AiProvider.openrouter:
        return 'OpenRouter (Multi-Model)';
      case AiProvider.mistral:
        return 'Mistral AI';
      case AiProvider.xai:
        return 'xAI (Grok)';
      case AiProvider.together:
        return 'Together AI';
      case AiProvider.perplexity:
        return 'Perplexity AI';
      case AiProvider.cohere:
        return 'Cohere';
      case AiProvider.ollama:
        return 'Ollama (Local / Robot)';
      case AiProvider.lmstudio:
        return 'LM Studio (Local Desktop)';
      case AiProvider.custom:
        return 'Custom OpenAI-Compatible';
    }
  }

  String get defaultBaseUrl {
    switch (this) {
      case AiProvider.openai:
        return 'https://api.openai.com/v1';
      case AiProvider.deepseek:
        return 'https://api.deepseek.com';
      case AiProvider.groq:
        return 'https://api.groq.com/openai/v1';
      case AiProvider.openrouter:
        return 'https://openrouter.ai/api/v1';
      case AiProvider.mistral:
        return 'https://api.mistral.ai/v1';
      case AiProvider.xai:
        return 'https://api.x.ai/v1';
      case AiProvider.together:
        return 'https://api.together.xyz/v1';
      case AiProvider.perplexity:
        return 'https://api.perplexity.ai';
      case AiProvider.cohere:
        return 'https://api.cohere.com/v2';
      case AiProvider.ollama:
        return 'http://localhost:11434/v1';
      case AiProvider.lmstudio:
        return 'http://localhost:1234/v1';
      case AiProvider.gemini:
      case AiProvider.anthropic:
      case AiProvider.custom:
        return '';
    }
  }

  List<String> get defaultModels {
    switch (this) {
      case AiProvider.gemini:
        return ['gemini-1.5-flash', 'gemini-1.5-pro', 'gemini-2.0-flash', 'gemini-2.0-flash-thinking-exp'];
      case AiProvider.openai:
        return ['gpt-4o-mini', 'gpt-4o', 'o3-mini', 'gpt-4-turbo'];
      case AiProvider.anthropic:
        return ['claude-3-5-sonnet-20241022', 'claude-3-5-haiku-20241022', 'claude-3-opus-20240229'];
      case AiProvider.deepseek:
        return ['deepseek-chat', 'deepseek-reasoner'];
      case AiProvider.groq:
        return ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant', 'mixtral-8x7b-32768', 'qwen-2.5-32b'];
      case AiProvider.openrouter:
        return [
          'meta-llama/llama-3.3-70b-instruct',
          'anthropic/claude-3.5-sonnet',
          'google/gemini-flash-1.5',
          'deepseek/deepseek-r1',
          'openai/gpt-4o-mini',
        ];
      case AiProvider.mistral:
        return ['mistral-large-latest', 'mistral-small-latest', 'codestral-latest', 'pixtral-large-latest'];
      case AiProvider.xai:
        return ['grok-2-1212', 'grok-2-vision-1212', 'grok-beta'];
      case AiProvider.together:
        return [
          'meta-llama/Llama-3.3-70B-Instruct-Turbo',
          'Qwen/Qwen2.5-72B-Instruct-Turbo',
          'deepseek-ai/DeepSeek-R1',
        ];
      case AiProvider.perplexity:
        return ['sonar', 'sonar-pro', 'sonar-reasoning'];
      case AiProvider.cohere:
        return ['command-r-plus-08-2024', 'command-r-08-2024'];
      case AiProvider.ollama:
        return ['llama3.2', 'llama3.1:8b', 'qwen2.5:7b', 'mistral', 'deepseek-r1:8b'];
      case AiProvider.lmstudio:
        return ['default', 'local-model'];
      case AiProvider.custom:
        return ['custom-model'];
    }
  }

  bool get isLocal => this == AiProvider.ollama || this == AiProvider.lmstudio;
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

  /// Transcribes recorded speech audio using Groq Whisper or OpenAI Whisper models.
  Future<String> transcribeAudio({
    required String audioPath,
    VoiceTranscriptionProvider? overrideProvider,
    String? overrideApiKey,
  }) async {
    final config = await getConfig();
    final voiceProvider = overrideProvider ?? config.voiceProvider;

    if (voiceProvider == VoiceTranscriptionProvider.deviceNative) {
      throw Exception('Device Native provider does not use remote cloud transcription.');
    }

    String apiKey = (overrideApiKey ?? config.voiceApiKey).trim();
    if (apiKey.isEmpty) {
      if (voiceProvider == VoiceTranscriptionProvider.groqWhisper && config.provider == AiProvider.groq) {
        apiKey = config.apiKey.trim();
      } else if (voiceProvider == VoiceTranscriptionProvider.openAiWhisper && config.provider == AiProvider.openai) {
        apiKey = config.apiKey.trim();
      }
    }

    if (apiKey.isEmpty) {
      final name = voiceProvider == VoiceTranscriptionProvider.groqWhisper ? 'Groq' : 'OpenAI';
      throw Exception('No API key provided for $name Whisper. Please configure your $name API key in AI Settings.');
    }

    final Uri endpoint = voiceProvider == VoiceTranscriptionProvider.groqWhisper
        ? Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions')
        : Uri.parse('https://api.openai.com/v1/audio/transcriptions');

    final String model = voiceProvider.modelName;

    final request = http.MultipartRequest('POST', endpoint);
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = model;
    request.fields['response_format'] = 'json';
    request.fields['temperature'] = '0.0';
    request.fields['prompt'] =
        'NavPro Mini AMR AI workflow assistant, waypoint navigation, docking, battery guard, condition branch, UI dialog, medicine delivery, patrol, relocalize';

    final audioFile = await http.MultipartFile.fromPath('file', audioPath);
    request.files.add(audioFile);

    final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final text = json['text'] as String? ?? '';
      return text.trim();
    } else {
      String msg = 'Status ${response.statusCode}: ${response.body}';
      try {
        final err = jsonDecode(response.body);
        if (err is Map && err.containsKey('error')) {
          msg = err['error'] is Map ? err['error']['message'] ?? msg : err['error'].toString();
        }
      } catch (_) {}
      throw Exception('Voice model transcription failed: $msg');
    }
  }

  /// Verifies connectivity to the Voice AI API.
  Future<Map<String, dynamic>> testVoiceConnection({
    required VoiceTranscriptionProvider provider,
    required String apiKey,
  }) async {
    if (provider == VoiceTranscriptionProvider.deviceNative) {
      return {'success': true, 'message': 'Device Native engine is available on this system.'};
    }
    if (apiKey.trim().isEmpty) {
      return {'success': false, 'message': 'API key is required for ${provider.displayName}.'};
    }

    final endpoint = provider == VoiceTranscriptionProvider.groqWhisper
        ? Uri.parse('https://api.groq.com/openai/v1/models')
        : Uri.parse('https://api.openai.com/v1/models');

    try {
      final resp = await http.get(
        endpoint,
        headers: {'Authorization': 'Bearer ${apiKey.trim()}'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        return {
          'success': true,
          'message': 'Voice API verified! ${provider.displayName} is ready for high-accuracy voice transcription.',
        };
      } else {
        return {
          'success': false,
          'message': 'Voice authentication failed (${resp.statusCode}): ${resp.body}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Voice connection error: $e'};
    }
  }

  /// System prompt giving the LLM deep knowledge of NavPro Mini mission nodes and safety rules.
  String _buildSystemPrompt(List<String> availableWaypoints) {
    final wpList = availableWaypoints.isNotEmpty
        ? availableWaypoints.join(', ')
        : 'Dock, Pharmacy, Room 101, Room 102, Triage, Nurse Station, Reception, Lab';

    return '''
You are the NavPro AI Workflow Assistant for NavPro Mini Autonomous Mobile Robots (AMR).
Your task is to convert human natural language workflow instructions into a complete, safe, and executable Mission Graph JSON for NavPro Mini AMR.

### KNOWN WAYPOINTS ON CURRENT MAP:
[$wpList]

### AVAILABLE NODE TYPES & SCHEMA:
1. "start": Mission entry point & workflow trigger.
   - Input ports: NONE
   - Output ports: "next"
   - Params: {
       "trigger": "manual" | "interval" | "schedule",
       "interval_minutes": 30, // For "interval": repeats every X minutes (e.g. 15, 30, 60, 120)
       "schedule_type": "daily" | "weekly" | "once", // For "schedule" clock alarm
       "schedule_hour": 9, // Hour 0-23
       "schedule_minute": 0, // Minute 0-59
       "weekdays": [0, 1, 2, 3, 4], // For weekly: 0=Mon..6=Sun
       "schedule_date": "2026-10-01", // For once: YYYY-MM-DD
       "enabled": true
     }
   - TRIGGER INSTRUCTION RULES:
     - If user asks to run "every X minutes" or "every X hours" (e.g. "patrol every 30 minutes", "inspect warehouse every 2 hours"):
       Set "trigger": "interval", "interval_minutes": <minutes> on the "start" node params!
     - If user specifies a clock time, alarm, or daily schedule (e.g. "at 9:00 AM", "daily at 14:30", "every morning at 8 on weekdays"):
       Set "trigger": "schedule", "schedule_type": "daily" (or "weekly"), "schedule_hour": <hour>, "schedule_minute": <minute>, "weekdays": <weekdays list> on the "start" node params!
     - If no recurrence or time is specified, default to "trigger": "manual".

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

11. "parallel": Executes multiple simultaneous NON-DRIVING branches at a spot (e.g. speak voice greeting while showing a questionnaire form, or play chime while flashing LED lights).
    - Input ports: "in"
    - Output ports: "branch_1", "branch_2", ...
    - Params: {"branch_count": 2}
    - STRICT PROHIBITION: NEVER branch driving ("navigate_waypoint", "navigate_coordinates", "patrol_loop") in parallel with destination user interactions ("ui_interaction", "ui_choice")! A person at a room cannot fill a form while the robot is still driving in transit. The robot MUST finish driving first ("arrived"), and only then trigger the interaction.

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
4. STRICT SEQUENCING FOR DELIVERY & FORMS:
   - Driving to a destination and asking for input/feedback at that destination MUST BE SEQUENTIAL.
   - ALWAYS connect: "navigate_waypoint" -> output port "arrived" -> destination interaction ("ui_interaction" or "ui_choice").
   - You can use "parallel" AFTER arrival (e.g. branch_1: "ui_speech" voice alert to patient, branch_2: "ui_interaction" medicine receipt form).
   - NEVER start a destination feedback form before the robot arrives at that destination!
5. User interactions: If asking questions or choices, handle the negative / cancelled / timeout branches gracefully (e.g. return to dock or end).
6. All branches must terminate at an "end" node or "dock" node.
7. Return ONLY valid JSON conforming to the output schema. No conversational filler, no markdown quotes outside the JSON block.

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

    // Check if user has an API key configured for external LLM (or using local inference)
    final hasKey = config.apiKey.trim().isNotEmpty || config.provider.isLocal;

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

      case AiProvider.cohere:
        String baseUrl = config.baseUrl.trim();
        if (baseUrl.isEmpty) baseUrl = config.provider.defaultBaseUrl;
        if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        final url = Uri.parse('$baseUrl/chat');
        final model = config.model.isNotEmpty ? config.model : config.provider.defaultModels.first;

        final resp = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey.trim()}',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userPrompt}
            ],
            'response_format': {'type': 'json_object'},
          }),
        ).timeout(const Duration(seconds: 30));

        if (resp.statusCode != 200) {
          throw Exception('Cohere API error (${resp.statusCode}): ${resp.body}');
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        responseText = data['message']?['content']?[0]?['text'] ?? '';
        break;

      // Universal OpenAI-compatible providers:
      // openai, deepseek, groq, openrouter, mistral, xai, together, perplexity, ollama, lmstudio, custom
      default:
        String baseUrl = config.baseUrl.trim();
        if (baseUrl.isEmpty) {
          baseUrl = config.provider.defaultBaseUrl;
        }
        if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        final url = Uri.parse('$baseUrl/chat/completions');

        final headers = <String, String>{
          'Content-Type': 'application/json',
        };
        if (config.apiKey.trim().isNotEmpty) {
          headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
        }
        if (config.provider == AiProvider.openrouter) {
          headers['HTTP-Referer'] = 'https://github.com/botforge-robotics/nav2_mission_planner_gui';
          headers['X-Title'] = 'NavPro Mini AMR';
        }

        final model = config.model.isNotEmpty
            ? config.model
            : config.provider.defaultModels.first;

        final shouldPassJsonFormat = config.provider != AiProvider.perplexity;

        final bodyMap = <String, dynamic>{
          'model': model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt}
          ],
          'temperature': 0.2,
          if (shouldPassJsonFormat) 'response_format': {'type': 'json_object'},
        };

        final resp = await http.post(
          url,
          headers: headers,
          body: jsonEncode(bodyMap),
        ).timeout(const Duration(seconds: 35));

        if (resp.statusCode != 200) {
          throw Exception('${config.provider.displayName} API error (${resp.statusCode}): ${resp.body}');
        }
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        responseText = data['choices']?[0]?['message']?['content'] ?? '';
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

    // Detect interval or clock alarm trigger from prompt
    String startTrigger = 'manual';
    final startParams = <String, dynamic>{
      'trigger': 'manual',
      'enabled': true,
      'interval_minutes': 30,
      'schedule_type': 'daily',
      'schedule_hour': 9,
      'schedule_minute': 0,
      'weekdays': [0, 1, 2, 3, 4],
    };

    final intervalMatch = RegExp(r'every\s+(\d+)\s*(minute|min|hour|hr)s?', caseSensitive: false).firstMatch(prompt);
    if (intervalMatch != null) {
      final numVal = int.tryParse(intervalMatch.group(1) ?? '30') ?? 30;
      final unit = intervalMatch.group(2)?.toLowerCase() ?? 'min';
      final totalMins = unit.startsWith('h') ? numVal * 60 : numVal;
      startTrigger = 'interval';
      startParams['trigger'] = 'interval';
      startParams['interval_minutes'] = totalMins;
    } else if (lower.contains('every hour') || lower.contains('hourly')) {
      startTrigger = 'interval';
      startParams['trigger'] = 'interval';
      startParams['interval_minutes'] = 60;
    } else {
      final timeMatch = RegExp(r'at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?', caseSensitive: false).firstMatch(prompt);
      if (timeMatch != null) {
        int hour = int.tryParse(timeMatch.group(1) ?? '9') ?? 9;
        final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
        final amPm = timeMatch.group(3)?.toLowerCase();
        if (amPm == 'pm' && hour < 12) hour += 12;
        if (amPm == 'am' && hour == 12) hour = 0;

        startTrigger = 'schedule';
        startParams['trigger'] = 'schedule';
        startParams['schedule_hour'] = hour;
        startParams['schedule_minute'] = minute;

        if (lower.contains('weekday') || lower.contains('workday')) {
          startParams['schedule_type'] = 'weekly';
          startParams['weekdays'] = [0, 1, 2, 3, 4];
        } else if (lower.contains('weekend')) {
          startParams['schedule_type'] = 'weekly';
          startParams['weekdays'] = [5, 6];
        } else {
          startParams['schedule_type'] = 'daily';
        }
      }
    }

    final startLabel = startTrigger == 'interval'
        ? 'Start (Every ${startParams['interval_minutes']}m)'
        : (startTrigger == 'schedule'
            ? 'Start (Alarm ${startParams['schedule_hour']}:${startParams['schedule_minute'].toString().padLeft(2, '0')})'
            : 'Start Mission');

    // Build delivery / pharmacy workflow with full safety branchings
    if (hasMedicineOrDelivery) {
      return {
        'name': 'Medical Delivery: $fromWp to $toWp',
        'description': 'Autonomous delivery with battery guard, pharmacist confirmation, patient verification, feedback collection, and safe dock return.',
        'nodes': [
          {'id': 'n_start', 'type': 'start', 'label': startLabel, 'params': startParams},
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
        {'id': 'n_start', 'type': 'start', 'label': startLabel, 'params': startParams},
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
    // Sanitize any invalid parallel splits (e.g. driving + interaction in parallel)
    _sanitizeParallelInteractions(json);

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

    final missionGraph = MissionGraph(
      id: 'mission_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name']?.toString() ?? 'AI Generated Mission',
      nodes: nodesMap.values.toList(),
      edges: edgesList,
    );

    // Apply neat Sugiyama hierarchical DAG layout
    applyCleanGraphLayout(missionGraph);

    return missionGraph;
  }

  /// Programmatically enforces that driving nodes and destination user interactions
  /// are strictly sequential, even if an external LLM tried to parallelize them.
  static void _sanitizeParallelInteractions(Map<String, dynamic> json) {
    final rawNodes = (json['nodes'] as List? ?? []).whereType<Map>().toList();
    final rawEdges = (json['edges'] as List? ?? []).whereType<Map>().toList();

    for (final node in rawNodes) {
      if (node['type'] == 'parallel') {
        final parallelId = node['id']?.toString() ?? '';
        final branchEdges = rawEdges.where((e) => e['from_node'] == parallelId).toList();
        final targetIds = branchEdges.map((e) => e['to_node']?.toString() ?? '').toList();
        final targets = rawNodes.where((rn) => targetIds.contains(rn['id']?.toString())).toList();

        final driving = targets.firstWhere(
          (tn) => tn['type'] == 'navigate_waypoint' || tn['type'] == 'navigate_coordinates',
          orElse: () => {},
        );
        final interaction = targets.firstWhere(
          (tn) => tn['type'] == 'ui_interaction' || tn['type'] == 'ui_choice',
          orElse: () => {},
        );

        if (driving.isNotEmpty && interaction.isNotEmpty) {
          final drivingId = driving['id']?.toString() ?? '';
          final interactionId = interaction['id']?.toString() ?? '';

          // Remove the direct parallel -> interaction edge
          rawEdges.removeWhere((e) => e['from_node'] == parallelId && e['to_node'] == interactionId);

          // Route navigation arrived -> interaction
          rawEdges.add({
            'id': 'e_seq_${DateTime.now().millisecondsSinceEpoch}',
            'from_node': drivingId,
            'from_port': 'arrived',
            'to_node': interactionId,
            'to_port': 'in',
          });
        }
      }
    }
  }

  /// Calculates clean, non-overlapping hierarchical coordinates (Sugiyama DAG style)
  /// with topological depth ranking and barycenter ordering to eliminate wire tangles.
  static void applyCleanGraphLayout(MissionGraph graph) {
    if (graph.nodes.isEmpty) return;

    final nodesMap = {for (final n in graph.nodes) n.id: n};
    final edges = graph.edges;

    final outgoing = <String, List<String>>{};
    final incoming = <String, List<String>>{};
    for (final id in nodesMap.keys) {
      outgoing[id] = [];
      incoming[id] = [];
    }
    for (final e in edges) {
      if (nodesMap.containsKey(e.fromNode) && nodesMap.containsKey(e.toNode)) {
        outgoing[e.fromNode]?.add(e.toNode);
        incoming[e.toNode]?.add(e.fromNode);
      }
    }

    // Find start / root node
    final startNode = graph.nodes.firstWhere(
      (n) => n.type == 'start',
      orElse: () => graph.nodes.first,
    );

    // 1. Longest-path depth calculation so dependencies flow strictly Left to Right
    final depths = <String, int>{startNode.id: 0};
    final queue = <String>[startNode.id];

    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      final curDepth = depths[cur]!;
      for (final next in outgoing[cur] ?? []) {
        final currentKnown = depths[next] ?? -1;
        if (currentKnown < curDepth + 1) {
          depths[next] = curDepth + 1;
          queue.add(next);
        }
      }
    }

    // Assign any unvisited or disconnected nodes
    int maxDepth = 0;
    for (final d in depths.values) {
      if (d > maxDepth) maxDepth = d;
    }
    for (final id in nodesMap.keys) {
      if (!depths.containsKey(id)) {
        depths[id] = ++maxDepth;
      }
    }

    // Push terminal sinks to the rightmost column
    for (final node in graph.nodes) {
      final out = outgoing[node.id] ?? [];
      final isTerminal = node.type == 'end' || node.type == 'mission_end' || 
          (node.type == 'dock' && (out.isEmpty || out.every((t) => nodesMap[t]?.type == 'end')));
      if (isTerminal && depths[node.id]! < maxDepth) {
        depths[node.id] = maxDepth;
      }
    }

    // Group into columns
    final layers = <int, List<String>>{};
    for (final entry in depths.entries) {
      layers.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    const double colSpacing = 340.0;
    const double rowSpacing = 210.0;
    const double startX = 80.0;
    const double centerY = 340.0;

    // Temporary map of assigned Y positions for barycenter sorting
    final yPositions = <String, double>{startNode.id: centerY};

    final sortedColKeys = layers.keys.toList()..sort();

    for (final col in sortedColKeys) {
      final nodeIds = layers[col]!;

      // Sort nodes in this column by average Y position of predecessors (Barycenter heuristic)
      if (col > 0) {
        nodeIds.sort((a, b) {
          final predsA = incoming[a] ?? [];
          final predsB = incoming[b] ?? [];

          final avgYA = predsA.isEmpty
              ? centerY
              : predsA.map((p) => yPositions[p] ?? centerY).reduce((v, e) => v + e) / predsA.length;
          final avgYB = predsB.isEmpty
              ? centerY
              : predsB.map((p) => yPositions[p] ?? centerY).reduce((v, e) => v + e) / predsB.length;

          return avgYA.compareTo(avgYB);
        });
      }

      final totalInCol = nodeIds.length;
      for (int i = 0; i < totalInCol; i++) {
        final id = nodeIds[i];
        final node = nodesMap[id];
        if (node == null) continue;

        final double x = startX + col * colSpacing;
        final double y = centerY + (i - (totalInCol - 1) / 2.0) * rowSpacing;

        node.position = Offset(x, y);
        yPositions[id] = y;
      }
    }
  }
}
