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
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        side: const BorderSide(color: AppColors.border, width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
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
                                'AI Mission Agent Settings',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 1),
                              Text(
                                'Configure LLM agent API credentials for live workflow synthesis',
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
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _modelController,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.surfaceSunken,
                              hintText: 'e.g. gemini-1.5-flash, gpt-4o-mini',
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
                            children: (_modelSuggestions[_provider] ?? []).map((m) {
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
                              if (_provider == AiProvider.ollama)
                                const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Text(
                                    '(Optional for local Ollama)',
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
                              hintText: _provider == AiProvider.ollama ? 'Optional' : 'sk-... or AIza...',
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

                          // Custom Base URL (For Ollama or Custom)
                          if (_provider == AiProvider.ollama ||
                              _provider == AiProvider.custom ||
                              _provider == AiProvider.openai) ...[
                            const Text(
                              'API Base URL',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _baseUrlController,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppColors.surfaceSunken,
                                hintText: _provider == AiProvider.ollama
                                    ? 'http://localhost:11434/v1'
                                    : 'https://api.openai.com/v1',
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
                          ],

                          // Info / Offline fallback note
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
                                    'Offline Guard: If no API key is set or no internet is available, the agent automatically uses the built-in deterministic mission synthesizer with full safety checks.',
                                    style: TextStyle(color: Color(0xFF0369A1), fontSize: 12, height: 1.35),
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
