import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/locations_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/mission_step_summary.dart';
import '../maps/pick_map_position_screen.dart';

/// Reference §7's Mission Planner "Add Waypoint" step, built on the real
/// step schema navpromini_sdk's own mission runner understands
/// (handlers/missions.py's `VALID_STEP_TYPES = ('navigate', 'wait', 'dock',
/// 'undock', 'call_service', 'call_action')`, plus mission-level
/// `loop_count`/`loop_forever`). `call_service`/`call_action` are the
/// generic escape hatch — any ROS service or action by name+type, the same
/// power the app's Tools screen already exposes for interactive use, reused
/// here inside a saved sequence — so they're grouped under "Advanced" rather
/// than flattened in with the everyday five, and validated server-side at
/// save time (a bad type string fails immediately, not mid-run).
///
/// Handles both create ([existing] null) and edit ([existing] the mission
/// being changed) — the server's own `POST /missions` is already
/// create-or-replace by id (see missions.py's own docstring), so editing
/// is just saving again under the same id.
class MissionEditorScreen extends StatefulWidget {
  const MissionEditorScreen({super.key, this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<MissionEditorScreen> createState() => _MissionEditorScreenState();
}

enum _Repeat { once, count, forever }

class _MissionEditorScreenState extends State<MissionEditorScreen> {
  late final _nameController =
      TextEditingController(text: widget.existing?['name'] as String? ?? '');
  late final List<Map<String, dynamic>> _steps = [
    for (final s in (widget.existing?['steps'] as List? ?? const []))
      Map<String, dynamic>.from(s as Map),
  ];

  late _Repeat _repeat = widget.existing?['loop_forever'] == true
      ? _Repeat.forever
      : ((widget.existing?['loop_count'] as num?) ?? 1) > 1
          ? _Repeat.count
          : _Repeat.once;
  late int _loopCount =
      ((widget.existing?['loop_count'] as num?) ?? 2).toInt().clamp(2, 999);

  SdkApiException? _loadError;
  bool _saving = false;
  String? _saveError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocations());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  SdkApiService? get _api {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    return ip == null ? null : SdkApiService(ip);
  }

  Future<void> _loadLocations() async {
    final api = _api;
    if (api == null) return;
    try {
      final list = await api.listWaypoints();
      if (!mounted) return;
      // Shared app-wide (see LocationsController's own doc) — written here
      // too, not just read, so a fresher list this screen happens to fetch
      // is visible everywhere else immediately as well.
      LocationsController.instance.value = list;
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  // -- Add Step ---------------------------------------------------------

  Future<void> _addStepSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
          children: [
            const Text('Add Step',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: AppSpacing.md),
            _StepOptionGrid(options: const [
              _StepOption('map', Icons.touch_app_rounded, AppColors.primary,
                  'Add Position', 'Tap the map'),
              _StepOption('location', Icons.place_rounded, AppColors.primary,
                  'Saved Location', 'Pick from your list'),
              _StepOption(
                  'current',
                  Icons.my_location_rounded,
                  AppColors.primary,
                  'Current Position',
                  "Robot's position now"),
              _StepOption('wait', Icons.hourglass_bottom_rounded,
                  AppColors.stateLocalizing, 'Wait', 'Pause for a duration'),
              _StepOption('dock', Icons.ev_station_rounded,
                  AppColors.stateDocking, 'Dock', 'Navigate & dock'),
              _StepOption('undock', Icons.logout_rounded,
                  AppColors.textSecondary, 'Undock', 'Leave the dock'),
            ], onPick: (id) => Navigator.of(sheetContext).pop(id)),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Text('ADVANCED',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.textTertiary)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Call any ROS service or action by name — the same power the '
              'Tools screen gives you, reusable inside a saved mission.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            _StepOptionGrid(options: const [
              _StepOption('call_service', Icons.settings_ethernet_rounded,
                  AppColors.accent, 'Call Service', 'By name + type'),
              _StepOption('call_action', Icons.bolt_rounded, AppColors.accent,
                  'Call Action', 'By name + type'),
            ], onPick: (id) => Navigator.of(sheetContext).pop(id)),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'map':
        await _pickFromMap();
      case 'location':
        await _pickFromSavedLocation();
      case 'current':
        _addCurrentPosition();
      case 'wait':
        await _addWaitStep();
      case 'dock':
        setState(
            () => _steps.add({'type': 'dock', 'navigate_to_staging': true}));
      case 'undock':
        setState(() => _steps.add({'type': 'undock'}));
      case 'call_service':
        await _addRosCallStep(isAction: false);
      case 'call_action':
        await _addRosCallStep(isAction: true);
    }
  }

  Future<void> _pickFromMap() async {
    final picked =
        await Navigator.of(context).push<({double x, double y, double theta})>(
      MaterialPageRoute(builder: (_) => const PickMapPositionScreen()),
    );
    if (picked == null || !mounted) return;
    setState(() => _steps.add({
          'type': 'navigate',
          'x': picked.x,
          'y': picked.y,
          'theta': picked.theta,
        }));
  }

