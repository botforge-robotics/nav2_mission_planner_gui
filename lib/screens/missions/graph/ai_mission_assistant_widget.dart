import 'package:flutter/material.dart';
import '../../../services/ai_mission_agent_service.dart';
import '../../../theme/app_theme.dart';
import 'ai_agent_settings_dialog.dart';
import 'mission_graph_models.dart';

/// Floating AI Mission Assistant widget docked in the bottom-right corner
/// of the Mission Graph Editor. Takes human natural language workflows
/// and synthesizes nodes, connections, and properties live onto the canvas.
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

class _AiMissionAssistantWidgetState extends State<AiMissionAssistantWidget> with SingleTickerProviderStateMixin {
  late final TextEditingController _promptController;
  late final FocusNode _focusNode;

  bool _isExpanded = false;
  bool _isGenerating = false;
  String? _statusMessage;
  bool _isError = false;

  final List<String> _quickPrompts = [
    'Go to pharmacy, ask if room 102 medicines are ready, if yes deliver to room 102 and collect feedback with voice in parallel, if no return to dock',
    'Patrol Reception, Lab, and Nurse Station in a loop with 20% battery guard and dock on low battery',
    'Navigate to Room 101, display patient questionnaire form, announce arrival, then return to dock',
  ];

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _generateMission() async {
    final text = _promptController.text.trim();
    if (text.isEmpty) return;

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

  void _openSettings() {
    AiAgentSettingsDialog.show(context);
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
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = true),
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E222D), Color(0xFF262C3D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 14,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome, color: AppColors.primaryLight, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'AI Mission Agent',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'PROMPT',
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_up, color: Color(0xFF94A3B8), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedCard() {
    return Material(
      color: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black87,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 440,
        decoration: BoxDecoration(
          color: const Color(0xFF1B1F2A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF333B4F), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF222736),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Color(0xFF2F374B))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome, color: AppColors.primaryLight, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'AI Mission Architect',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Settings Button
                  Tooltip(
                    message: 'AI Provider & API Key Settings',
                    child: IconButton(
                      icon: const Icon(Icons.settings_outlined, color: Color(0xFFCBD5E1), size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: _openSettings,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Minimize Button
                  Tooltip(
                    message: 'Minimize',
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF94A3B8), size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => setState(() => _isExpanded = false),
                    ),
                  ),
                ],
              ),
            ),

            // Content Body
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Suggestions / Quick Prompts
                  const Text(
                    'Quick Templates:',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 28,
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
                          backgroundColor: const Color(0xFF272D3E),
                          side: const BorderSide(color: Color(0xFF384259)),
                          label: Text(
                            label,
                            style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11),
                          ),
                          onPressed: () {
                            _promptController.text = p;
                            _focusNode.requestFocus();
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Prompt TextField
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF12151D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _focusNode.hasFocus ? AppColors.primary : const Color(0xFF2C3446),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _promptController,
                          focusNode: _focusNode,
                          maxLines: 3,
                          minLines: 2,
                          style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
                          decoration: InputDecoration(
                            hintText: 'Describe mission in English (e.g. Go to pharmacy, ask for medicines for room 102, if yes give patient and take feedback, if no dock)...',
                            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: InputBorder.none,
                          ),
                        ),
                        // Action row inside input container
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Row(
                            children: [
                              if (_promptController.text.isNotEmpty)
                                Tooltip(
                                  message: 'Clear input',
                                  child: InkWell(
                                    onTap: () => setState(() => _promptController.clear()),
                                    borderRadius: BorderRadius.circular(6),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.clear, color: Color(0xFF64748B), size: 16),
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _isGenerating ? null : _generateMission,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: _isGenerating
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.play_arrow_rounded, size: 18),
                                label: Text(
                                  _isGenerating ? 'Synthesizing...' : 'Build Mission',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
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
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isError
                            ? const Color(0xFF7F1D1D).withValues(alpha: 0.5)
                            : const Color(0xFF064E3B).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isError ? const Color(0xFFDC2626) : const Color(0xFF059669),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _isError ? Icons.error_outline : Icons.check_circle_outline,
                            color: _isError ? const Color(0xFFF87171) : const Color(0xFF34D399),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: TextStyle(
                                color: _isError ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
                                fontSize: 11.5,
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
