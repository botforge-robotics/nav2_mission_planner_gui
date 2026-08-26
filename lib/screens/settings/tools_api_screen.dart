import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:ros2_msg_utils/ros2_msg_utils.dart';
import 'package:rosapi_msgs/srv.dart';

import '../../providers/connection_provider.dart';
import '../../services/ros_raw_call.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';

/// Reference §13 (Tools / API Interface), expanded by request beyond the
/// original single "Call API" panel: Topics, Services, and Actions tabs
/// browse the live ROS graph via rosapi (already vendored — rosbridge_suite
/// on :9090 — see rosapi_msgs' own generated classes for Topics/Services/
/// GetActionServers/ServiceType/ActionType) and call/subscribe generically
/// via ros_raw_call.dart's raw JSON helpers, the same wire protocol
/// ros2_api's own typed ServiceClient/ActionClient use underneath, just
/// without a generated Dart class for the type picked at runtime. Only
/// Developer Mode users see this (gated in SettingsHomeScreen), since every
/// tab here can issue real commands to the robot.
class ToolsApiScreen extends StatelessWidget {
  const ToolsApiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Developer Tools'),
          bottom: const TabBar(tabs: [
            Tab(text: 'API'),
            Tab(text: 'Topics'),
            Tab(text: 'Services'),
            Tab(text: 'Actions'),
          ]),
        ),
        body: const TabBarView(children: [
          _ApiTab(),
          _TopicsTab(),
          _ServicesTab(),
          _ActionsTab(),
        ]),
      ),
    );
  }
}

/// The original "Call API" panel, unchanged — a raw HTTP caller against
/// navpromini_sdk's own `/api/v1/...` surface.
class _ApiTab extends StatefulWidget {
  const _ApiTab();

  @override
  State<_ApiTab> createState() => _ApiTabState();
}

class _ApiTabState extends State<_ApiTab> {
  String _method = 'GET';
  final _pathController = TextEditingController(text: '/api/v1/state');
  final _bodyController = TextEditingController(text: '{\n  \n}');

  bool _sending = false;
  int? _status;
  String? _responseText;

  @override
  void dispose() {
    _pathController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    if (ip == null) return;
    var path = _pathController.text.trim();
    if (path.isEmpty) return;
    if (!path.startsWith('/')) path = '/$path';

    Map<String, dynamic>? body;
    if (_method != 'GET' && _bodyController.text.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(_bodyController.text);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        setState(() {
          _status = null;
          _responseText = 'Body is not valid JSON.';
        });
        return;
      }
    }

    setState(() {
      _sending = true;
      _status = null;
      _responseText = null;
    });

