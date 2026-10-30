import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/fade_in.dart';

class AiVoiceSettingsScreen extends StatefulWidget {
  final String? robotIp;
  const AiVoiceSettingsScreen({super.key, this.robotIp});

  @override
  State<AiVoiceSettingsScreen> createState() => _AiVoiceSettingsScreenState();
}

class _AiVoiceSettingsScreenState extends State<AiVoiceSettingsScreen> {
  late SdkApiService _api;
  final _groqController = TextEditingController();
  final _geminiController = TextEditingController();

  bool _initialized = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _obscureGroq = true;
  bool _obscureGemini = true;

  String _modelPref = 'groq';
  bool _groqConfigured = false;
  String _groqMaskedKey = '';
  bool _geminiConfigured = false;
  String _geminiMaskedKey = '';
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final conn = context.read<ConnectionProvider>();
      final ip = widget.robotIp ?? conn.robot?.ip ?? '192.168.0.128';
      _api = SdkApiService(ip);
      _loadConfig();
    }
  }

  @override
  void dispose() {
    _groqController.dispose();
    _geminiController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final config = await _api.getVoiceConfig();
      if (!mounted) return;

      setState(() {
        _groqConfigured = config['groq_configured'] == true;
        _groqMaskedKey = (config['groq_masked_key'] ?? '').toString();
        _geminiConfigured = config['gemini_configured'] == true;
        _geminiMaskedKey = (config['gemini_masked_key'] ?? '').toString();
        _modelPref = (config['model_preference'] ?? 'groq').toString();
        _isLoading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not fetch voice settings from robot: $err';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    final newGroq = _groqController.text.trim();
    final newGemini = _geminiController.text.trim();

    try {
      await _api.setVoiceConfig(
        groqApiKey: newGroq.isNotEmpty ? newGroq : null,
        geminiApiKey: newGemini.isNotEmpty ? newGemini : null,
        modelPreference: _modelPref,
      );

      _groqController.clear();
      _geminiController.clear();
      await _loadConfig();

      messenger.showSnackBar(
        const SnackBar(
          content: Text('✓ AI Assistant settings saved securely on robot hardware!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (err) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: $err'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testAgentVoice() async {
    setState(() => _isTesting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final res = await _api.sendVoiceChat(
        'Hello NavPro, confirm voice assistant is active and operational.',
        speak: true,
      );
      final reply = res['reply'] ?? 'Voice replied successfully.';
      messenger.showSnackBar(
        SnackBar(
          content: Text('🤖 Robot Replied: "$reply"'),
          backgroundColor: Colors.blueAccent,
        ),
      );
    } catch (err) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Test speech failed: $err'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Widget _buildEngineOption({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _modelPref == id;
    final colors = AppColors.of(context);

    return InkWell(
      onTap: () => setState(() => _modelPref = id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : colors.border.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: isSelected ? color : colors.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 6),
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Voice Assistant & Models'),
        actions: [
          IconButton(
            tooltip: 'Reload configuration',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadConfig,
          ),
        ],
      ),
      body: SafeArea(
        child: CenteredFormColumn(
          maxWidth: isDesktop ? 680 : 540,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : FadeSlideIn(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      // Hero Card
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colors.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.psychology_rounded,
                                  color: colors.primary,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Conversational Voice Agent',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Low-latency tool calling with speech barge-in and ambient noise filtering',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.red),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.red, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      // Section 1: Active Model Preference
                      Text(
                        'Voice Intelligence Engine',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: colors.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            children: [
                              _buildEngineOption(
                                id: 'groq',
                                title: 'Groq LLaMA 3.3 70B (Recommended)',
                                subtitle: 'Ultra-fast (~180ms TTFT), telephony agent style with native tool calling. 14,400 free requests/day.',
                                icon: Icons.bolt_rounded,
                                color: Colors.amber.shade700,
                              ),
                              _buildEngineOption(
                                id: 'gemini',
                                title: 'Google Gemini 2.0 Flash',
                                subtitle: 'Fast multimodal reasoning and function calling. 1,500 free requests/day.',
                                icon: Icons.auto_awesome_rounded,
                                color: Colors.purple.shade400,
                              ),
                              _buildEngineOption(
                                id: 'local',
                                title: 'Offline Local Engine',
                                subtitle: 'Zero cloud dependency: Google STT fallback + local keyword commands.',
                                icon: Icons.lan_rounded,
                                color: Colors.blueGrey,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Section 2: Groq API Key
                      Text(
                        'Groq Cloud API Key',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (_groqConfigured)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green),
                              ),
                              child: Text(
                                'ACTIVE: $_groqMaskedKey',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: const Text(
                                'NOT CONFIGURED',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _groqController,
                        obscureText: _obscureGroq,
                        decoration: InputDecoration(
                          hintText: _groqConfigured ? 'Leave empty to keep existing key' : 'Paste gsk_...',
                          prefixIcon: const Icon(Icons.vpn_key_rounded, size: 20),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(_obscureGroq ? Icons.visibility_off : Icons.visibility, size: 20),
                                onPressed: () => setState(() => _obscureGroq = !_obscureGroq),
                              ),
                              IconButton(
                                tooltip: 'Paste from clipboard',
                                icon: const Icon(Icons.content_paste_rounded, size: 20),
                                onPressed: () async {
                                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                                  if (data?.text != null) {
                                    _groqController.text = data!.text!.trim();
                                  }
                                },
                              ),
                            ],
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Powers Whisper Turbo STT (<150ms transcription) & LLaMA 3.3. Get a free key at console.groq.com.',
                        style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Section 3: Gemini API Key
                      Text(
                        'Google Gemini API Key',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (_geminiConfigured)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green),
                              ),
                              child: Text(
                                'ACTIVE: $_geminiMaskedKey',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: const Text(
                                'NOT CONFIGURED',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _geminiController,
                        obscureText: _obscureGemini,
                        decoration: InputDecoration(
                          hintText: _geminiConfigured ? 'Leave empty to keep existing key' : 'Paste AIza...',
                          prefixIcon: const Icon(Icons.vpn_key_rounded, size: 20),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(_obscureGemini ? Icons.visibility_off : Icons.visibility, size: 20),
                                onPressed: () => setState(() => _obscureGemini = !_obscureGemini),
                              ),
                              IconButton(
                                tooltip: 'Paste from clipboard',
                                icon: const Icon(Icons.content_paste_rounded, size: 20),
                                onPressed: () async {
                                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                                  if (data?.text != null) {
                                    _geminiController.text = data!.text!.trim();
                                  }
                                },
                              ),
                            ],
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Powers Gemini 2.0 Flash reasoning and tool calling. Get a free key at aistudio.google.com.',
                        style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Section 4: Security Card
                      Card(
                        elevation: 0,
                        color: colors.primary.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: colors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.shield_rounded, color: colors.primary, size: 22),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Keys are stored directly on robot hardware at /home/navpromini/.config/navpro/voice_config.json with chmod 0600 permissions. Plaintext keys are never returned over network APIs.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textPrimary,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Section 5: Enabled Tools Chip Wrap
                      Text(
                        'Enabled Autonomous Robot Tools',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: const [
                          Chip(label: Text('⚡ dock_robot', style: TextStyle(fontSize: 11))),
                          Chip(label: Text('⚡ undock_robot', style: TextStyle(fontSize: 11))),
                          Chip(label: Text('⚡ emergency_stop', style: TextStyle(fontSize: 11))),
                          Chip(label: Text('⚡ navigate_to_road_node', style: TextStyle(fontSize: 11))),
                          Chip(label: Text('⚡ get_robot_telemetry', style: TextStyle(fontSize: 11))),
                          Chip(label: Text('⚡ ignore_background_speech', style: TextStyle(fontSize: 11))),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // Section 6: Action Buttons
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_rounded, size: 20),
                          label: Text(
                            _isSaving ? 'Saving to Robot...' : 'Save Settings to Robot',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          onPressed: _isSaving ? null : _saveConfig,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          icon: _isTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.volume_up_rounded, size: 18),
                          label: Text(
                            _isTesting ? 'Testing Speech...' : 'Test Robot Voice Talkback',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed: _isTesting ? null : _testAgentVoice,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
