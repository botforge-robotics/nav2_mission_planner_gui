import 'package:flutter/material.dart';
import 'package:ros2_api/ros2_api.dart';
import '../../../theme/app_spacing.dart';
import 'json_utils.dart';
import 'json_box.dart';

/// Call panel for one service, selected from the Tools screen's Services
/// tab. Built on `ros2_api`'s [DynamicServiceClient] — raw JSON request/
/// response, no per-service Dart class needed.
class ServiceToolPanel extends StatefulWidget {
  final Ros2 ros2;
  final String serviceName;
  final String serviceType;

  const ServiceToolPanel({
    super.key,
    required this.ros2,
    required this.serviceName,
    required this.serviceType,
  });

  @override
  State<ServiceToolPanel> createState() => _ServiceToolPanelState();
}

class _ServiceToolPanelState extends State<ServiceToolPanel> {
  late final TextEditingController _requestController;
  bool _calling = false;
  String? _requestError;
  String? _responseText;
  // Tri-state: null = no call yet, true = response received, false = call
  // failed/timed out/threw — drives the status chip next to "Response",
  // echoing the reference design's "200 OK"-style badge.
  bool? _responseOk;
  DynamicServiceClient? _client;

  @override
  void initState() {
    super.initState();
    _requestController = TextEditingController(text: '{}');
  }

  @override
  void didUpdateWidget(covariant ServiceToolPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serviceName != widget.serviceName) {
      _client?.cancel();
      _client = null;
      setState(() {
        _responseText = null;
        _requestError = null;
        _requestController.text = '{}';
      });
    }
  }

  Future<void> _call() async {
    final (args, error) = JsonUtils.parseArgs(_requestController.text);
    if (error != null) {
      setState(() => _requestError = error);
      return;
    }
    setState(() {
      _calling = true;
      _requestError = null;
      _responseText = null;
      _responseOk = null;
    });
    _client = DynamicServiceClient(
      ros2: widget.ros2,
      serviceName: widget.serviceName,
      serviceType: widget.serviceType,
    );
    try {
      final response = await _client!.call(requestArgs: args!);
      if (!mounted) return;
      setState(() {
        _responseOk = response != null;
        _responseText = response != null
            ? JsonUtils.pretty(response)
            : 'No response (call failed or timed out)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _responseOk = false;
        _responseText = 'Error: $e';
      });
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  void dispose() {
    _client?.cancel();
    _requestController.dispose();
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
          Text(widget.serviceName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            widget.serviceType,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Request', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _requestController,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              hintText: '{}',
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                borderSide: BorderSide.none,
              ),
              errorText: _requestError,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _calling ? null : _call,
              icon: _calling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('Call'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text('Response', style: theme.textTheme.titleSmall),
              const SizedBox(width: AppSpacing.sm),
              ResultStatusChip(ok: _responseOk),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          JsonBox(text: _responseText ?? 'No call made yet'),
        ],
      ),
    );
  }
}
