import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/fleet_provider.dart';

class AddFleetRobotDialog extends StatefulWidget {
  const AddFleetRobotDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const AddFleetRobotDialog(),
    );
  }

  @override
  State<AddFleetRobotDialog> createState() => _AddFleetRobotDialogState();
}

class _AddFleetRobotDialogState extends State<AddFleetRobotDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _serialController = TextEditingController();
  final _dockController = TextEditingController(text: 'charger_1');

  String? _selectedFleetId;
  String? _selectedLevelId;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final fleet = context.read<FleetProvider>();
    if (fleet.fleets.isNotEmpty) {
      _selectedFleetId = fleet.fleets.first.id;
    }
    if (fleet.levels.isNotEmpty) {
      _selectedLevelId = fleet.levels.first.id;
    }
    final nextNum = fleet.robots.length + 1;
    _nameController.text = 'NavPro Mini $nextNum';
    _serialController.text = 'navpro_mini_${nextNum.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serialController.dispose();
    _dockController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final fleet = context.read<FleetProvider>();
    try {
      await fleet.createRobot(
        serial: _serialController.text.trim(),
        name: _nameController.text.trim(),
        fleetId: _selectedFleetId,
        levelId: _selectedLevelId,
        dockWaypoint: _dockController.text.trim(),
        homeWaypoint: _dockController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Robot "${_nameController.text.trim()}" successfully registered to fleet!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetProvider>();

    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.smart_toy_rounded, color: Colors.blue),
          SizedBox(width: 10),
          Text('Add Robot to Fleet'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Register a NavPro Mini AMR into the fleet coordinator to enable Open-RMF traffic management and multi-robot task dispatching.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Robot Display Name *',
                    hintText: 'e.g. NavPro Mini 01',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a robot name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _serialController,
                  decoration: const InputDecoration(
                    labelText: 'Serial Number / Unique ID *',
                    hintText: 'e.g. navpro_mini_01',
                    prefixIcon: Icon(Icons.fingerprint_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a serial number' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedFleetId,
                  decoration: const InputDecoration(
                    labelText: 'Assigned Fleet',
                    prefixIcon: Icon(Icons.hub_rounded),
                  ),
                  items: fleet.fleets.map((f) {
                    return DropdownMenuItem(value: f.id, child: Text(f.name));
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedFleetId = val),
                  validator: (v) => v == null ? 'Please select a fleet' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedLevelId,
                  decoration: const InputDecoration(
                    labelText: 'Starting Floor / Level',
                    prefixIcon: Icon(Icons.layers_rounded),
                  ),
                  items: fleet.levels.map((l) {
                    return DropdownMenuItem(value: l.id, child: Text(l.name));
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedLevelId = val),
                  validator: (v) => v == null ? 'Please select a floor level' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dockController,
                  decoration: const InputDecoration(
                    labelText: 'Home / Charger Waypoint',
                    hintText: 'e.g. charger_1 or dock_a',
                    prefixIcon: Icon(Icons.battery_charging_full_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(Icons.info_outline, color: Colors.blue, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hardware Tip: On the physical robot, point its Zenoh bridge / ROS 2 domain to this fleet server host. Online robots will automatically begin reporting AMCL pose & battery.',
                          style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          icon: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.add_task_rounded, size: 18),
          label: Text(_isSubmitting ? 'Registering...' : 'Register Robot'),
        ),
      ],
    );
  }
}
