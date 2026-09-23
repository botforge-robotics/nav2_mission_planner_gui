import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../services/ai_mission_agent_service.dart';
import '../../../theme/app_theme.dart';
import 'ai_agent_settings_dialog.dart';
import 'mission_graph_models.dart';

/// Floating AI Mission Assistant widget docked in the bottom-right corner
/// of the Mission Graph Editor. Supports both text typing and microphone voice input
/// backed by high-accuracy AI Voice Models (Groq Whisper / OpenAI Whisper) and Device Native.
/// Fully styled with NavPro Mini's light, modern autonomous robotics design tokens.
class AiMissionAssistantWidget extends StatefulWidget {
  const AiMissionAssistantWidget({
    super.key,
    required this.availableWaypoints,
    required this.onGraphGenerated,
    this.existingGraph,
  });

  final List<String> availableWaypoints;
  final ValueChanged<MissionGraph> onGraphGenerated;
  final MissionGraph? existingGraph;

  @override
  State<AiMissionAssistantWidget> createState() => _AiMissionAssistantWidgetState();
}

class _AiMissionAssistantWidgetState extends State<AiMissionAssistantWidget> {
  late final TextEditingController _promptController;
  late final FocusNode _focusNode;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final _MissionAudioRecorder _audioRecorder = _MissionAudioRecorder();
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isTranscribingVoice = false;
  String? _voiceEngineLabel;
  String? _activeAudioPath;

  bool _isExpanded = false;
  bool _isGenerating = false;
  String? _statusMessage;
  bool _isError = false;

  bool _isAiConfigured = false;
  AiAgentConfig? _aiConfig;

