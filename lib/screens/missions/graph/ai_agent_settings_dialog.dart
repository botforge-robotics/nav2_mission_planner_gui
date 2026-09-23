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

  bool _obscureApiKey = true;
  bool _testingConnection = false;
  String? _testResult;
  bool _testSuccess = false;
  bool _loading = true;

  final Map<AiProvider, List<String>> _modelSuggestions = {
    AiProvider.gemini: ['gemini-1.5-flash', 'gemini-1.5-pro', 'gemini-2.0-flash-exp'],
    AiProvider.openai: ['gpt-4o-mini', 'gpt-4o', 'gpt-3.5-turbo'],
    AiProvider.anthropic: ['claude-3-5-sonnet-20241022', 'claude-3-haiku-20240307'],
    AiProvider.ollama: ['llama3.2', 'llama3', 'mistral', 'qwen2.5:7b'],
    AiProvider.custom: ['custom-model'],
  };

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _modelController = TextEditingController();
    _baseUrlController = TextEditingController();
    _loadConfig();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
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
        _loading = false;
      });
    }
  }

  void _onProviderChanged(AiProvider? provider) {
    if (provider == null) return;
    setState(() {
      _provider = provider;
      _testResult = null;
      final suggestions = _modelSuggestions[provider] ?? ['default'];
      if (!suggestions.contains(_modelController.text)) {
        _modelController.text = suggestions.first;
      }
      if (provider == AiProvider.ollama && _baseUrlController.text.isEmpty) {
        _baseUrlController.text = 'http://localhost:11434/v1';
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

    if (_provider != AiProvider.ollama && apiKey.isEmpty) {
      setState(() {
        _testingConnection = false;
        _testSuccess = false;
        _testResult = 'API Key is required for ${_provider.name.toUpperCase()}.';
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
            _testResult = 'Connection verified! Gemini API authenticated successfully.';
          });
        } else {
          setState(() {
            _testSuccess = false;
            _testResult = 'Gemini error (${resp.statusCode}): ${resp.body}';
          });
        }
      } else if (_provider == AiProvider.openai || _provider == AiProvider.custom || _provider == AiProvider.ollama) {
        String endpoint = baseUrl;
        if (endpoint.isEmpty) {
          endpoint = _provider == AiProvider.ollama ? 'http://localhost:11434/v1' : 'https://api.openai.com/v1';
        }
        if (endpoint.endsWith('/')) endpoint = endpoint.substring(0, endpoint.length - 1);

        final url = Uri.parse('$endpoint/chat/completions');
        final headers = <String, String>{
          'Content-Type': 'application/json',
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        };

        final resp = await http.post(
          url,
          headers: headers,
          body: jsonEncode({
            'model': model.isNotEmpty ? model : 'gpt-4o-mini',
            'messages': [
              {'role': 'user', 'content': 'Ping test. Reply with "pong".'}
            ],
            'max_tokens': 5,
          }),
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          setState(() {
            _testSuccess = true;
            _testResult = 'Connection verified! ${_provider.name.toUpperCase()} responded successfully.';
          });
        } else {
          setState(() {
            _testSuccess = false;
            _testResult = 'Provider error (${resp.statusCode}): ${resp.body}';
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

  Future<void> _save() async {
    final cfg = AiAgentConfig(
      provider: _provider,
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
    );
    await AiMissionAgentService.instance.saveConfig(cfg);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E222D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2E3547)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.psychology_outlined, color: AppColors.primaryLight, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'AI Mission Agent Settings',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Configure LLM agent API credentials for live workflow synthesis',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 32, thickness: 1, color: Color(0xFF2E3547)),

                    // Provider Dropdown
                    const Text(
                      'AI Provider',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF13161F),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2E3547)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<AiProvider>(
                          value: _provider,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E222D),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          onChanged: _onProviderChanged,
                          items: const [
                            DropdownMenuItem(
                              value: AiProvider.gemini,
                              child: Text('Google Gemini (Flash / Pro)'),
                            ),
                            DropdownMenuItem(
                              value: AiProvider.openai,
                              child: Text('OpenAI (GPT-4o / GPT-4o-mini)'),
                            ),
                            DropdownMenuItem(
                              value: AiProvider.anthropic,
                              child: Text('Anthropic (Claude 3.5 Sonnet)'),
                            ),
                            DropdownMenuItem(
                              value: AiProvider.ollama,
                              child: Text('Ollama (Local LLM - Llama/Mistral/Qwen)'),
                            ),
                            DropdownMenuItem(
                              value: AiProvider.custom,
                              child: Text('Custom OpenAI-Compatible Endpoint'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Model Name Input + Suggestion Chips
                    const Text(
                      'Model Name',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _modelController,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF13161F),
                        hintText: 'e.g. gemini-1.5-flash, gpt-4o-mini',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2E3547)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2E3547)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primaryLight),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Model suggestion chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: (_modelSuggestions[_provider] ?? []).map((m) {
                        final isSelected = _modelController.text.trim() == m;
                        return InkWell(
                          onTap: () => setState(() => _modelController.text = m),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.3)
                                  : const Color(0xFF272C3D),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected ? AppColors.primaryLight : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              m,
                              style: TextStyle(
                                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
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
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        if (_provider == AiProvider.ollama)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Text(
                              '(Optional for local Ollama)',
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: _obscureApiKey,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5, letterSpacing: 1.1),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF13161F),
                        hintText: _provider == AiProvider.ollama ? 'Optional' : 'sk-... or AIza...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13, letterSpacing: 0),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureApiKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: const Color(0xFF94A3B8),
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2E3547)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2E3547)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primaryLight),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Custom Base URL (For Ollama or Custom)
                    if (_provider == AiProvider.ollama ||
                        _provider == AiProvider.custom ||
                        _provider == AiProvider.openai) ...[
                      const Text(
                        'API Base URL',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _baseUrlController,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF13161F),
                          hintText: _provider == AiProvider.ollama
                              ? 'http://localhost:11434/v1'
                              : 'https://api.openai.com/v1',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF2E3547)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF2E3547)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.primaryLight),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Info / Offline fallback note
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF13161F),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2E3547)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(Icons.info_outline, color: Color(0xFF38BDF8), size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Offline Guard: If no API key is set or no internet is available, the agent automatically uses the built-in deterministic mission synthesizer with full safety checks.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Test connection outcome
                    if (_testResult != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _testSuccess
                              ? const Color(0xFF064E3B).withValues(alpha: 0.6)
                              : const Color(0xFF7F1D1D).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _testSuccess ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _testSuccess ? Icons.check_circle_outline : Icons.error_outline,
                              color: _testSuccess ? const Color(0xFF34D399) : const Color(0xFFF87171),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _testResult!,
                                style: TextStyle(
                                  color: _testSuccess ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Actions
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _testingConnection ? null : _testConnection,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF3B445B)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          icon: _testingConnection
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.network_check_outlined, size: 16),
                          label: Text(_testingConnection ? 'Testing...' : 'Test Connection'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          child: const Text('Save Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
