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
  late Set<int> _weekdays = {
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
    return Scaffold(
      appBar:
          AppBar(title: Text(_isEditing ? 'Edit Schedule' : 'New Schedule')),
      body: SafeArea(
        child: CenteredFormColumn(
          maxWidth: 560,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text('Mission', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _missionId,
                isExpanded: true,
                hint: const Text('Choose a mission'),
                items: [
                  for (final m in widget.missions)
                    DropdownMenuItem(
                      value: m['id'] as String,
                      child: Text(m['name'] as String? ?? m['id'] as String),
                    ),
                ],
                onChanged: (v) => setState(() => _missionId = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Name (optional)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _nameController,
                decoration:
                    const InputDecoration(hintText: 'Defaults to mission name'),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Time', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time_rounded),
                label: Text(_time.format(context)),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Repeat', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('Once'),
                    selected: _repeat == 'once',
                    onSelected: (_) => setState(() => _repeat = 'once'),
                  ),
                  ChoiceChip(
                    label: const Text('Daily'),
                    selected: _repeat == 'daily',
                    onSelected: (_) => setState(() => _repeat = 'daily'),
                  ),
                  ChoiceChip(
                    label: const Text('Weekly'),
                    selected: _repeat == 'weekly',
                    onSelected: (_) => setState(() => _repeat = 'weekly'),
                  ),
                ],
              ),
              if (_repeat == 'once') ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded),
                  label: Text(
                      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
                ),
              ],
              if (_repeat == 'weekly') ...[
                const SizedBox(height: AppSpacing.sm),
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
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: AppSpacing.lg),
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
                              _isEditing ? 'Save Changes' : 'Create Schedule'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