  final List<String> _quickPrompts = [
    'Go to pharmacy, ask if room 102 medicines are ready, if yes deliver to room 102 and collect feedback with voice, if no return to dock',
    'Patrol Reception, Lab, and Nurse Station in a loop with 20% battery guard and dock on low battery',
    'Navigate to Room 101, display patient questionnaire form, announce arrival, then return to dock',
  ];

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
    _promptController.addListener(() {
      if (mounted) setState(() {});
    });
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _initSpeech();
    _checkAiConfig();
  }

  Future<void> _checkAiConfig() async {
    final cfg = await AiMissionAgentService.instance.getConfig();
    if (mounted) {
      setState(() {
        _aiConfig = cfg;
        _isAiConfigured = cfg.isConfigured;
      });
    }
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (val) {
          debugPrint('[SpeechToText] Error: $val');
          if (mounted) setState(() => _isListening = false);
        },
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[SpeechToText] Init error: $e');
    }
  }

  Future<void> _toggleListening() async {
    if (!_isAiConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('AI is not configured. Please add an API key or select a local provider in Settings.'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(label: 'Settings', onPressed: _openSettings),
          ),
        );
      }
      return;
    }
    final cfg = await AiMissionAgentService.instance.getConfig();
    final isCloudWhisper = cfg.voiceProvider != VoiceTranscriptionProvider.deviceNative;

    if (isCloudWhisper) {
      await _toggleWhisperVoice(cfg);
    } else {
      await _toggleNativeSpeech();
    }
  }

  Future<void> _toggleWhisperVoice(AiAgentConfig cfg) async {
    if (_isListening) {
      // User tapped mic to stop recording and start transcription
      try {
        final path = (await _audioRecorder.stop()) ?? _activeAudioPath;
        if (mounted) {
          setState(() {
            _isListening = false;
            _isTranscribingVoice = true;
          });
        }

        if (path != null && File(path).existsSync()) {
          final transcribed = await AiMissionAgentService.instance.transcribeAudio(audioPath: path);
          if (mounted && transcribed.isNotEmpty) {
            final current = _promptController.text.trim();
            _promptController.text = current.isEmpty ? transcribed : '$current $transcribed';
            _promptController.selection = TextSelection.fromPosition(
              TextPosition(offset: _promptController.text.length),
            );
          }
          try {
            await File(path).delete();
          } catch (_) {}
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Whisper transcription error: $e'),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Settings',
                onPressed: _openSettings,
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isTranscribingVoice = false);
      }
    } else {
      // User tapped mic to start recording
      try {
        final tempDirPath = Directory.systemTemp.path;
        final path = '$tempDirPath/prompt_${DateTime.now().millisecondsSinceEpoch}.wav';
        _activeAudioPath = path;

        await _audioRecorder.start(path: path);

        if (mounted) {
          setState(() {
            _isListening = true;
            _voiceEngineLabel = cfg.voiceProvider.shortName;
          });
        }
      } catch (e) {
        debugPrint('[AudioRecorder] Start error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Audio recorder could not start ($e). Falling back to native speech recognition.'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        await _toggleNativeSpeech();
      }
    }
  }

  Future<void> _toggleNativeSpeech() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
    } else {
      if (!_speechAvailable) {
        _speechAvailable = await _speech.initialize();
      }
      if (_speechAvailable) {
        setState(() {
          _isListening = true;
          _voiceEngineLabel = 'Native Speech';
        });
        await _speech.listen(
          onResult: (result) {
            if (mounted) {
              setState(() {
                _promptController.text = result.recognizedWords;
                _promptController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _promptController.text.length),
                );
              });
            }
          },
          listenOptions: stt.SpeechListenOptions(
            listenFor: const Duration(seconds: 60),
            pauseFor: const Duration(seconds: 4),
            localeId: 'en_US',
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Microphone / speech recognition is not available. Please type your prompt or use Groq/OpenAI Whisper.'),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Settings',
                onPressed: _openSettings,
              ),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _audioRecorder.dispose();
    _promptController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _generateMission() async {
    final text = _promptController.text.trim();
    if (text.isEmpty) return;

    if (!_isAiConfigured) {
      _openSettings();
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }

    setState(() {
      _isGenerating = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final graph = await AiMissionAgentService.instance.generateMissionGraph(
        userPrompt: text,
        availableWaypoints: widget.availableWaypoints,
        existingGraph: widget.existingGraph,
      );

      if (mounted) {
        widget.onGraphGenerated(graph);
        setState(() {
          _isGenerating = false;
          _statusMessage = 'Generated "${graph.name}" (${graph.nodes.length} nodes, ${graph.edges.length} edges) with safety guards.';
          _isError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _statusMessage = 'Generation error: $e';
          _isError = true;
        });
      }
    }
  }

  Future<void> _openSettings() async {
    await AiAgentSettingsDialog.show(context);
    await _checkAiConfig();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isExpanded) {
      return _buildCollapsedButton();
    }
    return _buildExpandedCard();
  }

  Widget _buildCollapsedButton() {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: _isAiConfigured
                ? AppColors.primary.withValues(alpha: 0.35)
                : const Color(0xFFF59E0B).withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowTint.withValues(alpha: 0.12),
              blurRadius: 16,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _isExpanded = true),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _isAiConfigured
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : const Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: _isAiConfigured ? AppColors.primary : const Color(0xFFD97706),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'AI Workflow Assistant (Preview)',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: _isAiConfigured
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _isAiConfigured ? 'PREVIEW' : 'NOT CONFIGURED',
                        style: TextStyle(
                          color: _isAiConfigured ? AppColors.primary : const Color(0xFFD97706),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Quick Mic Button on pill
            Tooltip(
              message: _isAiConfigured
                  ? 'Speak prompt (Voice Input)'
                  : 'AI not configured — tap to configure in Settings',
              child: InkWell(
                onTap: () {
                  if (_isAiConfigured) {
                    setState(() => _isExpanded = true);
                    _toggleListening();
                  } else {
                    _openSettings();
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _isAiConfigured
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.surfaceSunken,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isAiConfigured ? Icons.mic_none_rounded : Icons.mic_off_outlined,
                    color: _isAiConfigured ? AppColors.primary : AppColors.textTertiary,
                    size: 16,
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: () => setState(() => _isExpanded = true),
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(2, 10, 12, 10),
                child: Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.textSecondary, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedCard() {
    final screenWidth = MediaQuery.maybeOf(context)?.size.width ?? 500;
    final cardWidth = (screenWidth < 520 ? screenWidth - 32 : 480.0).clamp(320.0, 500.0);
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.border, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowTint.withValues(alpha: 0.14),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.cardRadius)),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome, color: AppColors.primary, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text(
                                'AI Workflow Assistant',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _isAiConfigured
                                    ? AppColors.success.withValues(alpha: 0.12)
                                    : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isAiConfigured
                                      ? AppColors.success.withValues(alpha: 0.3)
                                      : const Color(0xFFF59E0B).withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: _isAiConfigured ? AppColors.success : const Color(0xFFD97706),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isAiConfigured
                                        ? (_aiConfig?.provider.displayName ?? 'Ready')
                                        : 'Not Configured',
                                    style: TextStyle(
                                      color: _isAiConfigured ? AppColors.success : const Color(0xFFB45309),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        const Text(
                          'Preview version — review synthesized nodes and safety fallbacks before execution',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Settings Button
                  Tooltip(
                    message: 'AI Provider & Credentials',
                    child: IconButton(
                      icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      splashRadius: 18,
                      onPressed: _openSettings,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Minimize Button
                  Tooltip(
                    message: 'Minimize',
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      splashRadius: 18,
                      onPressed: () => setState(() => _isExpanded = false),
                    ),
                  ),
                ],
              ),
            ),

            // Content Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Prominent configuration warning banner when AI is unconfigured
                  if (!_isAiConfigured)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'AI Provider Not Configured',
                                  style: TextStyle(
                                    color: Color(0xFF92400E),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Text input, mic, and workflow generation are disabled until an AI provider or API key is set up in Settings.',
                                  style: TextStyle(
                                    color: Color(0xFFB45309),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _openSettings,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: const Icon(Icons.settings, size: 14),
                            label: const Text('Configure', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),

                  // Suggestions / Quick Prompts
                  Row(
                    children: const [
                      Icon(Icons.lightbulb_outline, size: 13, color: AppColors.textSecondary),
                      SizedBox(width: 4),
                      Text(
                        'SAMPLE AMR WORKFLOWS',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 30,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _quickPrompts.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, i) {
                        final p = _quickPrompts[i];
                        final label = i == 0
                            ? '💊 Pharmacy & Room 102'
                            : i == 1
                                ? '🛡️ Patrol Loop + Battery Guard'
                                : '📋 Questionnaire Form';
                        return ActionChip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppColors.surfaceSunken,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          label: Text(
                            label,
                            style: TextStyle(
                              color: _isAiConfigured ? AppColors.textPrimary : AppColors.textTertiary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onPressed: _isAiConfigured
                              ? () {
                                  _promptController.text = p;
                                  _focusNode.requestFocus();
                                }
                              : () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('AI is not configured. Please set up your API key in Settings first.'),
                                      behavior: SnackBarBehavior.floating,
                                      action: SnackBarAction(label: 'Settings', onPressed: _openSettings),
                                    ),
                                  );
                                },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Transcribing active banner
                  if (_isTranscribingVoice)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF93C5FD)),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Transcribing audio with ${_voiceEngineLabel ?? "Whisper AI"} model...',
                              style: const TextStyle(
                                color: Color(0xFF1D4ED8),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Listening active banner
                  if (_isListening)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Recording audio (${_voiceEngineLabel ?? "Voice Model"})... Click stop when finished.',
                              style: const TextStyle(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          InkWell(
                            onTap: _toggleListening,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Stop & Transcribe',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Prompt TextField Container
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                      border: Border.all(
                        color: !_isAiConfigured
                            ? AppColors.border
                            : (_isListening
                                ? AppColors.primary
                                : (_focusNode.hasFocus ? AppColors.primary : AppColors.border)),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _promptController,
                          focusNode: _focusNode,
                          enabled: _isAiConfigured && !_isGenerating,
                          maxLines: 3,
                          minLines: 2,
                          style: TextStyle(
                            color: _isAiConfigured ? AppColors.textPrimary : AppColors.textTertiary,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                          decoration: InputDecoration(
                            hintText: _isAiConfigured
                                ? 'Describe your robot workflow or speak via mic (e.g. Go to pharmacy, ask if room 102 medicines are ready, if yes deliver and collect feedback, if no dock)...'
                                : 'AI is not configured. Add an API key or local model in Settings to enable text prompt, voice mic, and workflow generation.',
                            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
                            contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                            border: InputBorder.none,
                          ),
                        ),
                        // Action row inside input container
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                          child: Row(
                            children: [
                              // Voice Input Toggle Button
                              if (_isTranscribingVoice)
                                FilledButton.icon(
                                  onPressed: null,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.surfaceElevated,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
                                  icon: const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                  ),
                                  label: const Text('Transcribing...', style: TextStyle(fontSize: 11.5, color: AppColors.primary)),
                                )
                              else
                                Tooltip(
                                  message: !_isAiConfigured
                                      ? 'Configure AI in Settings to enable Voice Input'
                                      : (_isListening ? 'Stop recording & transcribe' : 'Voice Input (Microphone)'),
                                  child: _isListening
                                      ? FilledButton.icon(
                                          onPressed: (!_isAiConfigured || _isGenerating) ? null : _toggleListening,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.danger,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            elevation: 0,
                                          ),
                                          icon: const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          ),
                                          label: const Text('Stop & Transcribe', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                        )
                                      : OutlinedButton.icon(
                                          onPressed: (!_isAiConfigured || _isGenerating) ? null : _toggleListening,
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _isAiConfigured ? AppColors.primary : AppColors.textTertiary,
                                            side: BorderSide(
                                              color: _isAiConfigured
                                                  ? AppColors.primary.withValues(alpha: 0.35)
                                                  : AppColors.border,
                                            ),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          icon: Icon(
                                            Icons.mic_none_rounded,
                                            size: 16,
                                            color: _isAiConfigured ? null : AppColors.textTertiary,
                                          ),
                                          label: Text(
                                            'Voice Input',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: _isAiConfigured ? null : AppColors.textTertiary,
                                            ),
                                          ),
                                        ),
                                ),
                              const SizedBox(width: 8),

                              if (_promptController.text.isNotEmpty && _isAiConfigured && !_isGenerating)
                                Tooltip(
                                  message: 'Clear input',
                                  child: InkWell(
                                    onTap: () => setState(() => _promptController.clear()),
                                    borderRadius: BorderRadius.circular(6),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.clear, color: AppColors.textSecondary, size: 16),
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              Tooltip(
                                message: !_isAiConfigured
                                    ? 'Configure AI in Settings to generate workflows'
                                    : (_isGenerating
                                        ? 'Synthesizing mission workflow...'
                                        : (_promptController.text.trim().isEmpty
                                            ? 'Enter a description to generate workflow'
                                            : 'Generate robot workflow')),
                                child: FilledButton.icon(
                                  onPressed: (_isAiConfigured && !_isGenerating && _promptController.text.trim().isNotEmpty)
                                      ? _generateMission
                                      : null,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.25),
                                    disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    elevation: 0,
                                  ),
                                  icon: _isGenerating
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.play_arrow_rounded, size: 18),
                                  label: Text(
                                    _isGenerating ? 'Synthesizing...' : 'Generate Workflow',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Status / Feedback info banner
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: _isError ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isError ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                            color: _isError ? AppColors.danger : AppColors.success,
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: TextStyle(
                                color: _isError ? const Color(0xFF991B1B) : const Color(0xFF166534),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Unified audio recorder that uses ALSA arecord on Linux systems (guaranteeing
/// zero-dependency recording without MissingPluginException or missing ffmpeg/parecord),
/// and falls back to package:record on other mobile/desktop platforms.
class _MissionAudioRecorder {
  Process? _linuxProcess;
  final AudioRecorder _packageRecorder = AudioRecorder();
  bool _usingLinuxProcess = false;

  Future<void> start({required String path}) async {
    if (Platform.isLinux) {
      try {
        _linuxProcess = await Process.start('arecord', [
          '-f', 'S16_LE',
          '-r', '16000',
          '-c', '1',
          path,
        ]);
        _usingLinuxProcess = true;
        return;
      } catch (e) {
        debugPrint('[_MissionAudioRecorder] arecord failed ($e), falling back to package recorder...');
      }
    }

    try {
      final hasPermission = await _packageRecorder.hasPermission();
      if (!hasPermission) {
        throw Exception('Microphone permission denied.');
      }
      await _packageRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _usingLinuxProcess = false;
    } catch (e) {
      if (Platform.isLinux) {
        _linuxProcess = await Process.start('arecord', [
          '-f', 'S16_LE',
          '-r', '16000',
          '-c', '1',
          path,
        ]);
        _usingLinuxProcess = true;
        return;
      }
      rethrow;
    }
  }

  Future<String?> stop() async {
    if (_usingLinuxProcess && _linuxProcess != null) {
      try {
        _linuxProcess!.kill(ProcessSignal.sigint);
        await _linuxProcess!.exitCode.timeout(
          const Duration(milliseconds: 1500),
          onTimeout: () {
            _linuxProcess?.kill();
            return 0;
          },
        );
      } catch (_) {}
      _linuxProcess = null;
      _usingLinuxProcess = false;
      return null;
    } else {
      return await _packageRecorder.stop();
    }
  }

  void dispose() {
    if (_linuxProcess != null) {
      try {
        _linuxProcess!.kill();
      } catch (_) {}
      _linuxProcess = null;
    }
    _packageRecorder.dispose();
  }
}