    final result = await SdkApiService(ip).raw(_method, path, body: body);
    if (!mounted) return;
    const encoder = JsonEncoder.withIndent('  ');
    setState(() {
      _sending = false;
      _status = result.status;
      _responseText = encoder.convert(result.body);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CenteredFormColumn(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Call API', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownMenu<String>(
                  initialSelection: _method,
                  onSelected: (v) => setState(() => _method = v ?? 'GET'),
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: 'GET', label: 'GET'),
                    DropdownMenuEntry(value: 'POST', label: 'POST'),
                    DropdownMenuEntry(value: 'PUT', label: 'PUT'),
                    DropdownMenuEntry(value: 'DELETE', label: 'DELETE'),
                  ],
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration:
                        const InputDecoration(hintText: '/api/v1/state'),
                  ),
                ),
              ],
            ),
            if (_method != 'GET') ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _bodyController,
                maxLines: 5,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(hintText: 'JSON body'),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textOnPrimary),
                    )
                  : const Text('Send'),
            ),
            if (_responseText != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Text('Response',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (_status != null)
                    Chip(
                      label: Text(_status == 0 ? 'NO RESPONSE' : '$_status'),
                      backgroundColor:
                          (_status != null && _status! >= 200 && _status! < 300
                                  ? AppColors.success
                                  : AppColors.danger)
                              .withValues(alpha: 0.12),
                      side: BorderSide.none,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                  border: Border.all(color: AppColors.border),
                ),
                child: SelectableText(
                  _responseText!,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared "load once, show error/retry, filter by search" shell the three
/// new tabs below all use — same list-screen shape as every other list in
/// this app (Locations, Missions, Maps), just generic over what's loaded.
class _GraphList extends StatefulWidget {
  const _GraphList({
    required this.hint,
    required this.load,
    required this.itemBuilder,
  });

  final String hint;
  final Future<List<String>> Function(Ros2 ros2) load;
  final Widget Function(BuildContext context, String name) itemBuilder;

  @override
  State<_GraphList> createState() => _GraphListState();
}

class _GraphListState extends State<_GraphList> {
  List<String>? _items;
  String? _error;
  String _query = '';
  bool _requested = false;

  Future<void> _load(Ros2 ros2) async {
    setState(() => _error = null);
    try {
      final items = await widget.load(ros2);
      items.sort();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ros2 = context.watch<ConnectionProvider>().ros2;
    if (!_requested && ros2 != null) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(ros2));
    }
    if (ros2 == null) {
      return const Center(child: Text('Not connected.'));
    }
    return CenteredFormColumn(
      maxWidth: 640,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: AppSpacing.sm),
                          TextButton(
                              onPressed: () => _load(ros2),
                              child: const Text('Retry')),
                        ],
                      ),
                    )
                  : _items == null
                      ? const Center(child: CircularProgressIndicator())
                      : Builder(builder: (context) {
                          final filtered = _items!
                              .where((n) => n.toLowerCase().contains(_query))
                              .toList();
                          if (filtered.isEmpty) {
                            return const Center(
                                child: Text('No matches.',
                                    style: TextStyle(
                                        color: AppColors.textSecondary)));
                          }
                          return ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) =>
                                widget.itemBuilder(context, filtered[i]),
                          );
                        }),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Res> _call<T extends RosServiceMessage<Req, Res>,
    Req extends RosMessage<Req>, Res extends RosMessage<Res>>(
  Ros2 ros2,
  String name,
  T type,
  Req request,
) async {
  final client = ServiceClient<T, Req, Res>(
    ros2: ros2,
    name: name,
    type: type.fullType,
    serviceType: type,
    timeout: 10,
    checkExists: false,
  );
  try {
    return await client.call(request);
  } finally {
    client.dispose();
  }
}

class _TopicsTab extends StatelessWidget {
  const _TopicsTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _GraphList(
        hint: 'Search topics',
        load: (ros2) async {
          final r = await _call<Topics, TopicsRequest, TopicsResponse>(
              ros2, '/rosapi/topics', Topics(), TopicsRequest());
          return [
            for (var i = 0; i < r.topics.length; i++)
              '${r.topics[i]} ${i < r.types.length ? r.types[i] : ''}',
          ];
        },
        itemBuilder: (context, entry) {
          final parts = entry.split(' ');
          final name = parts[0];
          final type = parts.length > 1 ? parts[1] : '';
          return ListTile(
            leading:
                const Icon(Icons.podcasts_rounded, color: AppColors.primary),
            title: Text(name),
            subtitle: Text(type,
                style: const TextStyle(color: AppColors.textSecondary)),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _TopicPeekSheet(topic: name, type: type),
            ),
          );
        },
      ),
    );
  }
}

/// Subscribes to one topic while the sheet is open and shows the last few
/// raw messages — closing the sheet unsubscribes.
class _TopicPeekSheet extends StatefulWidget {
  const _TopicPeekSheet({required this.topic, required this.type});

  final String topic;
  final String type;

  @override
  State<_TopicPeekSheet> createState() => _TopicPeekSheetState();
}

