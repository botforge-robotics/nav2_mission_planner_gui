import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/fleet_models.dart';
import '../../providers/fleet_provider.dart';
import '../../theme/app_theme.dart';

class FleetSettingsScreen extends StatefulWidget {
  const FleetSettingsScreen({super.key});

  @override
  State<FleetSettingsScreen> createState() => _FleetSettingsScreenState();
}

class _FleetSettingsScreenState extends State<FleetSettingsScreen> {
  final _hostController = TextEditingController(text: 'localhost');
  final _portController = TextEditingController(text: '80');
  bool _fleetEnabled = false;

  @override
  void initState() {
    super.initState();
    final fleet = context.read<FleetProvider>();
    _fleetEnabled = fleet.isFleetMode;
    _hostController.text = (fleet.fleetServerHost != null && fleet.fleetServerHost!.isNotEmpty)
        ? fleet.fleetServerHost!
        : 'localhost';
    _portController.text = fleet.fleetServerPort.toString();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 3000;
    final fleet = context.read<FleetProvider>();
    fleet.setFleetMode(_fleetEnabled, host: host, port: port);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_fleetEnabled
            ? 'Connected to Fleet Server at $host:$port'
            : 'Switched to Direct Robot Mode'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FleetProvider>(
      builder: (context, fleet, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Open-RMF Fleet Management'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh Fleet',
                onPressed: fleet.isFleetMode ? fleet.refreshFleet : null,
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.hub_rounded,
                            size: 28,
                            color: _fleetEnabled ? Colors.blue : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Fleet Server Mode',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                Text(
                                  'Coordinate multi-robot fleets, multi-floor maps, and Open-RMF traffic',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _fleetEnabled,
                            onChanged: (val) {
                              setState(() => _fleetEnabled = val);
                              _saveSettings();
                            },
                          ),
                        ],
                      ),
                      if (_fleetEnabled) ...[
                        const Divider(height: 24),
                        TextField(
                          controller: _hostController,
                          decoration: const InputDecoration(
                            labelText: 'Fleet Server IP / Hostname',
                            hintText: 'e.g. 192.168.1.100 or localhost',
                            prefixIcon: Icon(Icons.dns_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Platform API / Ingress Port',
                            hintText: '80',
                            prefixIcon: Icon(Icons.numbers_rounded),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _saveSettings,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Apply Fleet Config'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () => _showLoginDialog(context, fleet),
                              icon: Icon(
                                fleet.isAuthenticated ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                                color: fleet.isAuthenticated ? Colors.green : Colors.orange,
                              ),
                              label: Text(
                                fleet.isAuthenticated ? 'Authenticated' : 'Sign In',
                                style: TextStyle(
                                  color: fleet.isAuthenticated ? Colors.green : Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (fleet.isFleetMode) ...[
                if (fleet.error != null)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Fleet Error: ${fleet.error}',
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),
                const Text(
                  'Active Fleet Overview',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        'Total Robots',
                        '${fleet.robots.length}',
                        Icons.smart_toy_rounded,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        'Building Levels',
                        '${fleet.levels.length}',
                        Icons.layers_rounded,
                        Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        'Active Tasks',
                        '${fleet.activeMissions.length}',
                        Icons.alt_route_rounded,
                        Colors.green,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Text(
                  'Connected Robots',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (fleet.robots.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('No robots found on Fleet Server. Robots will appear here once connected.'),
                      ),
                    ),
                  )
                else
                  ...fleet.robots.map((r) => _buildRobotTile(context, fleet, r)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildRobotTile(BuildContext context, FleetProvider fleet, FleetRobotInfo robot) {
    final isSelected = fleet.selectedRobotId == robot.id;
    return Card(
      elevation: isSelected ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected ? const BorderSide(color: Colors.blue, width: 2) : BorderSide.none,
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: robot.isPending
              ? Colors.amber.shade100
              : (robot.isActive ? Colors.green.shade100 : Colors.grey.shade200),
          child: Icon(
            Icons.smart_toy_rounded,
            color: robot.isPending
                ? Colors.amber.shade800
                : (robot.isActive ? Colors.green.shade800 : Colors.grey.shade600),
          ),
        ),
        title: Row(
          children: [
            Text(robot.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: robot.isPending ? Colors.amber.shade100 : Colors.green.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                robot.status.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: robot.isPending ? Colors.amber.shade900 : Colors.green.shade900,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Level: ${robot.levelName ?? robot.levelId ?? 'Unassigned'} • Charger: ${robot.dockWaypoint ?? 'None'} • Mode: ${robot.navMode ?? 'OFFLINE'}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: robot.isPending
            ? ElevatedButton(
                onPressed: () => _showCommissionDialog(context, fleet, robot),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('Commission', style: TextStyle(color: Colors.white, fontSize: 12)),
              )
            : IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _showRobotDetailsSheet(context, fleet, robot),
              ),
        onTap: () {
          fleet.selectRobot(robot.id);
        },
      ),
    );
  }

  void _showCommissionDialog(BuildContext context, FleetProvider fleet, FleetRobotInfo robot) {
    String? selectedFleetId = fleet.fleets.isNotEmpty ? fleet.fleets.first.id : null;
    String? selectedLevelId = fleet.levels.isNotEmpty ? fleet.levels.first.id : null;
    final nameCtrl = TextEditingController(text: robot.name);
    final chargerCtrl = TextEditingController(text: 'charger_1');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Commission ${robot.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Robot Name'),
                ),
                const SizedBox(height: 12),
                if (fleet.fleets.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: selectedFleetId,
                    decoration: const InputDecoration(labelText: 'Assigned Fleet'),
                    items: fleet.fleets
                        .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name)))
                        .toList(),
                    onChanged: (val) => setDlgState(() => selectedFleetId = val),
                  ),
                const SizedBox(height: 12),
                if (fleet.levels.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: selectedLevelId,
                    decoration: const InputDecoration(labelText: 'Initial Floor / Level'),
                    items: fleet.levels
                        .map((l) => DropdownMenuItem(value: l.id, child: Text(l.name)))
                        .toList(),
                    onChanged: (val) => setDlgState(() => selectedLevelId = val),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: chargerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Home / Charger Waypoint',
                    hintText: 'e.g. charger_1 or dock_a',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                if (selectedFleetId != null && selectedLevelId != null) {
                  await fleet.commissionRobot(
                    robotId: robot.id,
                    fleetId: selectedFleetId!,
                    levelId: selectedLevelId!,
                    name: nameCtrl.text.trim(),
                    dockWaypoint: chargerCtrl.text.trim(),
                    homeWaypoint: chargerCtrl.text.trim(),
                    startNav: true,
                  );
                }
              },
              child: const Text('Activate & Start Nav'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRobotDetailsSheet(BuildContext context, FleetProvider fleet, FleetRobotInfo robot) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smart_toy_rounded, size: 28, color: Colors.blue),
                const SizedBox(width: 12),
                Text(robot.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 12),
            Text('ID: ${robot.id}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text('Serial: ${robot.serial}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text('Current Level: ${robot.levelName ?? robot.levelId ?? 'N/A'}'),
            Text('Charger: ${robot.dockWaypoint ?? 'N/A'}'),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text('Nav Ready'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    fleet.sendNavCommand(robotId: robot.id, action: 'start_nav');
                  },
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop Nav'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    fleet.sendNavCommand(robotId: robot.id, action: 'stop_nav');
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Decommission',
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await fleet.decommissionRobot(robot.id);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLoginDialog(BuildContext context, FleetProvider fleet) {
    final userCtrl = TextEditingController(text: 'admin');
    final passCtrl = TextEditingController(text: 'navpro-admin');
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.lock_rounded, color: Colors.blue),
              SizedBox(width: 8),
              Text('Fleet Server Sign In'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Authenticate with platform-api credentials to acquire a Bearer token.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'admin',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'navpro-admin',
                  prefixIcon: const Icon(Icons.password_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (fleet.isAuthenticated)
              TextButton(
                onPressed: () {
                  fleet.setFleetMode(fleet.isFleetMode, token: '');
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signed out of Fleet Server')),
                  );
                },
                child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final nav = Navigator.of(ctx);
                final scaffold = ScaffoldMessenger.of(context);
                final success = await fleet.login(userCtrl.text.trim(), passCtrl.text.trim());
                if (success) {
                  nav.pop();
                  scaffold.showSnackBar(
                    const SnackBar(
                      content: Text('Successfully authenticated with Fleet Server!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  scaffold.showSnackBar(
                    SnackBar(
                      content: Text('Login failed: ${fleet.error ?? "Invalid credentials"}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Sign In'),
            ),
          ],
        ),
      ),
    );
  }
}
