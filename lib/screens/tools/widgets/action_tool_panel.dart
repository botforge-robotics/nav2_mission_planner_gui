import 'package:flutter/material.dart';
import 'package:ros2_api/ros2_api.dart';
import '../../../theme/app_spacing.dart';
import 'json_utils.dart';
import 'json_box.dart';

/// Send-goal panel for one action, selected from the Tools screen's
/// Actions tab. Built on `ros2_api`'s [DynamicActionClient] — raw JSON
/// goal/feedback/result, no per-action Dart class needed (the same
/// primitive `DockingService` uses for `/dock`/`/undock`).
class ActionToolPanel extends StatefulWidget {
  final Ros2 ros2;
  final String actionName;
  final String actionType;

  const ActionToolPanel({
    super.key,
    required this.ros2,
    required this.actionName,
    required this.actionType,
  });

  @override
  State<ActionToolPanel> createState() => _ActionToolPanelState();
}

class _ActionToolPanelState extends State<ActionToolPanel> {
  late final TextEditingController _goalController;
  DynamicActionClient? _client;
  bool _sending = false;
  String? _goalError;
  String? _resultText;
  bool? _resultOk;
  final List<Map<String, dynamic>> _feedback = [];

  @override
  void initState() {
    super.initState();
    _goalController = TextEditingController(text: '{}');
  }

  @override
  void didUpdateWidget(covariant ActionToolPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionName != widget.actionName) {
      _client?.cancelGoal();
      _client?.dispose();
      _client = null;
      setState(() {
        _resultText = null;
        _goalError = null;
        _feedback.clear();
        _goalController.text = '{}';
      });
    }
  }

  Future<void> _sendGoal() async {
    final (args, error) = JsonUtils.parseArgs(_goalController.text);
    if (error != null) {
      setState(() => _goalError = error);
      return;
    }
    setState(() {
      _sending = true;
      _goalError = null;
      _resultText = null;
      _resultOk = null;
      _feedback.clear();
    });
    _client = DynamicActionClient(
      ros2: widget.ros2,
      actionName: widget.actionName,
      actionType: widget.actionType,
    );
    try {
      final result = await _client!.send(
        goalArgs: args!,
        onFeedback: (fb) {
          if (!mounted) return;
          setState(() => _feedback.add(fb));
        },
      );
      if (!mounted) return;
      setState(() {
        _resultOk = result != null;
        _resultText = result != null
            ? JsonUtils.pretty(result)
            : 'No result (goal failed, was cancelled, or timed out)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultOk = false;
        _resultText = 'Error: $e';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _cancel() {
    _client?.cancelGoal();
  }

  @override
  void dispose() {
    _client?.cancelGoal();
    _client?.dispose();
    _goalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.actionName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            widget.actionType,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Goal', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _goalController,
            maxLines: 6,
            enabled: !_sending,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              hintText: '{}',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                borderSide: BorderSide.none,
              ),
              errorText: _goalError,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_sending)
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel goal'),
                  ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: _sending ? null : _sendGoal,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_sending ? 'Active…' : 'Send goal'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Feedback (${_feedback.length})',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          JsonBox(
            text: _feedback.isNotEmpty
                ? JsonUtils.pretty(_feedback.last)
                : (_sending ? 'Waiting for feedback…' : 'No feedback yet'),
            maxHeight: 120,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text('Result', style: theme.textTheme.titleSmall),
              const SizedBox(width: AppSpacing.sm),
              ResultStatusChip(ok: _resultOk),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          JsonBox(text: _resultText ?? 'No goal sent yet'),
        ],
      ),
    );
  }
}
