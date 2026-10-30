import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';

/// Live Voice Assistant Screen providing:
/// - Real-time acoustic waveform animation (CustomPainter)
/// - Left: Robot conversational bubbles with cute robot avatar & action tag
/// - Right: User speech bubbles with user avatar
/// - One prominent Header Action Button to toggle agent Listen or Mute
/// - Direct Push-to-Talk / Tap-to-Speak microphone capture
/// - Quick robot action chips (Dock, Undock, Road Node 1, Battery, Stop)
class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({super.key, required this.robotIp});

  final String robotIp;

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen>
    with SingleTickerProviderStateMixin {
  late final SdkApiService _api;
  late final AnimationController _waveController;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _isMuted = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _loading = false;
  String _statusMessage = 'Ready to listen';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _api = SdkApiService(widget.robotIp);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _fetchDialog();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchDialog());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _waveController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchDialog() async {
    try {
      final res = await _api.getVoiceDialog();
      if (!mounted) return;
      setState(() {
        _isMuted = res['muted'] == true;
        _isListening = res['listening'] == true;
        final list = res['messages'] as List?;
        if (list != null) {
          _messages = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      });
      _scrollToBottom();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleMute() async {
    try {
      final res = await _api.toggleVoiceMute();
      if (!mounted) return;
      setState(() {
        _isMuted = res['muted'] == true;
        _statusMessage = _isMuted ? 'Agent Muted' : 'Agent Listening';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isMuted ? 'Microphone muted' : 'Microphone active and listening'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to toggle mute: $e')),
      );
    }
  }

  Future<void> _triggerListen() async {
    if (_isMuted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent is muted. Unmute to listen.')),
      );
      return;
    }
    if (_isListening || _loading) return;

    setState(() {
      _isListening = true;
      _loading = true;
      _statusMessage = 'Listening for 4 seconds...';
    });

    try {
      final res = await _api.triggerVoiceListen(durationSec: 4.0, autoReply: true);
      if (!mounted) return;

      setState(() {
        _isListening = false;
        _loading = false;
        final st = res['status']?.toString();
        if (st == 'success') {
          _statusMessage = 'Heard speech successfully';
          _isSpeaking = true;
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _isSpeaking = false);
          });
        } else if (st == 'silence') {
          _statusMessage = 'No speech detected (ambient noise)';
        } else {
          _statusMessage = 'Listening complete';
        }
      });
      await _fetchDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _loading = false;
        _statusMessage = 'Recognition error: $e';
      });
    }
  }

  Future<void> _sendText([String? customText]) async {
    final text = (customText ?? _textController.text).trim();
    if (text.isEmpty) return;

    _textController.clear();
    setState(() {
      _statusMessage = 'Processing command...';
      _loading = true;
    });

    try {
      await _api.sendVoiceChat(text, speak: true);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMessage = 'Agent replied';
        _isSpeaking = true;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _isSpeaking = false);
      });
      await _fetchDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMessage = 'Error sending message: $e';
      });
    }
  }

  Future<void> _clearDialog() async {
    try {
      await _api.clearVoiceDialog();
      await _fetchDialog();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Live Voice Assistant',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
              'Acoustic Mic & Autonomous Voice Control',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
        actions: [
          // One Header Button to make agent Listen or Mute
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _toggleMute,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _isMuted
                      ? colors.danger.withOpacity(0.12)
                      : colors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isMuted ? colors.danger : colors.success,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      size: 16,
                      color: _isMuted ? colors.danger : colors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isMuted ? 'Muted' : 'Listening',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _isMuted ? colors.danger : colors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear Chat History',
            onPressed: _clearDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Waveform Visualizer Card
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.graphic_eq_rounded,
                              size: 16, color: colors.primary),
                          const SizedBox(width: 6),
                          Text(
                            'ACOUSTIC WAVEFORM (BOTTOM MIC)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colors.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _isListening
                              ? colors.success.withOpacity(0.15)
                              : (_isMuted
                                  ? colors.danger.withOpacity(0.12)
                                  : colors.surfaceSunken),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _statusMessage,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _isListening
                                ? colors.success
                                : (_isMuted ? colors.danger : colors.textSecondary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 60,
                    width: double.infinity,
                    child: AnimatedBuilder(
                      animation: _waveController,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _VoiceWaveformPainter(
                            phase: _waveController.value * 2 * math.pi,
                            isListening: _isListening,
                            isSpeaking: _isSpeaking,
                            isMuted: _isMuted,
                            primaryColor: colors.primary,
                            successColor: colors.success,
                            dangerColor: colors.danger,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Chat Dialogs (Left: Robot, Right: User)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                ),
                child: _messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet. Tap "Tap to Speak" or type below.',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isRobot = msg['sender'] == 'robot';
                          final text = msg['text']?.toString() ?? '';
                          final action = msg['action']?.toString();

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: isRobot
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (isRobot) ...[
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: colors.primary,
                                    child: const Icon(Icons.smart_toy_outlined,
                                        size: 18, color: Colors.white),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isRobot
                                          ? colors.surfaceSunken
                                          : colors.primary,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: Radius.circular(isRobot ? 2 : 16),
                                        bottomRight: Radius.circular(isRobot ? 16 : 2),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: isRobot
                                          ? CrossAxisAlignment.start
                                          : CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          text,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isRobot
                                                ? colors.textPrimary
                                                : colors.textOnPrimary,
                                          ),
                                        ),
                                        if (action != null && action.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: colors.border,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '⚡ $action',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: colors.textPrimary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                if (!isRobot) ...[
                                  const SizedBox(width: 8),
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: colors.success,
                                    child: const Icon(Icons.person_rounded,
                                        size: 18, color: Colors.white),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),

            // Quick Command Chips
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildChip('⚡ Dock', 'Dock the robot', colors),
                    _buildChip('🚀 Undock', 'Undock', colors),
                    _buildChip('🛣️ Node 1', 'Go to Node 1', colors),
                    _buildChip('🛣️ Node 2', 'Go to Node 2', colors),
                    _buildChip('🔋 Battery', 'What is your battery level?', colors),
                    _buildChip('🛑 Stop', 'Stop navigation', colors, isDanger: true),
                  ],
                ),
              ),
            ),

            // Bottom Input & Tap-to-Talk Action Bar
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isListening ? colors.danger : colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _triggerListen,
                    icon: Icon(
                      _isListening ? Icons.hearing_rounded : Icons.mic_rounded,
                      size: 20,
                    ),
                    label: Text(
                      _isListening ? 'Listening…' : 'Tap to Speak',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: "Say or type 'dock', 'go to node 1'…",
                        hintStyle: TextStyle(fontSize: 13, color: colors.textTertiary),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        filled: true,
                        fillColor: colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: colors.border),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.send_rounded),
                          onPressed: () => _sendText(),
                        ),
                      ),
                      onSubmitted: (_) => _sendText(),
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

  Widget _buildChip(String label, String command, AppColorsTheme colors,
      {bool isDanger = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        backgroundColor: isDanger ? colors.danger.withOpacity(0.1) : colors.surface,
        side: BorderSide(color: isDanger ? colors.danger : colors.border),
        onPressed: () => _sendText(command),
      ),
    );
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  _VoiceWaveformPainter({
    required this.phase,
    required this.isListening,
    required this.isSpeaking,
    required this.isMuted,
    required this.primaryColor,
    required this.successColor,
    required this.dangerColor,
  });

  final double phase;
  final bool isListening;
  final bool isSpeaking;
  final bool isMuted;
  final Color primaryColor;
  final Color successColor;
  final Color dangerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final width = size.width;

    double amp = 4.0;
    Color strokeColor = primaryColor.withOpacity(0.6);

    if (isMuted) {
      amp = 1.0;
      strokeColor = dangerColor.withOpacity(0.5);
    } else if (isListening) {
      amp = 18.0;
      strokeColor = successColor;
    } else if (isSpeaking) {
      amp = 15.0;
      strokeColor = primaryColor;
    }

    final path = Path();
    for (double x = 0; x <= width; x += 3) {
      final norm = (x / width) * math.pi * 3;
      final env = math.sin((x / width) * math.pi); // Window envelope
      final y = centerY + math.sin(norm + phase) * amp * env;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.isListening != isListening ||
        oldDelegate.isSpeaking != isSpeaking ||
        oldDelegate.isMuted != isMuted;
  }
}