class _TopicPeekSheetState extends State<_TopicPeekSheet> {
  RawTopicSubscription? _sub;
  final List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    final ros2 = context.read<ConnectionProvider>().ros2;
    if (ros2 != null) {
      _sub = RawTopicSubscription.start(
        ros2,
        topic: widget.topic,
        type: widget.type,
        onMessage: (m) {
          if (!mounted) return;
          setState(() {
            _messages.insert(0, m);
            if (_messages.length > 20) _messages.removeLast();
          });
        },
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const encoder = JsonEncoder.withIndent('  ');
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.topic,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(widget.type,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text('Waiting for a message…',
                          style: TextStyle(color: AppColors.textSecondary)))
                  : ListView.separated(
                      itemCount: _messages.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: AppSpacing.lg),
                      itemBuilder: (context, i) => SelectableText(
                        encoder.convert(_messages[i]),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicesTab extends StatelessWidget {
  const _ServicesTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _GraphList(
        hint: 'Search services',
        load: (ros2) async {
          final resp = await _call<Services, ServicesRequest, ServicesResponse>(
              ros2, '/rosapi/services', Services(), ServicesRequest());
          return resp.services;
        },
        itemBuilder: (context, name) => ListTile(
          leading: const Icon(Icons.settings_ethernet_rounded,
              color: AppColors.accent),
          title: Text(name),
          onTap: () => _openCallServiceDialog(context, name),
        ),
      ),
    );
  }

  Future<void> _openCallServiceDialog(BuildContext context, String name) async {
    final ros2 = context.read<ConnectionProvider>().ros2;
    if (ros2 == null) return;
    String type;
    try {
      final resp =
          await _call<ServiceType, ServiceTypeRequest, ServiceTypeResponse>(
              ros2,
              '/rosapi/service_type',
              ServiceType(),
              ServiceTypeRequest(service: name));
      type = resp.type;
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't resolve type: $e")));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _RawCallDialog(
        title: 'Call Service',
        name: name,
        type: type,
        submitLabel: 'Call',
        onSubmit: (args) =>
            callServiceRaw(ros2, service: name, type: type, args: args),
      ),
    );
  }
}

class _ActionsTab extends StatelessWidget {
  const _ActionsTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _GraphList(
        hint: 'Search actions',
        load: (ros2) async {
          final resp = await _call<GetActionServers, GetActionServersRequest,
                  GetActionServersResponse>(ros2, '/rosapi/action_servers',
              GetActionServers(), GetActionServersRequest());
          return resp.action_servers;
        },
        itemBuilder: (context, name) => ListTile(
          leading: const Icon(Icons.bolt_rounded, color: AppColors.accent),
          title: Text(name),
          onTap: () => _openSendGoalDialog(context, name),
        ),
      ),
    );
  }

  Future<void> _openSendGoalDialog(BuildContext context, String name) async {
    final ros2 = context.read<ConnectionProvider>().ros2;
    if (ros2 == null) return;
    String type;
    try {
      final resp =
          await _call<ActionType, ActionTypeRequest, ActionTypeResponse>(
              ros2,
              '/rosapi/action_type',
              ActionType(),
              ActionTypeRequest(action: name));
      type = resp.type;
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Couldn't resolve type: $e")));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _RawCallDialog(
        title: 'Send Action Goal',
        name: name,
        type: type,
        submitLabel: 'Send',
        onSubmit: (goal) =>
            sendActionGoalRaw(ros2, action: name, actionType: type, goal: goal),
      ),
    );
  }
}

/// Shared name+type+JSON-args dialog for both the Services and Actions
/// tabs — send/call, show the raw JSON result or error inline.
class _RawCallDialog extends StatefulWidget {
  const _RawCallDialog({
    required this.title,
    required this.name,
    required this.type,
    required this.submitLabel,
    required this.onSubmit,
  });

  final String title;
  final String name;
  final String type;
  final String submitLabel;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> args)
      onSubmit;

  @override
  State<_RawCallDialog> createState() => _RawCallDialogState();
}

class _RawCallDialogState extends State<_RawCallDialog> {
  late final _argsController = TextEditingController(text: '{\n  \n}');
  bool _sending = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _argsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    Map<String, dynamic> args = const {};
    final raw = _argsController.text.trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          setState(() => _error = 'Must be a JSON object.');
          return;
        }
        args = decoded;
      } on FormatException catch (e) {
        setState(() => _error = 'Invalid JSON: ${e.message}');
        return;
      }
    }
    setState(() {
      _sending = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.onSubmit(args);
      if (!mounted) return;
      const encoder = JsonEncoder.withIndent('  ');
      setState(() {
        _sending = false;
        _result = encoder.convert(result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(widget.type,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _argsController,
                minLines: 3,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(hintText: '{"key": value}'),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              if (_result != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SelectableText(_result!,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
        FilledButton(
          onPressed: _sending ? null : _submit,
          child: _sending
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textOnPrimary))
              : Text(widget.submitLabel),
        ),
      ],
    );
  }
}
