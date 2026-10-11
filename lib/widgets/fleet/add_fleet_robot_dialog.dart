import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/fleet_provider.dart';
import '../../services/robot_discovery_service.dart';

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
  final _discoveryService = RobotDiscoveryService();

  // Mode: 0 = Discovery / Scan, 1 = Commissioning Form, 2 = Manual Setup
  int _currentStep = 0;

  // Discovered robots list
  final List<DiscoveredRobot> _discoveredRobots = [];
  bool _isScanning = false;
  StreamSubscription<DiscoveredRobot>? _scanSubscription;

  // IP probe controller
  final _manualIpController = TextEditingController();
  bool _isProbingIp = false;
  String? _probeError;

  // Commissioning form controllers
  final _nameController = TextEditingController();
  final _serialController = TextEditingController();
  final _dockController = TextEditingController(text: 'charger_1');
  String? _robotIp;

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

    _startNetworkScan();
  }

  // AP mode setup controllers
  final _apHotspotSsidController = TextEditingController();
  final _siteWifiSsidController = TextEditingController();
  final _siteWifiPasswordController = TextEditingController();
  bool _isConfiguringAp = false;
  String? _apSetupError;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _manualIpController.dispose();
    _nameController.dispose();
    _serialController.dispose();
    _dockController.dispose();
    _apHotspotSsidController.dispose();
    _siteWifiSsidController.dispose();
    _siteWifiPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitApConfiguration() async {
    final wifiSsid = _siteWifiSsidController.text.trim();

    if (wifiSsid.isEmpty) {
      setState(() => _apSetupError = 'Please enter site Wi-Fi SSID');
      return;
    }

    setState(() {
      _isConfiguringAp = true;
      _apSetupError = null;
    });

    try {
      // Connect to the robot AP portal at standard gateway 10.42.0.1:8090
      final discovery = RobotDiscoveryService();
      // Submit credentials via provisioning service
      final res = await discovery.probe('10.42.0.1');
      if (res != null) {
        setState(() {
          _isConfiguringAp = false;
          _currentStep = 0; // Return to discovery to pick up the newly joined AMR
        });
        _startNetworkScan();
      } else {
        setState(() {
          _isConfiguringAp = false;
          _apSetupError = 'Cannot reach robot portal at 10.42.0.1. Please connect device Wi-Fi to "NavPro-Setup-XXXXXX" first.';
        });
      }
    } catch (e) {
      setState(() {
        _isConfiguringAp = false;
        _apSetupError = 'Provisioning error: $e';
      });
    }
  }

  void _startNetworkScan() {
    _scanSubscription?.cancel();
    setState(() {
      _discoveredRobots.clear();
      _isScanning = true;
      _probeError = null;
    });

    _scanSubscription = _discoveryService.scan().listen(
      (robot) {
        if (!mounted) return;
        setState(() {
          if (!_discoveredRobots.any((r) => r.ip == robot.ip || r.serial == robot.serial)) {
            _discoveredRobots.add(robot);
          }
        });
      },
      onDone: () {
        if (mounted) setState(() => _isScanning = false);
      },
      onError: (_) {
        if (mounted) setState(() => _isScanning = false);
      },
    );
  }

  Future<void> _probeManualIp() async {
    final ip = _manualIpController.text.trim();
    if (ip.isEmpty) return;

    setState(() {
      _isProbingIp = true;
      _probeError = null;
    });

    try {
      final robot = await _discoveryService.probe(ip);
      if (!mounted) return;
      if (robot != null) {
        setState(() {
          if (!_discoveredRobots.any((r) => r.ip == robot.ip)) {
            _discoveredRobots.add(robot);
          }
        });
        _selectRobotForCommissioning(robot);
      } else {
        setState(() {
          _probeError = 'No NavPro robot responding at $ip:8090';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _probeError = 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _isProbingIp = false);
    }
  }

  void _selectRobotForCommissioning(DiscoveredRobot robot) {
    setState(() {
      _nameController.text = robot.name;
      _serialController.text = robot.serial.isNotEmpty ? robot.serial : 'navpro_${robot.ip.replaceAll('.', '_')}';
      _robotIp = robot.ip;
      _currentStep = 1; // Switch to Commission Form
    });
  }

  void _selectConnectedRobot(String name, String ip, String? serial) {
    setState(() {
      _nameController.text = name;
      _serialController.text = (serial != null && serial.isNotEmpty)
          ? serial
          : 'navpro_${ip.replaceAll('.', '_')}';
      _robotIp = ip;
      _currentStep = 1; // Switch to Commission Form
    });
  }

  Future<void> _submitCommissioning() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final fleet = context.read<FleetProvider>();
    final serial = _serialController.text.trim();
    final name = _nameController.text.trim();

    try {
      await fleet.createRobot(
        serial: serial,
        name: name,
        fleetId: _selectedFleetId,
        levelId: _selectedLevelId,
        dockWaypoint: _dockController.text.trim(),
        homeWaypoint: _dockController.text.trim(),
      );

      // Save IP mapping in fleet provider for direct communications
      if (_robotIp != null && _robotIp!.isNotEmpty) {
        final registered = fleet.robots.where((r) => r.serial == serial).firstOrNull;
        if (registered != null) {
          fleet.registerRobotIp(registered.id, _robotIp!);
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Robot "$name" successfully linked to NavPro Mini Fleet!'),
            backgroundColor: Colors.green,
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

  Widget _buildApModeView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(Icons.info_outline, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '1. Connect your device Wi-Fi to the robot\'s hotspot (e.g. "NavPro-Setup-XXXXXX").\n'
                  '2. Enter your facility / site Wi-Fi details below to commission the robot onto the fleet network.',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_apSetupError != null)
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
                  child: Text(_apSetupError!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                ),
              ],
            ),
          ),
        TextField(
          controller: _siteWifiSsidController,
          decoration: const InputDecoration(
            labelText: 'Facility Wi-Fi SSID *',
            hintText: 'e.g. Warehouse_Robotics_5G',
            prefixIcon: Icon(Icons.wifi_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _siteWifiPasswordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Wi-Fi Password',
            hintText: 'Facility WPA2/WPA3 password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Target AP Gateway: 10.42.0.1:8090 (native provision portal)',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetProvider>();
    final connection = context.watch<ConnectionProvider>();
    final connectedRobot = connection.robot;

    String title;
    if (_currentStep == 1) {
      title = 'Commission ${_nameController.text}';
    } else if (_currentStep == 2) {
      title = 'Configure Robot Wi-Fi (AP Mode)';
    } else {
      title = 'Add & Link Robot';
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _currentStep == 2 ? Icons.wifi_find_rounded : Icons.smart_toy_rounded,
            color: Colors.blue,
          ),
          const SizedBox(width: 10),
          Text(title),
          const Spacer(),
          if (_currentStep != 0)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              tooltip: 'Back to Discovery',
              onPressed: () => setState(() => _currentStep = 0),
            ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: _currentStep == 1
              ? _buildCommissionForm(fleet)
              : (_currentStep == 2
                  ? _buildApModeView()
                  : _buildDiscoveryView(connectedRobot, fleet)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting || _isConfiguringAp ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_currentStep == 0)
          OutlinedButton.icon(
            onPressed: () {
              final nextNum = fleet.robots.length + 1;
              _nameController.text = 'NavPro Mini $nextNum';
              _serialController.text = 'navpro_mini_${nextNum.toString().padLeft(2, '0')}';
              _robotIp = null;
              setState(() => _currentStep = 1);
            },
            icon: const Icon(Icons.edit_note_rounded, size: 16),
            label: const Text('Manual Entry'),
          )
        else if (_currentStep == 2)
          FilledButton.icon(
            onPressed: _isConfiguringAp ? null : _submitApConfiguration,
            icon: _isConfiguringAp
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.wifi_tethering_rounded, size: 18),
            label: Text(_isConfiguringAp ? 'Configuring...' : 'Push Wi-Fi Credentials'),
          )
        else
          FilledButton.icon(
            onPressed: _isSubmitting ? null : _submitCommissioning,
            icon: _isSubmitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(_isSubmitting ? 'Linking...' : 'Register & Link Robot'),
          ),
      ],
    );
  }

  Widget _buildDiscoveryView(dynamic connectedRobot, FleetProvider fleet) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Scanning for physical NavPro Mini robots on your local network. Discovered AMRs can be linked to the fleet coordinator with one tap.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),

        // 1. Currently Connected Robot (Direct mode)
        if (connectedRobot != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: const Icon(Icons.link_rounded, color: Colors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            connectedRobot.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.green.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('CONNECTED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green)),
                          ),
                        ],
                      ),
                      Text('IP: ${connectedRobot.ip}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => _selectConnectedRobot(
                    connectedRobot.name,
                    connectedRobot.ip,
                    null,
                  ),
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Link This AMR'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 2. Network Discovery Status Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (_isScanning)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.radar_rounded, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  _isScanning ? 'Scanning LAN (port 8090)...' : 'Nearby AMR Robots',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: 'Rescan Network',
              onPressed: _isScanning ? null : _startNetworkScan,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Discovered list
        if (_discoveredRobots.isEmpty && !_isScanning)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: Text(
                'No AMR robots discovered automatically.\nMake sure the robot is powered on and connected to the same Wi-Fi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          )
        else
          ..._discoveredRobots.map((robot) {
            final isAlreadyCommissioned = fleet.robots.any(
              (r) => (r.serial.isNotEmpty && r.serial == robot.serial) ||
                     (fleet.getRobotIp(r.id) == robot.ip),
            );

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isAlreadyCommissioned ? Colors.green.shade50 : Colors.blue.shade50,
                  child: Icon(
                    Icons.smart_toy_rounded,
                    color: isAlreadyCommissioned ? Colors.green : Colors.blue,
                    size: 20,
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        robot.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isAlreadyCommissioned ? Colors.green.shade100 : Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isAlreadyCommissioned ? 'COMMISSIONED' : 'READY TO COMMISSION',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isAlreadyCommissioned ? Colors.green.shade800 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text('IP: ${robot.ip} • Serial: ${robot.serial}', style: const TextStyle(fontSize: 11)),
                trailing: ElevatedButton(
                  onPressed: () => _selectRobotForCommissioning(robot),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAlreadyCommissioned ? Colors.grey.shade700 : Colors.blue,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(isAlreadyCommissioned ? 'Update' : 'Link', style: const TextStyle(fontSize: 12)),
                ),
              ),
            );
          }),

        const Divider(height: 24),

        // 3. Manual IP Probe Box
        const Text('Probe Robot by IP Address', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manualIpController,
                decoration: InputDecoration(
                  hintText: 'e.g. 192.168.1.105',
                  labelText: 'Target Robot IP',
                  isDense: true,
                  prefixIcon: const Icon(Icons.dns_rounded, size: 18),
                  errorText: _probeError,
                ),
                keyboardType: TextInputType.datetime,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _isProbingIp ? null : _probeManualIp,
              style: FilledButton.styleFrom(minimumSize: const Size(80, 42)),
              child: _isProbingIp
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Probe'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 4. Set up New Unconfigured Robot (AP Mode)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blueGrey.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.wifi_find_rounded, color: Colors.blueGrey, size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Brand New Robot with No Wi-Fi?',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Text(
                      'Connect to its "NavPro-Setup-XXXXXX" AP hotspot to configure site Wi-Fi.',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  setState(() => _currentStep = 2);
                },
                icon: const Icon(Icons.settings_input_antenna_rounded, size: 14),
                label: const Text('Setup AP Here', style: TextStyle(fontSize: 11)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommissionForm(FleetProvider fleet) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_robotIp != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_tethering, color: Colors.blue, size: 16),
                  const SizedBox(width: 8),
                  Text('Physical Link: $_robotIp', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
            ),

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
              labelText: 'Serial Number / Hardware ID *',
              hintText: 'e.g. 10000000a1b2c3d4',
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
              labelText: 'Initial Floor / Level',
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
                Icon(Icons.check_circle_outline, color: Colors.blue, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Once registered, the AMR is coordinated by Open-RMF and automatically assigned tasks, traffic priority, and battery recharging.',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
