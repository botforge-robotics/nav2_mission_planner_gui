import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../services/ai_mission_agent_service.dart';
import '../../../theme/app_theme.dart';

class AiAgentSettingsDialog extends StatefulWidget {
  const AiAgentSettingsDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const AiAgentSettingsDialog(),
    );
  }

  @override
  State<AiAgentSettingsDialog> createState() => _AiAgentSettingsDialogState();
}

class _AiAgentSettingsDialogState extends State<AiAgentSettingsDialog> {
  AiProvider _provider = AiProvider.gemini;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _baseUrlController;

  VoiceTranscriptionProvider _voiceProvider = VoiceTranscriptionProvider.groqWhisper;
  late final TextEditingController _voiceApiKeyController;
  bool _obscureVoiceApiKey = true;
  bool _testingVoiceConnection = false;
  String? _voiceTestResult;
  bool _voiceTestSuccess = false;

  bool _obscureApiKey = true;
  bool _testingConnection = false;
  String? _testResult;
  bool _testSuccess = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _modelController = TextEditingController();
    _baseUrlController = TextEditingController();
    _voiceApiKeyController = TextEditingController();
    _loadConfig();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
    _voiceApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final cfg = await AiMissionAgentService.instance.getConfig();
    if (mounted) {
      setState(() {
        _provider = cfg.provider;
        _apiKeyController.text = cfg.apiKey;
        _modelController.text = cfg.model;
        _baseUrlController.text = cfg.baseUrl;
        _voiceProvider = cfg.voiceProvider;
        _voiceApiKeyController.text = cfg.voiceApiKey;
        _loading = false;
      });
    }
  }

  void _onProviderChanged(AiProvider? provider) {
    if (provider == null) return;
    setState(() {
      _provider = provider;
      _testResult = null;
      final suggestions = provider.defaultModels;
      if (!suggestions.contains(_modelController.text)) {
        _modelController.text = suggestions.first;
      }
      if (provider.defaultBaseUrl.isNotEmpty) {
        _baseUrlController.text = provider.defaultBaseUrl;
      } else {
        _baseUrlController.clear();
      }
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _testResult = null;
    });

    final apiKey = _apiKeyController.text.trim();
    final model = _modelController.text.trim();
    final baseUrl = _baseUrlController.text.trim();

    if (!_provider.isLocal && apiKey.isEmpty) {
      setState(() {
        _testingConnection = false;
        _testSuccess = false;
        _testResult = 'API Key is required for ${_provider.displayName}.';
      });
      return;
    }

    try {
      if (_provider == AiProvider.gemini) {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
        );
        final resp = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': 'Ping test. Reply with "pong" only.'}
                ]
              }
            ],
            'generationConfig': {'maxOutputTokens': 5}
          }),
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          setState(() {
            _testSuccess = true;
            _testResult = 'Connection verified! Google Gemini authenticated successfully.';
          });
        } else {
          setState(() {
            _testSuccess = false;
            _testResult = 'Gemini error (${resp.statusCode}): ${resp.body}';
          });
        }
      } else if (_provider == AiProvider.anthropic) {
        final url = Uri.parse('https://api.anthropic.com/v1/messages');
        final resp = await http.post(
          url,
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model.isNotEmpty ? model : 'claude-3-5-sonnet-20241022',
            'max_tokens': 5,
            'messages': [
              {'role': 'user', 'content': 'Ping test. Reply with "pong".'}
            ],
          }),
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          setState(() {
            _testSuccess = true;
            _testResult = 'Connection verified! Anthropic Claude authenticated successfully.';
          });
        } else {
          setState(() {
            _testSuccess = false;
            _testResult = 'Anthropic error (${resp.statusCode}): ${resp.body}';
          });
        }
      } else if (_provider == AiProvider.cohere) {
        String endpoint = baseUrl.isNotEmpty ? baseUrl : _provider.defaultBaseUrl;
        if (endpoint.endsWith('/')) endpoint = endpoint.substring(0, endpoint.length - 1);
        final url = Uri.parse('$endpoint/chat');

        final resp = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model.isNotEmpty ? model : 'command-r-plus-08-2024',
            'messages': [
              {'role': 'user', 'content': 'Ping test'}
            ],
          }),
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          setState(() {
            _testSuccess = true;
            _testResult = 'Connection verified! Cohere authenticated successfully.';
          });
        } else {
          setState(() {
            _testSuccess = false;
            _testResult = 'Cohere error (${resp.statusCode}): ${resp.body}';
          });
        }
      } else {
        // Universal OpenAI-compatible test (OpenAI, DeepSeek, Groq, OpenRouter, Mistral, xAI, Together, Perplexity, Ollama, LM Studio, Custom)
        String endpoint = baseUrl.isNotEmpty ? baseUrl : _provider.defaultBaseUrl;
        if (endpoint.endsWith('/')) endpoint = endpoint.substring(0, endpoint.length - 1);

        final url = Uri.parse('$endpoint/chat/completions');
        final headers = <String, String>{
          'Content-Type': 'application/json',
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          if (_provider == AiProvider.openrouter) ...{
            'HTTP-Referer': 'https://github.com/botforge-robotics/nav2_mission_planner_gui',
            'X-Title': 'NavPro Mini AMR',
          },
        };

        final testModel = model.isNotEmpty ? model : _provider.defaultModels.first;

        final resp = await http.post(
          url,
          headers: headers,
          body: jsonEncode({
            'model': testModel,
            'messages': [
              {'role': 'user', 'content': 'Ping test. Reply with "pong".'}
            ],
            'max_tokens': 5,
          }),
        ).timeout(const Duration(seconds: 12));

        if (resp.statusCode == 200) {
          setState(() {
            _testSuccess = true;
            _testResult = 'Connection verified! ${_provider.displayName} responded successfully.';
          });
        } else {
          setState(() {
            _testSuccess = false;
            _testResult = '${_provider.displayName} error (${resp.statusCode}): ${resp.body}';
          });
        }
      }
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Connection failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _testingConnection = false);
      }
    }
  }

  Future<void> _testVoiceModel() async {
    setState(() {
      _testingVoiceConnection = true;
      _voiceTestResult = null;
    });

    String apiKey = _voiceApiKeyController.text.trim();
    if (apiKey.isEmpty) {
      if (_voiceProvider == VoiceTranscriptionProvider.groqWhisper && _provider == AiProvider.groq) {
        apiKey = _apiKeyController.text.trim();
      } else if (_voiceProvider == VoiceTranscriptionProvider.openAiWhisper && _provider == AiProvider.openai) {
        apiKey = _apiKeyController.text.trim();
      }
    }

    try {
      final res = await AiMissionAgentService.instance.testVoiceConnection(
        provider: _voiceProvider,
        apiKey: apiKey,
      );
      if (mounted) {
        setState(() {
          _voiceTestSuccess = res['success'] == true;
          _voiceTestResult = res['message'] as String?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _voiceTestSuccess = false;
          _voiceTestResult = 'Voice test error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _testingVoiceConnection = false);
      }
    }
  }

  Future<void> _save() async {
    final cfg = AiAgentConfig(
      provider: _provider,
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      voiceProvider: _voiceProvider,
      voiceApiKey: _voiceApiKeyController.text.trim(),
    );
    await AiMissionAgentService.instance.saveConfig(cfg);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        side: const BorderSide(color: AppColors.border, width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(48),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.cardRadius)),
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.psychology_outlined, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'AI Workflow Assistant Settings',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 1),
                              Text(
                                'Configure LLM provider credentials & voice models for live AMR workflow synthesis',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                          splashRadius: 18,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // Form Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Provider Dropdown
                          const Text(
                            'AI Provider',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSunken,
                              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<AiProvider>(
                                value: _provider,
                                isExpanded: true,
                                dropdownColor: AppColors.surface,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                                onChanged: _onProviderChanged,
                                items: AiProvider.values.map((p) {
                                  return DropdownMenuItem<AiProvider>(
                                    value: p,
                                    child: Row(
                                      children: [
                                        Icon(
                                          p.isLocal
                                              ? Icons.terminal_rounded
                                              : (p == AiProvider.custom
                                                  ? Icons.tune_rounded
                                                  : Icons.cloud_queue_rounded),
                                          size: 16,
                                          color: p.isLocal ? AppColors.accent : AppColors.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(p.displayName),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Model Name Input + Suggestion Chips
                          Row(
                            children: [
                              const Text(
                                'Model Name',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_provider.displayName} models',
                                style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _modelController,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.surfaceSunken,
                              hintText: 'e.g. ${_provider.defaultModels.first}',
                              hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Model suggestion chips
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _provider.defaultModels.map((m) {
                              final isSelected = _modelController.text.trim() == m;
                              return InkWell(
                                onTap: () => setState(() => _modelController.text = m),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary.withValues(alpha: 0.1)
                                        : AppColors.surfaceSunken,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected ? AppColors.primary : AppColors.border,
                                      width: isSelected ? 1.2 : 1.0,
                                    ),
                                  ),
                                  child: Text(
                                    m,
                                    style: TextStyle(
                                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),

                          // API Key Input
                          Row(
                            children: [
                              const Text(
                                'API Key',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_provider.isLocal)
                                const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Text(
                                    '(Optional for local runner)',
                                    style: TextStyle(color: AppColors.textTertiary, fontSize: 11.5),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _apiKeyController,
                            obscureText: _obscureApiKey,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              letterSpacing: 1.1,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.surfaceSunken,
                              hintText: _provider.isLocal ? 'Optional (No API key needed)' : 'sk-... or AIza...',
                              hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13, letterSpacing: 0),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureApiKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: AppColors.textSecondary,
                                  size: 20,
                                ),
                                splashRadius: 18,
                                onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Base URL (Custom or Pre-filled)
                          Row(
                            children: [
                              const Text(
                                'API Base URL',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              if (_provider.defaultBaseUrl.isNotEmpty &&
                                  _baseUrlController.text != _provider.defaultBaseUrl)
                                InkWell(
                                  onTap: () => setState(() => _baseUrlController.text = _provider.defaultBaseUrl),
                                  child: const Text(
                                    'Reset default',
                                    style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _baseUrlController,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.surfaceSunken,
                              hintText: _provider.defaultBaseUrl.isNotEmpty
                                  ? _provider.defaultBaseUrl
                                  : 'https://api.example.com/v1',
                              hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Voice AI Section
                          const Divider(height: 36, thickness: 1, color: AppColors.border),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.mic_rounded, color: AppColors.primary, size: 18),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Voice Speech-to-Text Model',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Select the speech recognition model used when speaking voice mission prompts.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          const SizedBox(height: 12),

                          // Voice Model Dropdown
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSunken,
                              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<VoiceTranscriptionProvider>(
                                value: _voiceProvider,
                                isExpanded: true,
                                icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                dropdownColor: AppColors.surfaceElevated,
                                items: VoiceTranscriptionProvider.values.map((v) {
                                  return DropdownMenuItem<VoiceTranscriptionProvider>(
                                    value: v,
                                    child: Row(
                                      children: [
                                        Icon(
                                          v == VoiceTranscriptionProvider.deviceNative
                                              ? Icons.phone_android_rounded
                                              : Icons.auto_awesome_rounded,
                                          size: 16,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            v.displayName,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _voiceProvider = val;
                                      _voiceTestResult = null;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Voice Provider description
                          Text(
                            _voiceProvider.description,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.3),
                          ),

                          if (_voiceProvider != VoiceTranscriptionProvider.deviceNative) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Text(
                                  '${_voiceProvider == VoiceTranscriptionProvider.groqWhisper ? "Groq" : "OpenAI"} Voice API Key',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  (_voiceProvider == VoiceTranscriptionProvider.groqWhisper && _provider == AiProvider.groq) ||
                                          (_voiceProvider == VoiceTranscriptionProvider.openAiWhisper && _provider == AiProvider.openai)
                                      ? 'Using primary key'
                                      : 'Separate key optional',
                                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _voiceApiKeyController,
                              obscureText: _obscureVoiceApiKey,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, letterSpacing: 0.5),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppColors.surfaceSunken,
                                hintText: (_voiceProvider == VoiceTranscriptionProvider.groqWhisper && _provider == AiProvider.groq) ||
                                        (_voiceProvider == VoiceTranscriptionProvider.openAiWhisper && _provider == AiProvider.openai)
                                    ? 'Leave blank to use primary AI Provider key'
                                    : 'Enter dedicated Whisper API key',
                                hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12, letterSpacing: 0),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureVoiceApiKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    color: AppColors.textSecondary,
                                    size: 20,
                                  ),
                                  splashRadius: 18,
                                  onPressed: () => setState(() => _obscureVoiceApiKey = !_obscureVoiceApiKey),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Test Voice Button
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 34),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  foregroundColor: AppColors.textPrimary,
                                  side: const BorderSide(color: AppColors.border),
                                ),
                                icon: _testingVoiceConnection
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                      )
                                    : const Icon(Icons.record_voice_over_rounded, size: 16, color: AppColors.primary),
                                label: Text(
                                  _testingVoiceConnection ? 'Verifying Voice...' : 'Test Voice Model API',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onPressed: _testingVoiceConnection ? null : _testVoiceModel,
                              ),
                            ),
                            if (_voiceTestResult != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _voiceTestSuccess ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _voiceTestSuccess ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _voiceTestSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                                      color: _voiceTestSuccess ? AppColors.success : AppColors.danger,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _voiceTestResult!,
                                        style: TextStyle(
                                          color: _voiceTestSuccess ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 18),

                          // Offline Guard Container
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F9FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFBAE6FD)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Icon(Icons.info_outline_rounded, color: Color(0xFF0284C7), size: 18),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Offline Guard: If no API key is provided or the robot is offline, the agent automatically activates the built-in deterministic mission synthesizer with full safety fail-safes.',
                                    style: TextStyle(color: Color(0xFF0369A1), fontSize: 12, height: 1.35),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Test Connection Outcome Banner
                          if (_testResult != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _testSuccess ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _testSuccess ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _testSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                                    color: _testSuccess ? AppColors.success : AppColors.danger,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _testResult!,
                                      style: TextStyle(
                                        color: _testSuccess ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Actions
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppSpacing.cardRadius)),
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _testingConnection ? null : _testConnection,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.borderStrong),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
                          ),
                          icon: _testingConnection
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                )
                              : const Icon(Icons.network_check_outlined, size: 16),
                          label: Text(_testingConnection ? 'Testing...' : 'Test Connection'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
                            elevation: 0,
                          ),
                          child: const Text('Save Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
