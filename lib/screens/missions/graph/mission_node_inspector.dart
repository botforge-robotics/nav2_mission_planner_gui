import 'package:flutter/material.dart';
import '../../../services/locations_controller.dart';
import '../../../theme/app_theme.dart';
import 'mission_graph_models.dart';

/// Contextual Properties Inspector & Dynamic Form Builder for the selected node.
class MissionNodeInspector extends StatefulWidget {
  const MissionNodeInspector({
    super.key,
    required this.node,
    required this.onChanged,
    this.readOnly = false,
  });

  final GraphNode node;
  final VoidCallback onChanged;
  final bool readOnly;

  @override
  State<MissionNodeInspector> createState() => _MissionNodeInspectorState();
}

class _MissionNodeInspectorState extends State<MissionNodeInspector>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _labelController = TextEditingController(text: widget.node.label);
  }

  @override
  void didUpdateWidget(covariant MissionNodeInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _labelController.text = widget.node.label;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isUiInteraction = node.type == 'ui_interaction';

    return Container(
      width: 320,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Inspector: ${node.type}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tabs (Properties vs Preview for UI interaction)
          if (isUiInteraction)
            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: const [
                Tab(text: 'Properties'),
                Tab(text: 'Live Preview'),
              ],
            ),

          // Body
          Expanded(
            child: isUiInteraction
                ? TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPropertiesList(),
                      _buildLiveFormPreview(),
                    ],
                  )
                : _buildPropertiesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertiesList() {
    final node = widget.node;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Node Label
        TextField(
          controller: _labelController,
          enabled: !widget.readOnly,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Node Label',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (val) {
            node.label = val;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),

        // Type specific inspectors
        if (node.type == 'navigate_waypoint')
          _buildNavigateWaypointInspector()
        else if (node.type == 'navigate_coordinates')
          _buildNavigateCoordinatesInspector()
        else if (node.type == 'wait')
          _buildWaitInspector()
        else if (node.type == 'condition')
          _buildConditionInspector()
        else if (node.type == 'call_api')
          _buildCallApiInspector()
        else if (node.type == 'ui_interaction')
          _buildUiInteractionInspector()
        else if (node.type == 'notify')
          _buildNotifyInspector()
        else if (node.type == 'end' || node.type == 'mission_end')
          _buildEndMissionInspector()
        else if (node.type == 'loop' || node.type == 'loop_counter')
          _buildLoopInspector()
        else if (node.type == 'battery_guard')
          _buildBatteryGuardInspector()
        else if (node.type == 'patrol_loop')
          _buildPatrolLoopInspector()
        else if (node.type == 'ui_media')
          _buildUiMediaInspector()
        else if (node.type == 'ui_speech')
          _buildUiSpeechInspector()
        else
          Text(
            'Node ID: ${node.id}\nNo extra parameters required.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
      ],
    );
  }

  Widget _buildNavigateWaypointInspector() {
    final waypoints = LocationsController.instance.value ?? const <Map<String, dynamic>>[];
    final currentWp = widget.node.params['waypoint'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Target Waypoint', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_wp_$currentWp'),
          isExpanded: true,
          initialValue: waypoints.any((w) => w['name'] == currentWp) ? currentWp : null,
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          hint: const Text('Select a waypoint', style: TextStyle(color: AppColors.textSecondary)),
          items: [
            for (final wp in waypoints)
              DropdownMenuItem(
                value: wp['name']?.toString() ?? '',
                child: Text(
                  '${wp['name']} (x: ${(wp['x'] as num?)?.toStringAsFixed(1) ?? '0.0'}, y: ${(wp['y'] as num?)?.toStringAsFixed(1) ?? '0.0'})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() {
                    widget.node.params['waypoint'] = val;
                  });
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 16),
        _buildNumberSlider(
          label: 'Goal Tolerance (meters)',
          value: (widget.node.params['tolerance_m'] as num?)?.toDouble() ?? 0.25,
          min: 0.05,
          max: 1.0,
          divisions: 19,
          onChanged: (v) {
            widget.node.params['tolerance_m'] = v;
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildNavigateCoordinatesInspector() {
    final x = (widget.node.params['x'] as num?)?.toDouble() ?? 0.0;
    final y = (widget.node.params['y'] as num?)?.toDouble() ?? 0.0;
    final theta = (widget.node.params['theta'] as num?)?.toDouble() ?? 0.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: x.toString(),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'X (meters)',
                  labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.surfaceSunken,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                ),
                onChanged: (v) {
                  widget.node.params['x'] = double.tryParse(v) ?? 0.0;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: y.toString(),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Y (meters)',
                  labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.surfaceSunken,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                ),
                onChanged: (v) {
                  widget.node.params['y'] = double.tryParse(v) ?? 0.0;
                  widget.onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: theta.toString(),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Orientation (Theta radians)',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['theta'] = double.tryParse(v) ?? 0.0;
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildWaitInspector() {
    final dur = (widget.node.params['duration_sec'] as num?)?.toDouble() ?? 5.0;

    return _buildNumberSlider(
      label: 'Duration (seconds)',
      value: dur,
      min: 1.0,
      max: 60.0,
      divisions: 59,
      onChanged: (v) {
        widget.node.params['duration_sec'] = v;
        widget.onChanged();
      },
    );
  }

  Widget _buildConditionInspector() {
    final expr = widget.node.params['expression'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: expr,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Expression',
            hintText: 'e.g. form.status == "Pass"',
            hintStyle: const TextStyle(color: AppColors.textTertiary),
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['expression'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 10),
        const Text(
          'Quick Token Helpers:',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildTokenChip('form.status == "Pass"'),
            _buildTokenChip('system.battery_pct < 20'),
            _buildTokenChip('form.damaged == True'),
          ],
        ),
      ],
    );
  }

  Widget _buildTokenChip(String token) {
    return ActionChip(
      backgroundColor: AppColors.surfaceSunken,
      side: const BorderSide(color: AppColors.border),
      label: Text(token, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w500)),
      onPressed: widget.readOnly
          ? null
          : () {
              setState(() {
                widget.node.params['expression'] = token;
              });
              widget.onChanged();
            },
    );
  }

  Widget _buildUiInteractionInspector() {
    final subtype = widget.node.params['subtype'] as String? ?? 'dynamic_form';
    final title = widget.node.params['title'] as String? ?? 'Operator Input';
    final timeout = (widget.node.params['timeout_sec'] as num?)?.toDouble() ?? 60.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Subtype Dropdown
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_subtype_$subtype'),
          isExpanded: true,
          initialValue: ['dynamic_form', 'choice', 'media_display', 'speech', 'kiosk'].contains(subtype) ? subtype : 'dynamic_form',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'UI Presentation Subtype',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(value: 'dynamic_form', child: Text('Dynamic Multi-Field Form', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'choice', child: Text('Action Buttons / Choices', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'media_display', child: Text('Media Display (Image/Video)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'speech', child: Text('Voice / TTS Announcement', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'kiosk', child: Text('Destination Kiosk Picker', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() {
                    widget.node.params['subtype'] = val;
                  });
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),

        // Target Display Surface Dropdown
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_target_${widget.node.params['target']}'),
          isExpanded: true,
          initialValue: ['robot_screen', 'operator_app', 'both'].contains(widget.node.params['target'])
              ? widget.node.params['target']
              : 'robot_screen',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Target Display Device',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(value: 'robot_screen', child: Text('Robot Touchscreen (Onboard)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'operator_app', child: Text('Operator Console (Remote App)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'both', child: Text('Both Displays (Robot + Operator)', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() {
                    widget.node.params['target'] = val;
                  });
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),

        TextFormField(
          initialValue: title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Dialog Title',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['title'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),

        _buildNumberSlider(
          label: 'Timeout (seconds)',
          value: timeout,
          min: 10.0,
          max: 300.0,
          divisions: 29,
          onChanged: (v) {
            widget.node.params['timeout_sec'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),

        // Subtype specific builders
        if (subtype == 'dynamic_form') _buildDynamicFormFieldsEditor(),
        if (subtype == 'choice') _buildChoiceOptionsEditor(),
        if (subtype == 'media_display') _buildMediaUrlEditor(),
      ],
    );
  }

  Widget _buildDynamicFormFieldsEditor() {
    final rawFields = (widget.node.params['fields'] as List? ?? []);
    final fields = [
      for (final f in rawFields)
        if (f is Map<String, dynamic>) FormFieldDef.fromJson(f)
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Form Fields',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            if (!widget.readOnly)
              TextButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Field', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                onPressed: () {
                  setState(() {
                    final newField = FormFieldDef(
                      key: 'field_${fields.length + 1}',
                      label: 'Question ${fields.length + 1}',
                      type: 'text',
                    );
                    fields.add(newField);
                    widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                  });
                  widget.onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < fields.length; i++)
          Card(
            color: AppColors.surfaceElevated,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border),
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: fields[i].label,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Field Label',
                            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            filled: true,
                            fillColor: AppColors.surfaceSunken,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                          ),
                          onChanged: (v) {
                            fields[i].label = v;
                            widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                            widget.onChanged();
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textTertiary),
                        onPressed: widget.readOnly
                            ? null
                            : () {
                                setState(() {
                                  fields.removeAt(i);
                                  widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                                });
                                widget.onChanged();
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('${widget.node.id}_field_${i}_${fields[i].type}'),
                          isExpanded: true,
                          initialValue: ['text', 'number', 'select', 'checkbox', 'switch', 'signature'].contains(fields[i].type) ? fields[i].type : 'text',
                          dropdownColor: AppColors.surface,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500),
                          isDense: true,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Type',
                            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            filled: true,
                            fillColor: AppColors.surfaceSunken,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'text', child: Text('Text', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'number', child: Text('Number', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'select', child: Text('Dropdown / Select', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'checkbox', child: Text('Checkbox', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'switch', child: Text('Switch', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'signature', child: Text('Signature', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: widget.readOnly
                              ? null
                              : (v) {
                                  setState(() {
                                    fields[i].type = v ?? 'text';
                                    widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                                  });
                                  widget.onChanged();
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Checkbox(
                        value: fields[i].required,
                        activeColor: AppColors.primary,
                        onChanged: widget.readOnly
                            ? null
                            : (v) {
                                setState(() {
                                  fields[i].required = v ?? false;
                                  widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                                });
                                widget.onChanged();
                              },
                      ),
                      const Text('Req', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChoiceOptionsEditor() {
    final options = (widget.node.params['options'] as List? ?? ['Yes', 'No']).map((e) => e.toString()).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Action Buttons', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
            if (!widget.readOnly)
              TextButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Option', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                onPressed: () {
                  setState(() {
                    options.add('Option ${options.length + 1}');
                    widget.node.params['options'] = options;
                  });
                  widget.onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: options[i],
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surfaceSunken,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                    onChanged: (v) {
                      options[i] = v;
                      widget.node.params['options'] = options;
                      widget.onChanged();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textTertiary),
                  onPressed: widget.readOnly
                      ? null
                      : () {
                          setState(() {
                            options.removeAt(i);
                            widget.node.params['options'] = options;
                          });
                          widget.onChanged();
                        },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMediaUrlEditor() {
    final mediaUrl = widget.node.params['media_url'] as String? ?? '';

    return TextFormField(
      initialValue: mediaUrl,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: 'Media / Image URL',
        hintText: 'https://...',
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      ),
      onChanged: (v) {
        widget.node.params['media_url'] = v;
        widget.onChanged();
      },
    );
  }

  Widget _buildCallApiInspector() {
    final method = widget.node.params['method'] as String? ?? 'POST';
    final url = widget.node.params['url'] as String? ?? '';

    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_method_$method'),
          isExpanded: true,
          initialValue: ['GET', 'POST', 'PUT', 'DELETE'].contains(method) ? method : 'POST',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'HTTP Method',
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(value: 'GET', child: Text('GET')),
            DropdownMenuItem(value: 'POST', child: Text('POST')),
            DropdownMenuItem(value: 'PUT', child: Text('PUT')),
            DropdownMenuItem(value: 'DELETE', child: Text('DELETE')),
          ],
          onChanged: widget.readOnly
              ? null
              : (v) {
                  widget.node.params['method'] = v;
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: url,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Endpoint URL',
            hintText: 'https://...',
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['url'] = v;
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildNotifyInspector() {
    final oled = widget.node.params['oled_text'] as String? ?? '';
    final led = widget.node.params['led_cmd'] as String? ?? '';

    return Column(
      children: [
        TextFormField(
          initialValue: oled,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'OLED Text Banner',
            hintText: 'e.g. INSPECTION DONE',
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['oled_text'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: led,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'LED Command',
            hintText: 'solid,0,200,40',
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['led_cmd'] = v;
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildLiveFormPreview() {
    final title = widget.node.params['title'] as String? ?? 'Form Preview';
    final rawFields = (widget.node.params['fields'] as List? ?? []);
    final fields = [
      for (final f in rawFields)
        if (f is Map<String, dynamic>) FormFieldDef.fromJson(f)
    ];

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(16),
      child: Card(
        color: AppColors.surface,
        elevation: 2,
        shadowColor: AppColors.shadowTint.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Divider(color: AppColors.border),
              if (fields.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No fields configured yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: fields.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final f = fields[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${f.label}${f.required ? ' *' : ''}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          if (f.type == 'switch')
                            Switch(value: false, activeThumbColor: AppColors.primary, onChanged: (_) {})
                          else if (f.type == 'checkbox')
                            Checkbox(value: false, activeColor: AppColors.primary, onChanged: (_) {})
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSunken,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                f.type == 'select' ? 'Select from options...' : 'Enter ${f.label.toLowerCase()}...',
                                style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {},
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
                ),
                child: const Text('Submit Form'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEndMissionInspector() {
    final status = widget.node.params['status'] as String? ?? 'success';
    final message = widget.node.params['message'] as String? ?? 'Mission completed successfully.';
    final dockOnEnd = widget.node.params['dock_on_end'] as bool? ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_status_$status'),
          isExpanded: true,
          initialValue: ['success', 'failed', 'aborted'].contains(status) ? status : 'success',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Terminal Mission Status',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(value: 'success', child: Text('Success (Clean Finish)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'failed', child: Text('Failed (Error Termination)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'aborted', child: Text('Aborted (Operator Exit)', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() => widget.node.params['status'] = val);
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: message,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Completion Message / Summary',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['message'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-Dock on End', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          subtitle: const Text('Send robot to AprilTag charger upon mission completion', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          value: dockOnEnd,
          activeThumbColor: AppColors.primary,
          onChanged: widget.readOnly
              ? null
              : (v) {
                  setState(() => widget.node.params['dock_on_end'] = v);
                  widget.onChanged();
                },
        ),
      ],
    );
  }

  Widget _buildLoopInspector() {
    final count = (widget.node.params['count'] as num?)?.toInt() ?? 3;
    final varName = widget.node.params['variable_name'] as String? ?? 'loop_index';
    final condition = widget.node.params['condition'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNumberSlider(
          label: 'Loop Iteration Count',
          value: count.toDouble(),
          min: 1.0,
          max: 50.0,
          divisions: 49,
          onChanged: (v) {
            setState(() => widget.node.params['count'] = v.toInt());
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: varName,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Loop Index Variable Name',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            helperText: 'Injected into context (0..N-1) for templates & conditions',
            helperStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['variable_name'] = v.trim();
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: condition,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'While Condition (Optional)',
            hintText: 'e.g. form.keep_going == true',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            helperText: 'If provided, loop exits if condition evaluates to false',
            helperStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['condition'] = v.trim();
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildBatteryGuardInspector() {
    final minPct = (widget.node.params['min_battery_pct'] as num?)?.toDouble() ?? 20.0;
    final requireCharging = widget.node.params['require_charging'] as bool? ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNumberSlider(
          label: 'Minimum Battery Required (%)',
          value: minPct,
          min: 5.0,
          max: 95.0,
          divisions: 18,
          onChanged: (v) {
            setState(() => widget.node.params['min_battery_pct'] = v);
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Require Charger Contact', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          subtitle: const Text('Robot must currently be docked/charging to pass "ok"', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          value: requireCharging,
          activeThumbColor: AppColors.primary,
          onChanged: widget.readOnly
              ? null
              : (v) {
                  setState(() => widget.node.params['require_charging'] = v);
                  widget.onChanged();
                },
        ),
      ],
    );
  }

  Widget _buildPatrolLoopInspector() {
    final rawWps = widget.node.params['waypoints'] as List? ?? [];
    final waypoints = rawWps.map((e) => e.toString()).toList();
    final laps = (widget.node.params['laps'] as num?)?.toInt() ?? 1;
    final dwell = (widget.node.params['dwell_sec'] as num?)?.toDouble() ?? 2.0;
    final availableLocations = LocationsController.instance.value ?? const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Patrol Waypoints Order', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_location_alt_outlined, size: 18, color: AppColors.primary),
              tooltip: 'Add Waypoint to Patrol',
              onSelected: (wpName) {
                setState(() {
                  waypoints.add(wpName);
                  widget.node.params['waypoints'] = waypoints;
                });
                widget.onChanged();
              },
              itemBuilder: (ctx) => [
                for (final loc in availableLocations)
                  PopupMenuItem(
                    value: loc['name']?.toString() ?? '',
                    child: Text(loc['name']?.toString() ?? ''),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (waypoints.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text('No waypoints added yet. Tap icon above to add patrol stops.', style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
          )
        else
          Column(
            children: [
              for (int i = 0; i < waypoints.length; i++)
                Container(
                  key: ValueKey('${waypoints[i]}_$i'),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Text('${i + 1}.', style: const TextStyle(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(waypoints[i], style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
                      if (i > 0)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.arrow_upward, size: 14, color: AppColors.textSecondary),
                          onPressed: () {
                            setState(() {
                              final item = waypoints.removeAt(i);
                              waypoints.insert(i - 1, item);
                              widget.node.params['waypoints'] = waypoints;
                            });
                            widget.onChanged();
                          },
                        ),
                      if (i < waypoints.length - 1)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.arrow_downward, size: 14, color: AppColors.textSecondary),
                          onPressed: () {
                            setState(() {
                              final item = waypoints.removeAt(i);
                              waypoints.insert(i + 1, item);
                              widget.node.params['waypoints'] = waypoints;
                            });
                            widget.onChanged();
                          },
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close, size: 16, color: AppColors.danger),
                        onPressed: () {
                          setState(() {
                            waypoints.removeAt(i);
                            widget.node.params['waypoints'] = waypoints;
                          });
                          widget.onChanged();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        _buildNumberSlider(
          label: 'Patrol Laps (0 = Infinite)',
          value: laps.toDouble(),
          min: 0.0,
          max: 20.0,
          divisions: 20,
          onChanged: (v) {
            setState(() => widget.node.params['laps'] = v.toInt());
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildNumberSlider(
          label: 'Dwell Time per Point (seconds)',
          value: dwell,
          min: 0.0,
          max: 30.0,
          divisions: 30,
          onChanged: (v) {
            setState(() => widget.node.params['dwell_sec'] = v);
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildUiMediaInspector() {
    final mediaType = widget.node.params['media_type'] as String? ?? 'image';
    final url = widget.node.params['url'] as String? ?? '';
    final duration = (widget.node.params['duration_sec'] as num?)?.toDouble() ?? 15.0;
    final showSkip = widget.node.params['show_skip'] as bool? ?? true;
    final target = widget.node.params['target'] as String? ?? 'robot_screen';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_media_type_$mediaType'),
          isExpanded: true,
          initialValue: ['image', 'video', 'web_url'].contains(mediaType) ? mediaType : 'image',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Media Format',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(value: 'image', child: Text('Image Poster (PNG/JPG)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'video', child: Text('Video Stream / Clip (MP4)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'web_url', child: Text('Interactive Web URL / Dashboard', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() => widget.node.params['media_type'] = val);
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_media_target_$target'),
          isExpanded: true,
          initialValue: ['robot_screen', 'operator_app', 'both'].contains(target) ? target : 'robot_screen',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Target Display Device',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(value: 'robot_screen', child: Text('Robot Touchscreen (Onboard)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'operator_app', child: Text('Operator Console (Remote App)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'both', child: Text('Both Displays', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() => widget.node.params['target'] = val);
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: url,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Resource URL',
            hintText: 'https://example.com/asset.jpg',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['url'] = v.trim();
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildNumberSlider(
          label: 'Display Duration (seconds)',
          value: duration,
          min: 5.0,
          max: 120.0,
          divisions: 23,
          onChanged: (v) {
            setState(() => widget.node.params['duration_sec'] = v);
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show Skip Button', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          subtitle: const Text('Allows user on screen to dismiss early', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          value: showSkip,
          activeThumbColor: AppColors.primary,
          onChanged: widget.readOnly
              ? null
              : (v) {
                  setState(() => widget.node.params['show_skip'] = v);
                  widget.onChanged();
                },
        ),
      ],
    );
  }

  Widget _buildUiSpeechInspector() {
    final text = widget.node.params['text'] as String? ?? '';
    final wait = widget.node.params['wait_completion'] as bool? ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: text,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Text to Speak (TTS)',
            hintText: 'e.g. NavPro Mini has arrived. Please collect your items.',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            helperText: 'Supports variables e.g. {{context.form.inspector_name}}',
            helperStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['text'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Wait Until Finished Speaking', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          subtitle: const Text('Pause mission execution until TTS audio finishes', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          value: wait,
          activeThumbColor: AppColors.primary,
          onChanged: widget.readOnly
              ? null
              : (v) {
                  setState(() => widget.node.params['wait_completion'] = v);
                  widget.onChanged();
                },
        ),
      ],
    );
  }

  Widget _buildNumberSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            Text(value.toStringAsFixed(1), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppColors.primary,
          inactiveColor: AppColors.borderStrong,
          onChanged: widget.readOnly ? null : onChanged,
        ),
      ],
    );
  }
}
