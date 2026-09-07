import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../providers/connection_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Create/edit a schedule — pick a mission, a time, and how it repeats
/// (once / daily / specific weekdays), matching handlers/schedules.py's own
/// validation exactly (see SdkApiService.putSchedule's own doc). Runs
/// entirely on the robot (server.py's 20s poll, schedules.check_schedules)
/// — this screen just edits the definition, it isn't what fires it.
class ScheduleEditorScreen extends StatefulWidget {
  const ScheduleEditorScreen({
    super.key,
    this.existing,
    required this.missions,
  });

  final Map<String, dynamic>? existing;

  /// Saved missions to pick from — loaded once by the list screen and
  /// passed in, rather than this screen re-fetching them itself.
  final List<Map<String, dynamic>> missions;

  @override
  State<ScheduleEditorScreen> createState() => _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends State<ScheduleEditorScreen> {
  late final _nameController =
      TextEditingController(text: widget.existing?['name'] as String? ?? '');

  String? _missionId;
  late TimeOfDay _time = _initialTime();
  late String _repeat = widget.existing?['repeat'] as String? ?? 'daily';
  late DateTime _date = _initialDate();
  late final Set<int> _weekdays = {
    for (final d in (widget.existing?['weekdays'] as List? ?? const []))
      d as int,
  };

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  TimeOfDay _initialTime() {
    final h = widget.existing?['hour'] as int?;
    final m = widget.existing?['minute'] as int?;
    if (h == null || m == null) return TimeOfDay.now();
    return TimeOfDay(hour: h, minute: m);
  }

  DateTime _initialDate() {
    final raw = widget.existing?['date'] as String?;
    if (raw != null) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  @override
  void initState() {
    super.initState();
    _missionId = widget.existing?['mission_id'] as String?;
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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(now) ? now : _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_missionId == null) {
      setState(() => _error = 'Pick a mission.');
      return;
    }
    if (_repeat == 'weekly' && _weekdays.isEmpty) {
      setState(() => _error = 'Pick at least one day.');
      return;
    }
    final api = _api;
    if (api == null) return;

    final mission = widget.missions.firstWhere((m) => m['id'] == _missionId);
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : mission['name'] as String? ?? 'Schedule';

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = widget.existing?['id'] as String? ?? const Uuid().v4();
      await api.putSchedule(
        id,
        missionId: _missionId!,
        name: name,
        hour: _time.hour,
        minute: _time.minute,
        repeat: _repeat,
        date: _repeat == 'once'
            ? '${_date.year.toString().padLeft(4, '0')}-'
                '${_date.month.toString().padLeft(2, '0')}-'
                '${_date.day.toString().padLeft(2, '0')}'
            : null,
        weekdays: _repeat == 'weekly' ? _weekdays.toList() : const [],
        enabled: widget.existing?['enabled'] as bool? ?? true,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;
    final selectedMission = widget.missions
        .cast<Map<String, dynamic>?>()
        .firstWhere((m) => m?['id'] == _missionId, orElse: () => null);

    final formContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Mission Picker Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.alt_route_rounded,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Mission to Execute',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _missionId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select Mission',
                    hintText: 'Choose a mission from your library',
                    prefixIcon: Icon(Icons.list_alt_rounded),
                  ),
                  items: [
                    for (final m in widget.missions)
                      DropdownMenuItem(
                        value: m['id'] as String,
                        child: Text(
                          '${m['name'] as String? ?? m['id'] as String} (${(m['steps'] as List? ?? const []).length} steps${m['map'] != null ? ' · Map: ${m['map']}' : ''})',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _missionId = v),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Schedule Title (Optional)',
                    hintText: 'e.g. Morning Patrol',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // 2. Frequency & Recurrence Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.repeat_rounded,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Recurrence & Frequency',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    ChoiceChip(
                      label: const Text('Daily'),
                      selected: _repeat == 'daily',
                      onSelected: (_) => setState(() => _repeat = 'daily'),
                    ),
                    ChoiceChip(
                      label: const Text('Weekly Days'),
                      selected: _repeat == 'weekly',
                      onSelected: (_) => setState(() => _repeat = 'weekly'),
                    ),
                    ChoiceChip(
                      label: const Text('One-time Run'),
                      selected: _repeat == 'once',
                      onSelected: (_) => setState(() => _repeat = 'once'),
                    ),
                  ],
                ),
                if (_repeat == 'once') ...[
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(
                        'Date: ${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
                  ),
                ],
                if (_repeat == 'weekly') ...[
                  const SizedBox(height: AppSpacing.md),
                  const Text('Repeat on days:',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      for (var i = 0; i < 7; i++)
                        FilterChip(
                          label: Text(_weekdayLabels[i]),
                          selected: _weekdays.contains(i),
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              _weekdays.add(i);
                            } else {
                              _weekdays.remove(i);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // 3. Time Picker Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Trigger Time',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _time.format(context),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: const Text('Change Time'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    ActionChip(
                      label: const Text('08:00 AM'),
                      onPressed: () => setState(() =>
                          _time = const TimeOfDay(hour: 8, minute: 0)),
                    ),
                    ActionChip(
                      label: const Text('12:00 PM'),
                      onPressed: () => setState(() =>
                          _time = const TimeOfDay(hour: 12, minute: 0)),
                    ),
                    ActionChip(
                      label: const Text('06:00 PM'),
                      onPressed: () => setState(() =>
                          _time = const TimeOfDay(hour: 18, minute: 0)),
                    ),
                    ActionChip(
                      label: const Text('10:00 PM'),
                      onPressed: () => setState(() =>
                          _time = const TimeOfDay(hour: 22, minute: 0)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );

    // Live preview string
    final repeatSummary = _repeat == 'daily'
        ? 'Every day'
        : _repeat == 'weekly'
            ? 'Every ${_weekdays.isEmpty ? "week" : _weekdays.map((d) => _weekdayLabels[d]).join(", ")}'
            : 'Once on ${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

    final missionTitle = selectedMission?['name'] as String? ??
        (selectedMission?['id'] as String?) ??
        'None selected';

    final previewCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.preview_rounded,
                    size: 20, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Schedule Summary',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Robotic Automation Task:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The robot will autonomously start "$missionTitle" at ${_time.format(context)} ($repeatSummary).',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (selectedMission != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Icon(Icons.alt_route_rounded,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Route steps: ${(selectedMission['steps'] as List? ?? const []).length} steps configured',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
            const Spacer(),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: AppSpacing.sm),
            ],
            SizedBox(
              height: 44,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.textOnPrimary),
                      )
                    : const Icon(Icons.check_rounded, size: 20),
                label: Text(
                  _isEditing ? 'Save Changes' : 'Create Schedule',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 38,
              width: double.infinity,
              child: OutlinedButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Schedule' : 'New Schedule'),
      ),
      body: SafeArea(
        child: isDesktop
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(child: formContent),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(
                      flex: 4,
                      child: previewCard,
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  formContent,
                  const SizedBox(height: AppSpacing.lg),
                  previewCard,
                ],
              ),
      ),
    );
  }
}