  Future<void> _pickFromSavedLocation() async {
    final locations = LocationsController.instance.value ?? const [];
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        if (locations.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text(
                'No saved locations yet — add one from the Locations tab first.',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
              child: Text('From Saved Locations',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final loc in locations)
              ListTile(
                leading:
                    const Icon(Icons.place_rounded, color: AppColors.primary),
                title: Text(loc['name'] as String? ?? ''),
                onTap: () =>
                    Navigator.of(sheetContext).pop(loc['name'] as String?),
              ),
          ],
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _steps.add({'type': 'navigate', 'target': picked}));
    }
  }

  void _addCurrentPosition() {
    final telemetry = context.read<RobotTelemetryProvider>();
    if (telemetry.poseX == null || telemetry.poseY == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "The robot's position isn't known yet — it isn't localized.")));
      return;
    }
    setState(() => _steps.add({
          'type': 'navigate',
          'x': telemetry.poseX,
          'y': telemetry.poseY,
          'theta': telemetry.poseTheta ?? 0.0,
        }));
  }

  Future<void> _addWaitStep() async {
    final controller = TextEditingController(text: '5');
    final seconds = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Wait'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration:
              const InputDecoration(hintText: 'Seconds', suffixText: 'sec'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  dialogContext, double.tryParse(controller.text)),
              child: const Text('Add')),
        ],
      ),
    );
    // Deferred — see _confirmAddLocation's matching comment in
    // map_view_screen.dart.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (seconds != null && seconds > 0 && mounted) {
      setState(() => _steps.add({'type': 'wait', 'duration': seconds}));
    }
  }

  /// Shared dialog for `call_service`/`call_action` — name, type, and an
  /// optional JSON request/goal, validated inline so a malformed JSON body
  /// can't reach Save.
  Future<void> _addRosCallStep({required bool isAction}) async {
    final nameController = TextEditingController();
    final typeController = TextEditingController();
    final bodyController = TextEditingController();
    final timeoutController =
        TextEditingController(text: isAction ? '300' : '15');
    String? bodyError;

    final step = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isAction ? 'Call Action' : 'Call Service'),
          // A bare SingleChildScrollView has no width of its own to hand
          // the Column below, so without this the dialog shrank to a
          // cramped, barely-usable width — a fixed generous width (clamped
          // to the actual screen on a narrow phone) instead.
          content: SizedBox(
            width: min(440, MediaQuery.sizeOf(context).width - 80),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: isAction ? 'Action name' : 'Service name',
                      hintText: isAction ? '/spin' : '/map_server/reload',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: typeController,
                    decoration: InputDecoration(
                      labelText: isAction ? 'Action type' : 'Service type',
                      hintText: isAction
                          ? 'nav2_msgs/action/Spin'
                          : 'std_srvs/srv/Trigger',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: bodyController,
                    minLines: 3,
                    maxLines: 6,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      labelText: isAction
                          ? 'Goal (JSON, optional)'
                          : 'Request (JSON, optional)',
                      hintText: '{"target_yaw": 1.57}',
                      errorText: bodyError,
                    ),
                    onChanged: (_) => setDialogState(() => bodyError = null),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: timeoutController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Timeout', suffixText: 'sec'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final type = typeController.text.trim();
                if (name.isEmpty || type.isEmpty) {
                  setDialogState(
                      () => bodyError = 'Name and type are both required.');
                  return;
                }
                Map<String, dynamic> body = const {};
                final raw = bodyController.text.trim();
                if (raw.isNotEmpty) {
                  try {
                    final decoded = jsonDecode(raw);
                    if (decoded is! Map<String, dynamic>) {
                      setDialogState(() => bodyError =
                          'Must be a JSON object, e.g. {"key": value}');
                      return;
                    }
                    body = decoded;
                  } on FormatException catch (e) {
                    setDialogState(
                        () => bodyError = 'Invalid JSON: ${e.message}');
                    return;
                  }
                }
                final timeout = double.tryParse(timeoutController.text) ??
                    (isAction ? 300.0 : 15.0);
                Navigator.pop(dialogContext, {
                  'type': isAction ? 'call_action' : 'call_service',
                  if (isAction) 'action': name else 'service': name,
                  if (isAction) 'action_type': type else 'service_type': type,
                  if (isAction) 'goal': body else 'request': body,
                  'timeout': timeout,
                });
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    // Deferred a frame — see the matching comment in map_view_screen.dart's
    // _confirmAddLocation: disposing an autofocused dialog's controllers
    // synchronously right after showDialog resolves can race the dialog's
    // still-unwinding exit transition and throw a framework assertion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      typeController.dispose();
      bodyController.dispose();
      timeoutController.dispose();
    });
    if (step != null && mounted) {
      setState(() => _steps.add(step));
    }
  }

  // -- Save ---------------------------------------------------------------

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _saveError = 'Give this mission a name.');
      return;
    }
    if (_steps.isEmpty) {
      setState(() => _saveError = 'Add at least one step.');
      return;
    }
    final api = _api;
    if (api == null) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final id = widget.existing?['id'] as String? ?? const Uuid().v4();
      await api.putMission(id, name, _steps,
          loopCount: _repeat == _Repeat.count ? _loopCount : 1,
          loopForever: _repeat == _Repeat.forever);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Mission' : 'New Mission')),
      body: SafeArea(
        child: CenteredFormColumn(
          maxWidth: 640,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                      hintText: 'Mission name, e.g. Patrol Route A'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Text('Steps',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addStepSheet,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Step'),
                    ),
                  ],
                ),
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      _loadError!.isUnreachable
                          ? "Can't load saved locations — the SDK isn't reachable."
                          : _loadError!.message,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                Expanded(
                  child: _steps.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.route_outlined,
                                  size: 40, color: AppColors.textTertiary),
                              const SizedBox(height: AppSpacing.sm),
                              const Text('No steps added yet.',
                                  style: TextStyle(
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          // Off: ReorderableListView.builder defaults this
                          // to true and auto-appends its own trailing drag
                          // handle — since a drag handle is already added
                          // by hand below (via ReorderableDragStartListener,
                          // so it actually drags), leaving the default on
                          // meant two overlapping handle icons crammed into
                          // trailing alongside the delete button.
                          buildDefaultDragHandles: false,
                          itemCount: _steps.length,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex -= 1;
                              final item = _steps.removeAt(oldIndex);
                              _steps.insert(newIndex, item);
                            });
                          },
                          itemBuilder: (context, i) => Card(
                            key: ValueKey('$i-${_steps[i].hashCode}'),
                            margin:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: ListTile(
                              leading: StepIconChip(step: _steps[i]),
                              title: Text(missionStepSummary(_steps[i]),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  'Step ${i + 1} · ${_steps[i]['type']}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18),
                                    onPressed: () =>
                                        setState(() => _steps.removeAt(i)),
                                  ),
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 4),
                                      child: Icon(Icons.drag_handle_rounded,
                                          color: AppColors.textTertiary,
                                          size: 20),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.md),
                _RepeatCard(
                  repeat: _repeat,
                  count: _loopCount,
                  onChanged: (r) => setState(() => _repeat = r),
                  onCountChanged: (c) => setState(() => _loopCount = c),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_saveError != null) ...[
                  Text(_saveError!,
                      style: const TextStyle(color: AppColors.danger)),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textOnPrimary),
                              )
                            : Text(
                                _isEditing ? 'Save Changes' : 'Create Mission'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepOption {
  const _StepOption(this.id, this.icon, this.color, this.label, this.caption);

  final String id;
  final IconData icon;
  final Color color;
  final String label;
  final String caption;
}

/// The Add Step sheet's tappable options, as a wrapping grid of icon-chip
/// tiles rather than a plain vertical list — closer to the reference
/// mockup's "Add Waypoint" panel and more scannable at a glance.
class _StepOptionGrid extends StatelessWidget {
  const _StepOptionGrid({required this.options, required this.onPick});

  final List<_StepOption> options;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.6,
      children: [
        for (final opt in options)
          Material(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              onTap: () => onPick(opt.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: opt.color.withValues(alpha: 0.14),
                      child: Icon(opt.icon, color: opt.color, size: 16),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(opt.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(opt.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Once / Repeat N times / Forever" — mission-level looping, backed by the
/// server's `loop_count`/`loop_forever` fields (handlers/missions.py).
class _RepeatCard extends StatelessWidget {
  const _RepeatCard({
    required this.repeat,
    required this.count,
    required this.onChanged,
    required this.onCountChanged,
  });

  final _Repeat repeat;
  final int count;
  final ValueChanged<_Repeat> onChanged;
  final ValueChanged<int> onCountChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Repeat', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  label: const Text('Once'),
                  selected: repeat == _Repeat.once,
                  onSelected: (_) => onChanged(_Repeat.once),
                ),
                ChoiceChip(
                  label: const Text('Repeat'),
                  selected: repeat == _Repeat.count,
                  onSelected: (_) => onChanged(_Repeat.count),
                ),
                ChoiceChip(
                  label: const Text('Forever'),
                  selected: repeat == _Repeat.forever,
                  onSelected: (_) => onChanged(_Repeat.forever),
                ),
              ],
            ),
            if (repeat == _Repeat.count) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed:
                        count > 2 ? () => onCountChanged(count - 1) : null,
                  ),
                  Text('$count times',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () => onCountChanged(count + 1),
                  ),
                ],
              ),
            ],
            if (repeat == _Repeat.forever) ...[
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'The mission repeats until you cancel it — it will not stop '
                'on its own.',
                style: TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
