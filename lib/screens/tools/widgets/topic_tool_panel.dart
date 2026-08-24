import 'package:flutter/material.dart';
import 'package:ros2_api/ros2_api.dart';
import '../../../theme/app_spacing.dart';
import 'json_utils.dart';
import 'json_box.dart';

/// Subscribe/publish panel for one topic, selected from the Tools screen's
/// Topics tab. Built entirely on `ros2_api`'s [DynamicSubscriber]/
/// [DynamicPublisher] — raw `Map<String, dynamic>` in and out, no
/// per-message-type Dart class needed, which is exactly what a generic
/// "call anything" tool requires. Talks to rosbridge directly, never
/// through `PcApiService` (see CLAUDE.md — the PC API has no ROS
/// knowledge).
class TopicToolPanel extends StatefulWidget {
  final Ros2 ros2;
  final String topicName;
  final String topicType;

  const TopicToolPanel({
    super.key,
    required this.ros2,
    required this.topicName,
    required this.topicType,
  });

  @override
  State<TopicToolPanel> createState() => _TopicToolPanelState();
}

class _TopicToolPanelState extends State<TopicToolPanel> {
  DynamicSubscriber? _subscriber;
  DynamicPublisher? _publisher;
  Map<String, dynamic>? _lastMessage;
  int _messageCount = 0;
  bool _publishing = false;
  String? _publishError;
  late final TextEditingController _publishController;

  bool get _isSubscribed => _subscriber?.isSubscribed ?? false;

  @override
  void initState() {
    super.initState();
    _publishController = TextEditingController(text: '{}');
  }

  @override
  void didUpdateWidget(covariant TopicToolPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topicName != widget.topicName) {
      _teardown();
      setState(() {
        _lastMessage = null;
        _messageCount = 0;
        _publishError = null;
        _publishController.text = '{}';
      });
    }
  }

  void _teardown() {
    _subscriber?.unsubscribe();
    _subscriber = null;
    _publisher?.unadvertise();
    _publisher = null;
  }

  void _toggleSubscribe() {
    if (_isSubscribed) {
      setState(() => _subscriber?.unsubscribe());
      return;
    }
    _subscriber = DynamicSubscriber(
      ros2: widget.ros2,
      topicName: widget.topicName,
      topicType: widget.topicType,
      onMessage: (msg) {
        if (!mounted) return;
        setState(() {
          _lastMessage = msg;
          _messageCount++;
        });
      },
    );
    setState(() => _subscriber!.subscribe());
  }

  Future<void> _publish() async {
    final (args, error) = JsonUtils.parseArgs(_publishController.text);
    if (error != null) {
      setState(() => _publishError = error);
      return;
    }
    setState(() {
      _publishing = true;
      _publishError = null;
    });
    try {
      _publisher ??= DynamicPublisher(
        ros2: widget.ros2,
        topicName: widget.topicName,
        topicType: widget.topicType,
      );
      _publisher!.publish(args!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Published to ${widget.topicName}')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _publishError = e.toString());
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  void dispose() {
    _teardown();
    _publishController.dispose();
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
          Text(widget.topicName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            widget.topicType,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Subscribe
          Row(
            children: [
              Text('Subscribe', style: theme.textTheme.titleSmall),
              const Spacer(),
              if (_isSubscribed)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Text(
                    '$_messageCount received',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              FilledButton.tonalIcon(
                onPressed: _toggleSubscribe,
                icon: Icon(_isSubscribed ? Icons.stop : Icons.play_arrow),
                label: Text(_isSubscribed ? 'Unsubscribe' : 'Subscribe'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          JsonBox(
            text: _lastMessage != null
                ? JsonUtils.pretty(_lastMessage)
                : (_isSubscribed
                    ? 'Waiting for a message…'
                    : 'Not subscribed'),
          ),
          const SizedBox(height: AppSpacing.xl),
          // Publish
          Text('Publish', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _publishController,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              hintText: '{"data": "hello"}',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                borderSide: BorderSide.none,
              ),
              errorText: _publishError,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _publishing ? null : _publish,
              icon: _publishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('Publish'),
            ),
          ),
        ],
      ),
    );
  }
}
