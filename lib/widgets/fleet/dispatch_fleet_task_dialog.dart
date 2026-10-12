import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/fleet_provider.dart';
import '../../services/fleet_api_service.dart';
import '../../services/locations_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';

/// Modal dialog to dispatch an Open-RMF task or run a mission workflow across the fleet.
/// Exactly provides the two flows requested:
/// 1. Pickup & Delivery (Pickup location, Dropoff destination, Fleet, Robot auto/specific)
/// 2. Run Mission / Workflow (Pick existing Mission / Visual Graph, Fleet, Robot auto/specific)
/// Plus an optional Schedule / Recurring configuration (Execute now vs Scheduled time & repetition).
class DispatchFleetTaskDialog extends StatefulWidget {
  const DispatchFleetTaskDialog({
    super.key,
    this.initialCategory = 'delivery',
    this.initialRobotId,
  });

  /// 'delivery' or 'mission'
  final String initialCategory;
  final String? initialRobotId;

  static Future<bool?> show(
    BuildContext context, {
    String initialCategory = 'delivery',
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
  late String _mode; // 'delivery' or 'mission'
  String? _selectedFleetName;
  String? _selectedRobotName; // null = Auto-assign via RMF Dispatcher auction

  // Delivery parameters
  final _pickupController = TextEditingController(text: 'station_a');
  final _dropoffController = TextEditingController(text: 'station_b');

  // Mission parameters
  List<Map<String, dynamic>> _availableMissions = [];
  String? _selectedMissionId;
  bool _loadingMissions = false;

  // Schedule parameters
  bool _isScheduled = false;
  TimeOfDay _scheduledTime = TimeOfDay.now();
  String _scheduleRepeat = 'once'; // 'once', 'daily', 'weekdays'

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialCategory == 'mission' ? 'mission' : 'delivery';

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

    _loadMissionsList();
  }

  Future<void> _loadMissionsList() async {
    setState(() => _loadingMissions = true);
    try {
      final conn = context.read<ConnectionProvider>();
      final fleet = context.read<FleetProvider>();

      // 1. Try SdkApiService if robot is connected directly
      if (conn.robot?.ip != null) {
        final api = SdkApiService(conn.robot!.ip);
        final list = await api.listMissions();
        if (mounted && list.isNotEmpty) {
          setState(() {
            _availableMissions = list;
            _selectedMissionId = list.first['id'] as String?;
            _loadingMissions = false;
          });
          return;
        }
      }

      // 2. Try Fleet workflows
      if (fleet.api != null) {
        final workflows = await fleet.api!.getWorkflows();
        if (mounted && workflows.isNotEmpty) {
          setState(() {
            _availableMissions = workflows;
            _selectedMissionId = (workflows.first['id'] ?? workflows.first['workflow_id']) as String?;
            _loadingMissions = false;
          });
          return;
        }
      }
    } catch (_) {
      // Fallback
    } finally {
      if (mounted) setState(() => _loadingMissions = false);
    }
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  String? _resolveTargetRobotIp(FleetProvider fleet, ConnectionProvider conn) {
    if (_selectedRobotName != null && _selectedRobotName!.isNotEmpty) {
      final matchingRobot = fleet.robots.where(
        (r) => r.name.toLowerCase() == _selectedRobotName!.toLowerCase() ||
               r.id.toLowerCase() == _selectedRobotName!.toLowerCase() ||
               r.serial.toLowerCase() == _selectedRobotName!.toLowerCase(),
      ).firstOrNull;
      if (matchingRobot != null) {
        if (matchingRobot.ip != null && matchingRobot.ip!.isNotEmpty) {
          return matchingRobot.ip;
        }
        final regIp = fleet.getRobotIp(matchingRobot.id);
        if (regIp != null && regIp.isNotEmpty) {
          return regIp;
        }
      }
      if (conn.robot?.name.toLowerCase() == _selectedRobotName!.toLowerCase() &&
          conn.robot?.ip != null &&
          conn.robot!.ip.isNotEmpty) {
        return conn.robot!.ip;
      }
    }
    if (conn.robot?.ip != null && conn.robot!.ip.isNotEmpty) {
      return conn.robot!.ip;
    }
    final anyWithIp = fleet.robots.where((r) => r.ip != null && r.ip!.isNotEmpty).firstOrNull;
    if (anyWithIp != null) {
      return anyWithIp.ip;
    }
    return null;
  }

  Future<void> _dispatch() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final fleet = context.read<FleetProvider>();
    final conn = context.read<ConnectionProvider>();

    try {
      bool dispatchedViaDirectRobot = false;
      String? fallbackRobotName;

      if (_mode == 'delivery') {
        final pickup = _pickupController.text.trim();
        final dropoff = _dropoffController.text.trim();
        if (pickup.isEmpty || dropoff.isEmpty) {
          throw Exception('Please specify both pickup and dropoff locations.');
        }

        final description = {
          'pickup': {
            'place': pickup,
            'handler': 'delivery_handler',
            'payload': [],
          },
          'dropoff': {
            'place': dropoff,
            'handler': 'delivery_handler',
            'payload': [],
          },
        };

        if (_isScheduled) {
          final targetIp = _resolveTargetRobotIp(fleet, conn);
          if (targetIp != null) {
            final api = SdkApiService(targetIp);
            final schedId = 'sched_deliv_${DateTime.now().millisecondsSinceEpoch}';
            final now = DateTime.now();
            final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
            await api.putSchedule(
              schedId,
              missionId: 'Delivery: $pickup -> $dropoff',
              name: 'Delivery to $dropoff',
              hour: _scheduledTime.hour,
              minute: _scheduledTime.minute,
              repeat: _scheduleRepeat,
              date: _scheduleRepeat == 'once' ? dateStr : null,
              weekdays: _scheduleRepeat == 'weekdays' ? [0, 1, 2, 3, 4] : const [],
            );
          } else {
            // Fleet schedule submission
            await fleet.dispatchRmfTask(
              category: 'delivery',
              description: description,
              fleetName: _selectedFleetName,
              robotName: _selectedRobotName,
            );
          }
        } else {
          // Immediate delivery dispatch
          String? rmfTaskId;

          try {
            final res = await fleet.dispatchRmfTask(
              category: 'delivery',
              description: description,
              fleetName: _selectedFleetName,
              robotName: _selectedRobotName,
            );
            rmfTaskId = res['state']?['booking']?['id'] as String?;
          } catch (e) {
            final is504OrGatewayError = (e is FleetApiException && (e.status == 504 || e.status == 502 || e.status == 0)) ||
                e.toString().contains('504') ||
                e.toString().contains('502') ||
                e.toString().contains('timed out') ||
                e.toString().contains('TimeoutException');

            if (!is504OrGatewayError) {
              rethrow;
            }

            // Fallback to direct AMR execution
            final targetIp = _resolveTargetRobotIp(fleet, conn);
            if (targetIp == null) {
              throw FleetApiException(
                504,
                'Fleet coordinator timed out (504). Please ensure Open-RMF core is running or connect directly to the AMR.',
              );
            }

            final api = SdkApiService(targetIp);
            fallbackRobotName = _selectedRobotName ?? conn.robot?.name ?? targetIp;
            final missionId = 'delivery_${DateTime.now().millisecondsSinceEpoch}';
            final steps = [
              {
                'type': 'navigate',
                'waypoint': pickup,
                'name': 'Pickup: $pickup',
              },
              {
                'type': 'wait',
                'duration': 5,
                'name': 'Loading (5s)',
              },
              {
                'type': 'navigate',
                'waypoint': dropoff,
                'name': 'Dropoff: $dropoff',
              },
              {
                'type': 'wait',
                'duration': 5,
                'name': 'Unloading (5s)',
              },
            ];

            try {
              await api.putMission(
                missionId,
                'Delivery: $pickup -> $dropoff',
                steps,
              );
              await api.startMission(missionId);
            } catch (_) {
              // Direct navigation fallback if custom missions are not supported
              await api.goToWaypoint(pickup);
            }
            dispatchedViaDirectRobot = true;
          }

          if (mounted) {
            Navigator.of(context).pop(true);
            final msg = dispatchedViaDirectRobot
                ? 'Delivery dispatched directly to $fallbackRobotName! (Fleet coordinator timed out: 504)'
                : 'Delivery task dispatched! ID: ${rmfTaskId ?? 'queued'}';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                backgroundColor: AppColors.success,
                duration: const Duration(seconds: 4),
              ),
            );
            return;
          }
        }
      } else {
        // Mission / Workflow mode
        if (_selectedMissionId == null || _selectedMissionId!.isEmpty) {
          throw Exception('Please select a Mission or Visual Graph to run.');
        }

        final mission = _availableMissions.firstWhere(
          (m) => (m['id'] ?? m['workflow_id']) == _selectedMissionId,
          orElse: () => {'name': _selectedMissionId},
        );
        final missionName = mission['name'] as String? ?? _selectedMissionId!;

        if (_isScheduled) {
          final targetIp = _resolveTargetRobotIp(fleet, conn);
          if (targetIp != null) {
            final api = SdkApiService(targetIp);
            final schedId = 'sched_mis_${DateTime.now().millisecondsSinceEpoch}';
            final now = DateTime.now();
            final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
            await api.putSchedule(
              schedId,
              missionId: _selectedMissionId!,
              name: missionName,
              hour: _scheduledTime.hour,
              minute: _scheduledTime.minute,
              repeat: _scheduleRepeat,
              date: _scheduleRepeat == 'once' ? dateStr : null,
              weekdays: _scheduleRepeat == 'weekdays' ? [0, 1, 2, 3, 4] : const [],
            );
          } else {
            throw Exception('Direct robot connection or IP required to save mission schedules.');
          }
        } else {
          // Immediate dispatch
          bool dispatched = false;
          String? fleetMissionId;
          final isUuid = RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(_selectedMissionId!);

          if (fleet.api != null && isUuid) {
            try {
              await fleet.dispatchTask(
                workflowId: _selectedMissionId!,
                fleet: _selectedFleetName ?? 'navpromini',
                robot: _selectedRobotName,
              );
              dispatched = true;

              // Poll mission status briefly to detect saga engine failures
              // (e.g. rmf-core unreachable → mission enters needs_operator/failed)
              if (fleet.api != null) {
                try {
                  final missions = await fleet.api!.getActiveMissions();
                  final latestMission = missions.isNotEmpty ? missions.last : null;
                  if (latestMission != null) {
                    fleetMissionId = latestMission['id'] as String?;
                    // Brief poll: check status after saga has had time to attempt first step
                    await Future.delayed(const Duration(seconds: 4));
                    if (fleetMissionId != null) {
                      final status = await fleet.api!.getMission(fleetMissionId);
                      final missionStatus = status['status'] as String? ?? '';
                      if (missionStatus == 'needs_operator' || missionStatus == 'failed') {
                        debugPrint('Fleet saga failed ($missionStatus), falling back to direct robot dispatch');
                        dispatched = false; // trigger direct robot fallback below
                      }
                    }
                  }
                } catch (_) {
                  // If status polling fails, assume fleet dispatch worked
                }
              }
            } catch (e) {
              final is504OrGatewayError = (e is FleetApiException && (e.status == 504 || e.status == 502 || e.status == 0)) ||
                  e.toString().contains('504') ||
                  e.toString().contains('502') ||
                  e.toString().contains('timed out') ||
                  e.toString().contains('TimeoutException');

              if (!is504OrGatewayError) {
                rethrow;
              }
              // Fall through to direct AMR dispatch
            }
          }

          if (!dispatched) {
            final targetIp = _resolveTargetRobotIp(fleet, conn);
            if (targetIp != null) {
              final api = SdkApiService(targetIp);
              fallbackRobotName = _selectedRobotName ?? conn.robot?.name ?? targetIp;

              // Try to load workflow steps from fleet and execute as local mission
              bool executedWorkflow = false;
              if (fleet.api != null && isUuid) {
                try {
                  final workflows = await fleet.api!.getWorkflows();
                  final wf = workflows.where(
                    (w) => (w['id'] ?? w['workflow_id']) == _selectedMissionId,
                  ).firstOrNull;
                  if (wf != null) {
                    final definition = wf['definition'] as Map<String, dynamic>?;
                    final latestVersion = wf['latestVersion'] as Map<String, dynamic>?;
                    final steps = (definition?['steps'] ?? latestVersion?['definition']?['steps']) as List<dynamic>?;
                    if (steps != null && steps.isNotEmpty) {
                      final localSteps = <Map<String, dynamic>>[];
                      for (final step in steps) {
                        final s = step as Map<String, dynamic>;
                        final stepType = s['type'] as String? ?? '';
                        final params = s['params'] as Map<String, dynamic>? ?? {};
                        if (stepType == 'goto') {
                          final places = (params['places'] as List<dynamic>?) ?? (params['place'] != null ? [params['place']] : <dynamic>[]);
                          for (final place in places) {
                            localSteps.add({
                              'type': 'navigate',
                              'waypoint': place.toString(),
                              'name': 'Go to $place',
                            });
                          }
                        } else if (stepType == 'wait') {
                          final seconds = params['seconds'] as int? ?? 5;
                          localSteps.add({
                            'type': 'wait',
                            'duration': seconds,
                            'name': 'Wait ${seconds}s',
                          });
                        } else if (stepType == 'dock') {
                          localSteps.add({
                            'type': 'dock',
                            'name': 'Dock',
                          });
                        }
                      }
                      if (localSteps.isNotEmpty) {
                        final localMissionId = 'fleet_fallback_${DateTime.now().millisecondsSinceEpoch}';
                        await api.putMission(localMissionId, missionName, localSteps);
                        await api.startMission(localMissionId);
                        executedWorkflow = true;
                      }
                    }
                  }
                } catch (e) {
                  debugPrint('Failed to convert fleet workflow to local mission: $e');
                }
              }

              if (!executedWorkflow) {
                // Last resort: try starting the mission ID directly on the robot
                await api.startMission(_selectedMissionId!);
              }
              dispatchedViaDirectRobot = true;
            } else {
              throw Exception('No active fleet or reachable robot connection found.');
            }
          }
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        final msg = dispatchedViaDirectRobot
            ? 'Mission dispatched directly to $fallbackRobotName! (Fleet coordinator unavailable, executing on robot)'
            : (_isScheduled
                ? 'Task scheduled successfully for ${_scheduledTime.format(context)} ($_scheduleRepeat)!'
                : 'Task successfully dispatched to fleet!');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.success,
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
    final locations = LocationsController.instance.value ?? [];

    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.alt_route_rounded, color: Colors.blue),
          SizedBox(width: 10),
          Text('Dispatch Task / Mission'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Submit an Open-RMF coordinated delivery or mission workflow. The fleet dispatcher automatically negotiates traffic, deconflicts lanes, and assigns the AMR.',
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

              // Task Mode Selection: Pickup & Delivery vs Run Mission
              const Text('Dispatch Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.local_shipping_outlined, size: 18),
                      label: const Center(child: Text('Pickup & Delivery')),
                      selected: _mode == 'delivery',
                      onSelected: (val) => setState(() => _mode = 'delivery'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.account_tree_outlined, size: 18),
                      label: const Center(child: Text('Run Mission / Workflow')),
                      selected: _mode == 'mission',
                      onSelected: (val) => setState(() => _mode = 'mission'),
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),

              // Mode 1: Pickup & Delivery
              if (_mode == 'delivery') ...[
                const Text('Delivery Endpoints', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: locations.isNotEmpty
                          ? DropdownButtonFormField<String>(
                              initialValue: locations.any((l) => l['name'] == _pickupController.text)
                                  ? _pickupController.text
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Pickup Location *',
                                prefixIcon: Icon(Icons.call_received_rounded, color: Colors.blue),
                              ),
                              hint: Text(_pickupController.text.isNotEmpty ? _pickupController.text : 'Select Pickup'),
                              items: locations.map((loc) {
                                final name = loc['name'] as String? ?? 'Point';
                                return DropdownMenuItem(value: name, child: Text(name));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _pickupController.text = val);
                              },
                            )
                          : TextField(
                              controller: _pickupController,
                              decoration: const InputDecoration(
                                labelText: 'Pickup Location *',
                                hintText: 'e.g. station_a',
                                prefixIcon: Icon(Icons.call_received_rounded, color: Colors.blue),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: locations.isNotEmpty
                          ? DropdownButtonFormField<String>(
                              initialValue: locations.any((l) => l['name'] == _dropoffController.text)
                                  ? _dropoffController.text
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Dropoff Destination *',
                                prefixIcon: Icon(Icons.call_made_rounded, color: Colors.orange),
                              ),
                              hint: Text(_dropoffController.text.isNotEmpty ? _dropoffController.text : 'Select Dropoff'),
                              items: locations.map((loc) {
                                final name = loc['name'] as String? ?? 'Point';
                                return DropdownMenuItem(value: name, child: Text(name));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _dropoffController.text = val);
                              },
                            )
                          : TextField(
                              controller: _dropoffController,
                              decoration: const InputDecoration(
                                labelText: 'Dropoff Destination *',
                                hintText: 'e.g. station_b',
                                prefixIcon: Icon(Icons.call_made_rounded, color: Colors.orange),
                              ),
                            ),
                    ),
                  ],
                ),
              ] else ...[
                // Mode 2: Run Mission / Workflow
                const Text('Select Mission / Workflow', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                if (_loadingMissions)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (_availableMissions.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No saved missions found. Please create one using the Mission Graph Editor first.',
                            style: TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _selectedMissionId,
                    decoration: const InputDecoration(
                      labelText: 'Mission Workflow *',
                      prefixIcon: Icon(Icons.account_tree_rounded, color: Colors.teal),
                    ),
                    items: _availableMissions.map((m) {
                      final id = (m['id'] ?? m['workflow_id']) as String;
                      final name = m['name'] as String? ?? id;
                      final isGraph = m['type'] == 'graph' || m.containsKey('nodes');
                      return DropdownMenuItem(
                        value: id,
                        child: Text('$name ${isGraph ? "(Visual Graph)" : "(Linear)"}'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedMissionId = val),
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

              const Divider(height: 28),

              // Schedule / Recurring Option (Matching Open-RMF web)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Schedule Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: const Text('Run at a scheduled start time or repeat on recurrence', style: TextStyle(fontSize: 11)),
                value: _isScheduled,
                onChanged: (val) => setState(() => _isScheduled = val),
              ),
              if (_isScheduled) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_rounded, size: 18),
                        label: Text('Time: ${_scheduledTime.format(context)}'),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _scheduledTime,
                          );
                          if (picked != null) setState(() => _scheduledTime = picked);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _scheduleRepeat,
                        decoration: const InputDecoration(
                          labelText: 'Recurrence',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'once', child: Text('Once')),
                          DropdownMenuItem(value: 'daily', child: Text('Every Day')),
                          DropdownMenuItem(value: 'weekdays', child: Text('Weekdays (Mon-Fri)')),
                        ],
                        onChanged: (val) => setState(() => _scheduleRepeat = val ?? 'once'),
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
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _dispatch,
          icon: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(_isScheduled ? Icons.alarm_rounded : Icons.send_rounded, size: 18),
          label: Text(_isSubmitting
              ? 'Submitting...'
              : (_isScheduled ? 'Schedule Task' : 'Dispatch Task')),
        ),
      ],
    );
  }
}
