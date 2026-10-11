import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/fleet_provider.dart';

class DispatchFleetTaskDialog extends StatefulWidget {
  const DispatchFleetTaskDialog({
    super.key,
    this.initialCategory = 'patrol',
    this.initialRobotId,
  });

  final String initialCategory;
  final String? initialRobotId;

  static Future<bool?> show(
    BuildContext context, {
    String initialCategory = 'patrol',
    String? initialRobotId,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => DispatchFleetTaskDialog(
        initialCategory: initialCategory,
        initialRobotId: initialRobotId,
      ),
    );
  }

  @override
  State<DispatchFleetTaskDialog> createState() => _DispatchFleetTaskDialogState();
}

class _DispatchFleetTaskDialogState extends State<DispatchFleetTaskDialog> {
  late String _category;
  String? _selectedFleetName;
  String? _selectedRobotName; // null means auto-assign via RMF dispatcher auction

  // Patrol / Go To parameters
  final _patrolPlacesController = TextEditingController(text: 'charger_1');
  int _patrolRounds = 1;

  // Clean parameters
  final _cleanZoneController = TextEditingController(text: 'zone_1');

  // Delivery parameters
  final _pickupController = TextEditingController(text: 'station_a');
  final _dropoffController = TextEditingController(text: 'station_b');

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    final fleet = context.read<FleetProvider>();
    if (fleet.fleets.isNotEmpty) {
      _selectedFleetName = fleet.fleets.first.name;
    } else {
      _selectedFleetName = 'navpromini';
    }

    if (widget.initialRobotId != null) {
      final robot = fleet.robots.where((r) => r.id == widget.initialRobotId).firstOrNull;
      if (robot != null) _selectedRobotName = robot.name;
    }
  }

  @override
  void dispose() {
    _patrolPlacesController.dispose();
    _cleanZoneController.dispose();
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  Future<void> _dispatch() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final fleet = context.read<FleetProvider>();
    try {
      final Map<String, dynamic> description = {};

      if (_category == 'patrol') {
        final rawPlaces = _patrolPlacesController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (rawPlaces.isEmpty) {
          throw Exception('Please specify at least one waypoint for Patrol/GoTo.');
        }
        description['places'] = rawPlaces;
        description['rounds'] = _patrolRounds;
      } else if (_category == 'charge_battery') {
        // empty description is standard for charge_battery in Open-RMF
      } else if (_category == 'clean') {
        final zone = _cleanZoneController.text.trim();
        if (zone.isEmpty) throw Exception('Please specify a zone to clean.');
        description['zone'] = zone;
      } else if (_category == 'delivery') {
        final pickup = _pickupController.text.trim();
        final dropoff = _dropoffController.text.trim();
        if (pickup.isEmpty || dropoff.isEmpty) {
          throw Exception('Please specify both pickup and dropoff locations.');
        }
        description['pickup'] = {
          'place': pickup,
          'handler': 'delivery_handler',
          'payload': [],
        };
        description['dropoff'] = {
          'place': dropoff,
          'handler': 'delivery_handler',
          'payload': [],
        };
      }

      final res = await fleet.dispatchRmfTask(
        category: _category,
        description: description,
        fleetName: _selectedFleetName,
        robotName: _selectedRobotName,
      );

      if (mounted) {
        final taskId = res['state']?['booking']?['id'] ?? 'queued';
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Task dispatched successfully! ID: $taskId'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
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
          Icon(Icons.alt_route_rounded, color: Colors.blue),
          SizedBox(width: 10),
          Text('Dispatch NavPro Mini Fleet Task'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Submit an Open-RMF coordinated task. The fleet server will automatically allocate, negotiate traffic lanes, and assign the best robot.',
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

              // Category Selector Tabs
              const Text('Task Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.repeat_rounded, size: 16),
                    label: const Text('Patrol / Go To'),
                    selected: _category == 'patrol',
                    onSelected: (val) => setState(() => _category = 'patrol'),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.battery_charging_full_rounded, size: 16),
                    label: const Text('Charge Battery'),
                    selected: _category == 'charge_battery',
                    onSelected: (val) => setState(() => _category = 'charge_battery'),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.cleaning_services_rounded, size: 16),
                    label: const Text('Clean'),
                    selected: _category == 'clean',
                    onSelected: (val) => setState(() => _category = 'clean'),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.local_shipping_outlined, size: 16),
                    label: const Text('Delivery'),
                    selected: _category == 'delivery',
                    onSelected: (val) => setState(() => _category = 'delivery'),
                  ),
                ],
              ),
              const Divider(height: 28),

              // Category-specific inputs
              if (_category == 'patrol') ...[
                TextField(
                  controller: _patrolPlacesController,
                  decoration: const InputDecoration(
                    labelText: 'Waypoints / Places *',
                    hintText: 'e.g. charger_1, point_b, office_hallway',
                    helperText: 'Separate multiple patrol waypoints with commas',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Patrol Rounds:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.remove, size: 16),
                      onPressed: _patrolRounds > 1 ? () => setState(() => _patrolRounds--) : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '$_patrolRounds',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add, size: 16),
                      onPressed: () => setState(() => _patrolRounds++),
                    ),
                  ],
                ),
              ] else if (_category == 'charge_battery') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.bolt_rounded, color: Colors.green, size: 24),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sends the robot to its designated docking/charging station to recharge.',
                          style: TextStyle(fontSize: 12, color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_category == 'clean') ...[
                TextField(
                  controller: _cleanZoneController,
                  decoration: const InputDecoration(
                    labelText: 'Cleaning Zone / Waypoint *',
                    hintText: 'e.g. zone_1 or lobby',
                    prefixIcon: Icon(Icons.cleaning_services_outlined),
                  ),
                ),
              ] else if (_category == 'delivery') ...[
                TextField(
                  controller: _pickupController,
                  decoration: const InputDecoration(
                    labelText: 'Pickup Location *',
                    hintText: 'e.g. storage_dock',
                    prefixIcon: Icon(Icons.call_received_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _dropoffController,
                  decoration: const InputDecoration(
                    labelText: 'Dropoff Destination *',
                    hintText: 'e.g. packing_bay',
                    prefixIcon: Icon(Icons.call_made_rounded),
                  ),
                ),
              ],

              const Divider(height: 28),

              // Robot & Fleet Assignment
              const Text('Assignment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _selectedRobotName,
                decoration: const InputDecoration(
                  labelText: 'Assigned Robot',
                  prefixIcon: Icon(Icons.smart_toy_rounded),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Auto-Assign (Open-RMF Fleet Auction)'),
                  ),
                  ...fleet.robots.map((r) {
                    return DropdownMenuItem<String?>(
                      value: r.name,
                      child: Text('${r.name} (${r.status.toUpperCase()})'),
                    );
                  }),
                ],
                onChanged: (val) => setState(() => _selectedRobotName = val),
              ),
              const SizedBox(height: 12),
              if (fleet.fleets.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _selectedFleetName,
                  decoration: const InputDecoration(
                    labelText: 'Fleet Scope',
                    prefixIcon: Icon(Icons.hub_rounded),
                  ),
                  items: fleet.fleets.map((f) {
                    return DropdownMenuItem(value: f.name, child: Text(f.name));
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedFleetName = val),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _dispatch,
          icon: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(_isSubmitting ? 'Dispatching...' : 'Dispatch Task'),
        ),
      ],
    );
  }
}
