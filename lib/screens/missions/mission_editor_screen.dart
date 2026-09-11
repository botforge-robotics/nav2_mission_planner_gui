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
import '../../utils/localize_at_dock.dart';
import '../../utils/mission_step_summary.dart';
import '../../widgets/app_shell/app_shell.dart';
import '../../widgets/map/occupancy_grid_view.dart';
import '../maps/pick_map_position_screen.dart';
import 'graph/mission_graph_editor_screen.dart';

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
  ({double x, double y, double theta})? _dockPose;
  String? _missionMap;
  String? _currentActiveMap;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _missionMap = widget.existing?['map'] as String?;
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
      final currentMap = await api.getCurrentMap();
      if (!mounted) return;
      // Shared app-wide (see LocationsController's own doc) — written here
      // too, not just read, so a fresher list this screen happens to fetch
      // is visible everywhere else immediately as well.
      LocationsController.instance.value = list;
      setState(() {
        _currentActiveMap = currentMap;
        _missionMap ??= currentMap;
      });
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
    final dock = await fetchDockPose(api);
    if (mounted) setState(() => _dockPose = dock);
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
              _StepOption('call_api', Icons.http_rounded, AppColors.accent,
                  'HTTP / API Call', 'Webhooks & endpoints'),
            ], onPick: (id) => Navigator.of(sheetContext).pop(id)),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    await _handleStepChoice(choice);
  }

  Future<void> _handleStepChoice(String choice) async {
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
        await _showRosCallDialog(isAction: false);
      case 'call_action':
        await _showRosCallDialog(isAction: true);
      case 'call_api':
        await _showApiCallDialog();
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
  /// can't reach Save. Supports adding a new step or editing an existing one.
  Future<void> _showRosCallDialog(
      {required bool isAction, int? editIndex}) async {
    final existing = editIndex != null ? _steps[editIndex] : null;
    final nameController = TextEditingController(
        text: existing != null
            ? (isAction ? existing['action'] : existing['service']) as String? ??
                ''
            : '');
    final typeController = TextEditingController(
        text: existing != null
            ? (isAction
                    ? existing['action_type']
                    : existing['service_type']) as String? ??
                ''
            : '');
    final existingBody =
        existing != null ? (existing[isAction ? 'goal' : 'request']) : null;
    final bodyController = TextEditingController(
        text: existingBody != null
            ? const JsonEncoder.withIndent('  ').convert(existingBody)
            : '');
    final timeoutController = TextEditingController(
        text: existing != null
            ? '${existing['timeout'] ?? (isAction ? '300' : '15')}'
            : (isAction ? '300' : '15'));
    String? bodyError;

    final step = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(editIndex != null
              ? (isAction ? 'Edit Action' : 'Edit Service')
              : (isAction ? 'Call Action' : 'Call Service')),
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
              child: Text(editIndex != null ? 'Save Changes' : 'Add'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      typeController.dispose();
      bodyController.dispose();
      timeoutController.dispose();
    });
    if (step != null && mounted) {
      setState(() {
        if (editIndex != null) {
          _steps[editIndex] = step;
        } else {
          _steps.add(step);
        }
      });
    }
  }

  /// Dialog for HTTP API call steps — method, URL, headers, and body payload.
  Future<void> _showApiCallDialog({int? editIndex}) async {
    final existing = editIndex != null ? _steps[editIndex] : null;
    final urlController = TextEditingController(
        text: existing != null ? (existing['url'] as String? ?? '') : '');
    var selectedMethod =
        (existing != null ? (existing['method'] as String?) : null)?.toUpperCase() ??
            'POST';
    final headersController = TextEditingController(
        text: existing != null && existing['headers'] != null
            ? const JsonEncoder.withIndent('  ').convert(existing['headers'])
            : '');
    final payloadController = TextEditingController(
        text: existing != null && existing['payload'] != null
            ? (existing['payload'] is String
                ? existing['payload'] as String
                : const JsonEncoder.withIndent('  ').convert(existing['payload']))
            : '');
    final timeoutController = TextEditingController(
        text: existing != null ? '${existing['timeout'] ?? 15}' : '15');
    var ignoreError =
        existing != null ? (existing['ignore_error'] == true) : false;
    String? bodyError;

    final step = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(editIndex != null ? 'Edit HTTP API Call' : 'HTTP / API Call'),
          content: SizedBox(
            width: min(480, MediaQuery.sizeOf(context).width - 80),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedMethod,
                          decoration: const InputDecoration(labelText: 'Method'),
                          items: const [
                            DropdownMenuItem(value: 'GET', child: Text('GET')),
                            DropdownMenuItem(value: 'POST', child: Text('POST')),
                            DropdownMenuItem(value: 'PUT', child: Text('PUT')),
                            DropdownMenuItem(value: 'PATCH', child: Text('PATCH')),
                            DropdownMenuItem(value: 'DELETE', child: Text('DELETE')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedMethod = val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: urlController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'URL Endpoint',
                            hintText: 'http://192.168.1.50:8000/api/hook',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: headersController,
                    minLines: 2,
                    maxLines: 4,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Headers (JSON, optional)',
                      hintText: '{"Content-Type": "application/json"}',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: payloadController,
                    minLines: 3,
                    maxLines: 6,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Payload / Body (JSON or text, optional)',
                      hintText: '{"status": "arrived", "robot_id": 1}',
                      errorText: bodyError,
                    ),
                    onChanged: (_) => setDialogState(() => bodyError = null),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: timeoutController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Timeout', suffixText: 'sec'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Ignore error',
                              style: TextStyle(fontSize: 13)),
                          subtitle: const Text('Continue on HTTP error',
                              style: TextStyle(fontSize: 11)),
                          value: ignoreError,
                          onChanged: (val) =>
                              setDialogState(() => ignoreError = val),
                        ),
                      ),
                    ],
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
                final url = urlController.text.trim();
                if (url.isEmpty) {
                  setDialogState(() => bodyError = 'URL is required.');
                  return;
                }
                Map<String, String>? headersMap;
                final headersRaw = headersController.text.trim();
                if (headersRaw.isNotEmpty) {
                  try {
                    final decoded = jsonDecode(headersRaw);
                    if (decoded is! Map) {
                      setDialogState(() =>
                          bodyError = 'Headers must be a JSON object.');
                      return;
                    }
                    headersMap = decoded
                        .map((k, v) => MapEntry(k.toString(), v.toString()));
                  } on FormatException catch (e) {
                    setDialogState(
                        () => bodyError = 'Invalid Headers JSON: ${e.message}');
                    return;
                  }
                }
                dynamic payloadVal;
                final payloadRaw = payloadController.text.trim();
                if (payloadRaw.isNotEmpty) {
                  try {
                    payloadVal = jsonDecode(payloadRaw);
                  } on FormatException {
                    payloadVal = payloadRaw;
                  }
                }
                final timeout =
                    double.tryParse(timeoutController.text) ?? 15.0;
                Navigator.pop(dialogContext, {
                  'type': 'call_api',
                  'url': url,
                  'method': selectedMethod,
                  if (headersMap != null && headersMap.isNotEmpty)
                    'headers': headersMap,
                  if (payloadVal != null) 'payload': payloadVal,
                  'timeout': timeout,
                  if (ignoreError) 'ignore_error': true,
                });
              },
              child: Text(editIndex != null ? 'Save Changes' : 'Add'),
            ),
          ],
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      urlController.dispose();
      headersController.dispose();
      payloadController.dispose();
      timeoutController.dispose();
    });

    if (step != null && mounted) {
      setState(() {
        if (editIndex != null) {
          _steps[editIndex] = step;
        } else {
          _steps.add(step);
        }
      });
    }
  }

  /// Edits an existing navigate step: allows switching between saved location
  /// and exact coordinates, picking from map, or reading current pose.
  Future<void> _editNavigateStep(int index) async {
    final current = _steps[index];
    final isSavedLoc = current['target'] != null;
    final locations = LocationsController.instance.value ?? const [];

    String selectedType = isSavedLoc ? 'location' : 'coords';
    String? selectedLoc = current['target'] as String?;
    if (selectedLoc == null && locations.isNotEmpty) {
      selectedLoc = locations.first['name'] as String?;
    }

    final xCtrl = TextEditingController(
        text: (current['x'] as num?)?.toStringAsFixed(2) ?? '0.00');
    final yCtrl = TextEditingController(
        text: (current['y'] as num?)?.toStringAsFixed(2) ?? '0.00');
    final thetaCtrl = TextEditingController(
        text: current['theta'] != null
            ? ((current['theta'] as num).toDouble() * 180 / pi).toStringAsFixed(1)
            : '0.0');

    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.place_rounded, color: AppColors.primary),
              SizedBox(width: AppSpacing.sm),
              Text('Edit Navigation Step'),
            ],
          ),
          content: SizedBox(
            width: min(440, MediaQuery.sizeOf(context).width - 80),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'location',
                        label: Text('Saved Location'),
                        icon: Icon(Icons.bookmark_outline_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: 'coords',
                        label: Text('Coordinates'),
                        icon: Icon(Icons.pin_drop_outlined, size: 16),
                      ),
                    ],
                    selected: {selectedType},
                    onSelectionChanged: (val) =>
                        setDialogState(() => selectedType = val.first),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (selectedType == 'location') ...[
                    if (locations.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Text(
                          'No saved locations found. Switch to Coordinates or add locations in the Map tab.',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: locations.any((l) => l['name'] == selectedLoc)
                            ? selectedLoc
                            : locations.first['name'] as String?,
                        decoration: const InputDecoration(
                          labelText: 'Select Location',
                          prefixIcon: Icon(Icons.place_rounded, size: 18),
                        ),
                        items: [
                          for (final loc in locations)
                            DropdownMenuItem<String>(
                              value: loc['name'] as String?,
                              child: Text(loc['name'] as String? ?? ''),
                            ),
                        ],
                        onChanged: (val) =>
                            setDialogState(() => selectedLoc = val),
                      ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: xCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                              labelText: 'X',
                              suffixText: 'm',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            controller: yCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                              labelText: 'Y',
                              suffixText: 'm',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            controller: thetaCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                              labelText: 'Heading',
                              suffixText: '°',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.map_rounded, size: 16),
                            label: const Text('Pick on Map'),
                            onPressed: () async {
                              final initX = double.tryParse(xCtrl.text);
                              final initY = double.tryParse(yCtrl.text);
                              final initDeg =
                                  double.tryParse(thetaCtrl.text) ?? 0.0;
                              final picked = await Navigator.of(context).push<
                                  ({double x, double y, double theta})>(
                                MaterialPageRoute(
                                  builder: (_) => PickMapPositionScreen(
                                    initialPose: initX != null && initY != null
                                        ? (
                                            x: initX,
                                            y: initY,
                                            theta: initDeg * pi / 180
                                          )
                                        : null,
                                    title: 'Pick Position on Map',
                                  ),
                                ),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  xCtrl.text = picked.x.toStringAsFixed(2);
                                  yCtrl.text = picked.y.toStringAsFixed(2);
                                  thetaCtrl.text =
                                      (picked.theta * 180 / pi).toStringAsFixed(1);
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.my_location_rounded, size: 16),
                            label: const Text('Current Pose'),
                            onPressed: () {
                              final telemetry =
                                  context.read<RobotTelemetryProvider>();
                              if (telemetry.poseX == null ||
                                  telemetry.poseY == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Robot is not localized.')),
                                );
                                return;
                              }
                              setDialogState(() {
                                xCtrl.text = telemetry.poseX!.toStringAsFixed(2);
                                yCtrl.text = telemetry.poseY!.toStringAsFixed(2);
                                thetaCtrl.text = (telemetry.poseTheta != null
                                        ? (telemetry.poseTheta! * 180 / pi)
                                        : 0.0)
                                    .toStringAsFixed(1);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (selectedType == 'location') {
                  if (selectedLoc == null || selectedLoc!.isEmpty) return;
                  Navigator.of(dialogCtx)
                      .pop({'type': 'navigate', 'target': selectedLoc});
                } else {
                  final x = double.tryParse(xCtrl.text) ?? 0.0;
                  final y = double.tryParse(yCtrl.text) ?? 0.0;
                  final deg = double.tryParse(thetaCtrl.text) ?? 0.0;
                  Navigator.of(dialogCtx).pop({
                    'type': 'navigate',
                    'x': x,
                    'y': y,
                    'theta': deg * pi / 180,
                  });
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      xCtrl.dispose();
      yCtrl.dispose();
      thetaCtrl.dispose();
    });

    if (updated != null && mounted) {
      setState(() => _steps[index] = updated);
    }
  }

  /// Edits an existing wait step duration.
  Future<void> _editWaitStep(int index) async {
    final current = _steps[index];
    final controller =
        TextEditingController(text: '${current['duration'] ?? 5}');
    final seconds = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.hourglass_bottom_rounded, color: AppColors.primary),
            SizedBox(width: AppSpacing.sm),
            Text('Edit Wait Step'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Duration',
            hintText: 'Seconds',
            suffixText: 'sec',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                dialogContext, double.tryParse(controller.text)),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (seconds != null && seconds > 0 && mounted) {
      setState(() => _steps[index] = {'type': 'wait', 'duration': seconds});
    }
  }

  /// Edits an existing dock step staging configuration.
  Future<void> _editDockStep(int index) async {
    final current = _steps[index];
    var navigateToStaging = current['navigate_to_staging'] != false;
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.ev_station_rounded, color: AppColors.primary),
              SizedBox(width: AppSpacing.sm),
              Text('Edit Dock Step'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Navigate to staging pose first'),
                subtitle: const Text(
                    'Robot navigates in front of dock before visual docking approach.'),
                value: navigateToStaging,
                onChanged: (val) =>
                    setDialogState(() => navigateToStaging = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, navigateToStaging),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _steps[index] = {
            'type': 'dock',
            'navigate_to_staging': updated,
          });
    }
  }

  /// Informs or confirms undock step.
  Future<void> _editUndockStep(int index) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.primary),
            SizedBox(width: AppSpacing.sm),
            Text('Undock Step'),
          ],
        ),
        content: const Text(
            'The robot will back out from the charging dock to clear the contacts. No additional parameters are required.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Dispatches editing to the appropriate editor based on step type.
  Future<void> _editStep(int index) async {
    if (index < 0 || index >= _steps.length) return;
    final step = _steps[index];
    switch (step['type']) {
      case 'navigate':
        await _editNavigateStep(index);
      case 'wait':
        await _editWaitStep(index);
      case 'dock':
        await _editDockStep(index);
      case 'undock':
        await _editUndockStep(index);
      case 'call_service':
        await _showRosCallDialog(isAction: false, editIndex: index);
      case 'call_action':
        await _showRosCallDialog(isAction: true, editIndex: index);
      case 'call_api':
        await _showApiCallDialog(editIndex: index);
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
          loopForever: _repeat == _Repeat.forever,
          map: _missionMap ?? _currentActiveMap);
      if (!mounted) return;
      _goBack(true);
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.message;
      });
    }
  }

  void _goBack([bool? result]) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result ?? false);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    }
  }

  List<Map<String, dynamic>> _routePins(List<Map<String, dynamic>> steps) {
    final pins = <Map<String, dynamic>>[];
    final locations =
        LocationsController.instance.value ?? const <Map<String, dynamic>>[];

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      double? x, y;
      if (step['type'] == 'navigate') {
        final target = step['target'];
        if (target is String) {
          for (final loc in locations) {
            if (loc['name'] == target) {
              x = (loc['x'] as num?)?.toDouble();
              y = (loc['y'] as num?)?.toDouble();
              break;
            }
          }
        } else {
          x = (step['x'] as num?)?.toDouble();
          y = (step['y'] as num?)?.toDouble();
        }
      } else if (step['type'] == 'dock' || step['type'] == 'undock') {
        x = _dockPose?.x;
        y = _dockPose?.y;
      }
      if (x != null && y != null) {
        pins.add({'name': '${i + 1}', 'x': x, 'y': y});
      }
    }
    return pins;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;
    final ros2 = context.watch<ConnectionProvider>().ros2;
    final telemetry = context.read<RobotTelemetryProvider>();
    final routePins = _routePins(_steps);

    if (isDesktop) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, __) {
          if (!didPop) _goBack(false);
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back to Missions',
              onPressed: () => _goBack(false),
            ),
            title: Text(_isEditing
                ? 'Mission Studio · Edit Mission'
                : 'Mission Studio · New Mission'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.account_tree_outlined, size: 16),
                label: const Text('Visual Node Editor'),
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => MissionGraphEditorScreen(
                        existingMission: widget.existing,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.textOnPrimary),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(_isEditing ? 'Save Changes' : 'Save Mission'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. LEFT COLUMN: Configuration, Step Palette & Primary Save Card
                SizedBox(
                  width: 360,
                  child: ListView(
                    children: [
                      // Mission Name & Repeat Card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mission Configuration',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Mission Name',
                                  hintText: 'e.g. Living Room Patrol',
                                  prefixIcon: Icon(Icons.label_outline_rounded),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: (_missionMap != null &&
                                              _currentActiveMap != null &&
                                              _missionMap != _currentActiveMap)
                                          ? AppColors.warning.withValues(alpha: 0.12)
                                          : AppColors.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: (_missionMap != null &&
                                                _currentActiveMap != null &&
                                                _missionMap != _currentActiveMap)
                                            ? AppColors.warning.withValues(alpha: 0.4)
                                            : AppColors.primary.withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          (_missionMap != null &&
                                                  _currentActiveMap != null &&
                                                  _missionMap != _currentActiveMap)
                                              ? Icons.warning_amber_rounded
                                              : Icons.map_outlined,
                                          size: 14,
                                          color: (_missionMap != null &&
                                                  _currentActiveMap != null &&
                                                  _missionMap != _currentActiveMap)
                                              ? AppColors.warning
                                              : AppColors.primary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Map: ${_missionMap ?? _currentActiveMap ?? "Active Map"}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: (_missionMap != null &&
                                                    _currentActiveMap != null &&
                                                    _missionMap != _currentActiveMap)
                                                ? AppColors.warning
                                                : AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_missionMap != null &&
                                  _currentActiveMap != null &&
                                  _missionMap != _currentActiveMap) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Warning: Active map on robot is "$_currentActiveMap". Waypoints may mismatch.',
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.warning),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.md),
                              _RepeatCard(
                                repeat: _repeat,
                                count: _loopCount,
                                onChanged: (r) => setState(() => _repeat = r),
                                onCountChanged: (c) =>
                                    setState(() => _loopCount = c),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Step Palette Card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add Step to Route',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Click any tool to insert into route:',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _StepOptionGrid(
                                options: const [
                                  _StepOption(
                                      'map',
                                      Icons.touch_app_rounded,
                                      AppColors.primary,
                                      'Add Position',
                                      'Tap the map'),
                                  _StepOption(
                                      'location',
                                      Icons.place_rounded,
                                      AppColors.primary,
                                      'Saved Location',
                                      'Pick from list'),
                                  _StepOption(
                                      'current',
                                      Icons.my_location_rounded,
                                      AppColors.primary,
                                      'Current Pose',
                                      "Robot's pose now"),
                                  _StepOption(
                                      'wait',
                                      Icons.hourglass_bottom_rounded,
                                      AppColors.stateLocalizing,
                                      'Wait Duration',
                                      'Pause timer'),
                                  _StepOption(
                                      'dock',
                                      Icons.ev_station_rounded,
                                      AppColors.stateDocking,
                                      'Dock',
                                      'Navigate & dock'),
                                  _StepOption(
                                      'undock',
                                      Icons.logout_rounded,
                                      AppColors.textSecondary,
                                      'Undock',
                                      'Leave dock'),
                                ],
                                onPick: (id) => _handleStepChoice(id),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              const Divider(),
                              const SizedBox(height: AppSpacing.xs),
                              const Text(
                                'Advanced & API Calls:',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _handleStepChoice('call_service'),
                                      icon: const Icon(
                                          Icons.settings_ethernet_rounded,
                                          size: 15),
                                      label: const Text('Service',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _handleStepChoice('call_action'),
                                      icon: const Icon(Icons.bolt_rounded,
                                          size: 15),
                                      label: const Text('Action',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _handleStepChoice('call_api'),
                                      icon: const Icon(Icons.http_rounded,
                                          size: 15),
                                      label: const Text('HTTP API',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      if (_saveError != null)
                        Card(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.cardRadius),
                            side: const BorderSide(color: AppColors.danger),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: AppColors.danger, size: 20),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(_saveError!,
                                      style: const TextStyle(
                                          color: AppColors.danger,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),

                // 2. CENTER COLUMN: Live Interactive Map Preview (flex: 6)
                Expanded(
                  flex: 6,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ros2 == null
                              ? const Center(child: Text('Not connected.'))
                              : OccupancyGridView(
                                  ros2: ros2,
                                  interactive: true,
                                  initialPose: telemetry.rawPose,
                                  initialPath: telemetry.currentPath,
                                  locations: routePins,
                                  showWaypointRoute: true,
                                  fitWholeMap: false,
                                  showRobot: true,
                                  showDock: true,
                                  showPath: true,
                                ),
                        ),
                        Positioned(
                          left: AppSpacing.md,
                          top: AppSpacing.md,
                          child: Card(
                            color: AppColors.surface.withValues(alpha: 0.92),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.xs),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.map_rounded,
                                      size: 16, color: AppColors.primary),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    'Mission Route Preview • Map: ${_missionMap ?? _currentActiveMap ?? "Active Map"} (${routePins.length} waypoints plotted)',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),

                // 3. RIGHT COLUMN: Visual Pipeline Sequence (width: 350)
                SizedBox(
                  width: 350,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.alt_route_rounded,
                                  color: AppColors.primary, size: 20),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Pipeline (${_steps.length} steps)',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Drag handles to reorder execution flow',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Divider(),
                          Expanded(
                            child: _steps.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.route_outlined,
                                            size: 40,
                                            color: AppColors.textTertiary),
                                        const SizedBox(height: AppSpacing.sm),
                                        const Text('No steps added yet.',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: AppSpacing.xs),
                                        const Text(
                                          'Use the palette on the left to add waypoints or actions.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  )
                                  : ReorderableListView.builder(
                                      buildDefaultDragHandles: false,
                                      itemCount: _steps.length,
                                      onReorderItem: (oldIndex, newIndex) {
                                        setState(() {
                                          final item =
                                              _steps.removeAt(oldIndex);
                                          _steps.insert(newIndex, item);
                                        });
                                      },
                                      itemBuilder: (context, i) => Card(
                                        key: ValueKey(
                                            '$i-${_steps[i].hashCode}'),
                                        margin: const EdgeInsets.only(
                                            bottom: AppSpacing.xs),
                                        color: AppColors.surfaceSunken,
                                        child: ListTile(
                                          dense: true,
                                          onTap: () => _editStep(i),
                                          leading: StepIconChip(step: _steps[i]),
                                          title: Text(
                                              missionStepSummary(_steps[i]),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13)),
                                          subtitle: Text(
                                              'Step ${i + 1} · ${_steps[i]['type']} · Click to edit',
                                              style: const TextStyle(
                                                  color: AppColors.textSecondary,
                                                  fontSize: 11)),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 18,
                                                    color: AppColors.primary),
                                                tooltip: 'Edit step',
                                                onPressed: () => _editStep(i),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.close_rounded,
                                                    size: 18),
                                                tooltip: 'Remove step',
                                                onPressed: () => setState(
                                                    () => _steps.removeAt(i)),
                                              ),
                                              ReorderableDragStartListener(
                                                index: i,
                                                child: const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 4),
                                                  child: Icon(
                                                      Icons.drag_handle_rounded,
                                                      color:
                                                          AppColors.textTertiary,
                                                      size: 20),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, __) {
        if (!didPop) _goBack(false);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back to Missions',
            onPressed: () => _goBack(false),
          ),
          title: Text(_isEditing ? 'Edit Mission' : 'New Mission'),
        ),
        body: SafeArea(
          child: CenteredFormColumn(
            maxWidth: 640,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (routePins.isNotEmpty) _RouteMapCard(pins: routePins),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                        hintText: 'Mission name, e.g. Patrol Route A'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (_missionMap != null &&
                                  _currentActiveMap != null &&
                                  _missionMap != _currentActiveMap)
                              ? AppColors.warning.withValues(alpha: 0.12)
                              : AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (_missionMap != null &&
                                    _currentActiveMap != null &&
                                    _missionMap != _currentActiveMap)
                                ? AppColors.warning.withValues(alpha: 0.4)
                                : AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              (_missionMap != null &&
                                      _currentActiveMap != null &&
                                      _missionMap != _currentActiveMap)
                                  ? Icons.warning_amber_rounded
                                  : Icons.map_outlined,
                              size: 14,
                              color: (_missionMap != null &&
                                      _currentActiveMap != null &&
                                      _missionMap != _currentActiveMap)
                                  ? AppColors.warning
                                  : AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Map: ${_missionMap ?? _currentActiveMap ?? "Active Map"}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (_missionMap != null &&
                                        _currentActiveMap != null &&
                                        _missionMap != _currentActiveMap)
                                    ? AppColors.warning
                                    : AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_missionMap != null &&
                      _currentActiveMap != null &&
                      _missionMap != _currentActiveMap) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Warning: Active map on robot is "$_currentActiveMap". Waypoints may mismatch.',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.warning),
                    ),
                  ],
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
                            buildDefaultDragHandles: false,
                            itemCount: _steps.length,
                            onReorderItem: (oldIndex, newIndex) {
                              setState(() {
                                final item = _steps.removeAt(oldIndex);
                                _steps.insert(newIndex, item);
                              });
                            },
                            itemBuilder: (context, i) => Card(
                              key: ValueKey('$i-${_steps[i].hashCode}'),
                              margin:
                                  const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: ListTile(
                                onTap: () => _editStep(i),
                                leading: StepIconChip(step: _steps[i]),
                                title: Text(missionStepSummary(_steps[i]),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    'Step ${i + 1} · ${_steps[i]['type']} · Tap to edit',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 18, color: AppColors.primary),
                                      tooltip: 'Edit step',
                                      onPressed: () => _editStep(i),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded,
                                          size: 18),
                                      tooltip: 'Remove step',
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
                          onPressed: _saving ? null : () => _goBack(false),
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

class _RouteMapCard extends StatelessWidget {
  const _RouteMapCard({required this.pins});

  final List<Map<String, dynamic>> pins;

  @override
  Widget build(BuildContext context) {
    final ros2 = context.watch<ConnectionProvider>().ros2;
    final telemetry = context.read<RobotTelemetryProvider>();
    if (ros2 == null || pins.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 180,
          child: OccupancyGridView(
            ros2: ros2,
            interactive: false,
            initialPose: telemetry.rawPose,
            initialPath: telemetry.currentPath,
            locations: pins,
            showWaypointRoute: true,
            fitWholeMap: true,
          ),
        ),
      ),
    );
  }
}
