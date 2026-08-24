import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/ros2_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'widgets/topic_tool_panel.dart';
import 'widgets/service_tool_panel.dart';
import 'widgets/action_tool_panel.dart';

/// Tools screen — the redesign's "13. Tools (API interface)" section: a
/// raw topics/services/actions browser and call console, for debugging
/// against the live robot the way the reference design's "Call API" panel
/// does. Talks to rosbridge directly through the `ros2_api` plugin's
/// Dynamic* clients (see the widgets/ subfolder) — never through
/// `PcApiService`/the PC server, which has no ROS knowledge at all (see
/// CLAUDE.md).
///
/// Discovery (topic/service/action names + types) comes from
/// `ROS2DataProvider`, the same provider already used elsewhere in the
/// app, rather than opening a fourth cache of the same rosapi calls.
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

enum _ToolKind { topics, services, actions }

class _ToolsScreenState extends State<ToolsScreen> {
  _ToolKind _kind = _ToolKind.topics;
  String? _selected;
  String _search = '';

  // Action types aren't included in ROS2DataProvider.actionServers (just
  // names) — resolved lazily per selection and cached here so re-selecting
  // the same action doesn't re-fetch.
  final Map<String, String> _actionTypeCache = {};
  bool _resolvingActionType = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    final provider = Provider.of<ROS2DataProvider>(context, listen: false);
    provider.fetchTopics();
    provider.fetchServices();
    provider.fetchActionServers();
  }

  Future<void> _selectAction(String name) async {
    setState(() => _selected = name);
    if (_actionTypeCache.containsKey(name)) return;
    setState(() => _resolvingActionType = true);
    final provider = Provider.of<ROS2DataProvider>(context, listen: false);
    final type = await provider.getActionType(name);
    if (!mounted) return;
    setState(() {
      _actionTypeCache[name] = type.isNotEmpty ? type : 'unknown';
      _resolvingActionType = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme,
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        final connection = context.watch<ConnectionProvider>();
        final provider = context.watch<ROS2DataProvider>();

        return Container(
          color: AppColors.lightBackground,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0),
                  child: Row(
                    children: [
                      Text('Tools', style: theme.textTheme.headlineSmall),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                        onPressed: () {
                          final p = Provider.of<ROS2DataProvider>(context,
                              listen: false);
                          p.fetchTopics(forceRefresh: true);
                          p.fetchServices(forceRefresh: true);
                          p.fetchActionServers(forceRefresh: true);
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
                  child: SegmentedButton<_ToolKind>(
                    segments: const [
                      ButtonSegment(
                          value: _ToolKind.topics,
                          label: Text('Topics'),
                          icon: Icon(Icons.podcasts)),
                      ButtonSegment(
                          value: _ToolKind.services,
                          label: Text('Services'),
                          icon: Icon(Icons.build_outlined)),
                      ButtonSegment(
                          value: _ToolKind.actions,
                          label: Text('Actions'),
                          icon: Icon(Icons.play_circle_outline)),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => setState(() {
                      _kind = s.first;
                      _selected = null;
                      _search = '';
                    }),
                  ),
                ),
                if (!connection.isConnected)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      'Not connected to a robot',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                else
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0,
                          AppSpacing.xl, AppSpacing.xl),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 280,
                            child: _ListPanel(
                              kind: _kind,
                              provider: provider,
                              selected: _selected,
                              search: _search,
                              onSearchChanged: (s) =>
                                  setState(() => _search = s),
                              onSelected: (name) {
                                if (_kind == _ToolKind.actions) {
                                  _selectAction(name);
                                } else {
                                  setState(() => _selected = name);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Card(
                              margin: EdgeInsets.zero,
                              child: _buildDetail(connection, provider),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDetail(
      ConnectionProvider connection, ROS2DataProvider provider) {
    final theme = Theme.of(context);
    final selected = _selected;
    if (selected == null) {
      return Center(
        child: Text(
          'Select a ${_kind.name.substring(0, _kind.name.length - 1)} on the left',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    switch (_kind) {
      case _ToolKind.topics:
        return TopicToolPanel(
          key: ValueKey('topic-$selected'),
          ros2: connection.ros2Client,
          topicName: selected,
          topicType: provider.topics[selected] ?? 'unknown',
        );
      case _ToolKind.services:
        return ServiceToolPanel(
          key: ValueKey('service-$selected'),
          ros2: connection.ros2Client,
          serviceName: selected,
          serviceType: provider.services[selected] ?? 'unknown',
        );
      case _ToolKind.actions:
        final type = _actionTypeCache[selected];
        if (type == null) {
          return Center(
            child: _resolvingActionType
                ? const CircularProgressIndicator()
                : Text('Could not resolve action type',
                    style: theme.textTheme.bodyMedium),
          );
        }
        return ActionToolPanel(
          key: ValueKey('action-$selected'),
          ros2: connection.ros2Client,
          actionName: selected,
          actionType: type,
        );
    }
  }
}

class _ListPanel extends StatelessWidget {
  final _ToolKind kind;
  final ROS2DataProvider provider;
  final String? selected;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSelected;

  const _ListPanel({
    required this.kind,
    required this.provider,
    required this.selected,
    required this.search,
    required this.onSearchChanged,
    required this.onSelected,
  });

  Map<String, String?> get _entries {
    switch (kind) {
      case _ToolKind.topics:
        return provider.topics;
      case _ToolKind.services:
        return provider.services;
      case _ToolKind.actions:
        return {for (final a in provider.actionServers) a: null};
    }
  }

  bool get _isLoading {
    switch (kind) {
      case _ToolKind.topics:
        return provider.isLoadingTopics;
      case _ToolKind.services:
        return provider.isLoadingServices;
      case _ToolKind.actions:
        return provider.isLoadingActions;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries.entries
        .where((e) =>
            search.isEmpty || e.key.toLowerCase().contains(search.toLowerCase()))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: TextField(
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search ${kind.name}…',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      _isLoading ? 'Loading…' : 'None found',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final isSelected = e.key == selected;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor:
                            theme.colorScheme.primary.withValues(alpha: 0.08),
                        title: Text(
                          e.key,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: e.value != null
                            ? Text(
                                e.value!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        onTap: () => onSelected(e.key),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
