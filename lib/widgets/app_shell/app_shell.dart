import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_msgs/msg.dart' as std_msgs;

import '../../providers/connection_provider.dart';
import '../../providers/fleet_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../screens/dashboard_screen.dart';
import '../../screens/maps/create_map_screen.dart';
import '../../screens/maps/map_view_screen.dart';
import '../../screens/missions/missions_list_screen.dart';
import '../../screens/settings/settings_home_screen.dart';
import '../../screens/teleop/teleop_screen.dart';
import '../../services/mode_transition_tracker.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../connecting_scaffold.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.screen);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

/// The app's top-level shell, and the gate for the app's core connection:
/// nothing behind it (Dashboard, Maps, Missions, Teleop, Settings) can do
/// anything useful before rosbridge is up, so this is where that's waited
/// for — once, rather than every screen re-deriving it. Locations has no
/// destination of its own — saved locations are managed from Map View's own
/// "Add Location" control and shown as tappable pins there and on Teleop's
/// live map, rather than a separate list screen.
///
/// Responsive navigation:
/// - Mobile: Bottom NavigationBar
/// - Tablet: Compact NavigationRail
/// - Desktop: Rich, dedicated DesktopSidebar with robot status and telemetry
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static final GlobalKey<_ShellNavState> _shellNavKey =
      GlobalKey<_ShellNavState>();

  static void selectTab(int index) {
    _shellNavKey.currentState?.setIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final fleet = context.watch<FleetProvider>();

    // In Fleet Mode, the operator manages the fleet, building maps, and task dispatching
    // even before or without a direct rosbridge connection to a specific single robot.
    if (!connection.isConnected && !fleet.isFleetMode) {
      return ConnectingScaffold(connection: connection);
    }
    return _ShellNav(key: _shellNavKey);
  }
}

class _ShellNav extends StatefulWidget {
  const _ShellNav({super.key});

  @override
  State<_ShellNav> createState() => _ShellNavState();
}

class _ShellNavState extends State<_ShellNav> {
  int _index = 0;
  Subscriber? _modeSubscriber;
  Ros2? _subscribedRos2;
  String? _lastMode;
  Timer? _fleetHeartbeatTimer;

  void setIndex(int index) {
    if (mounted) setState(() => _index = index);
  }

  static const _destinations = [
    _Destination('Dashboard', Icons.dashboard_outlined, Icons.dashboard_rounded,
        DashboardScreen()),
    _Destination(
        'Map Cockpit', Icons.map_outlined, Icons.map_rounded, MapViewScreen()),
    _Destination('Missions', Icons.flag_outlined, Icons.flag_rounded,
        MissionsListScreen()),
    _Destination('Teleop', Icons.videogame_asset_outlined,
        Icons.videogame_asset_rounded, TeleopScreen()),
    _Destination('Settings', Icons.settings_outlined, Icons.settings_rounded,
        SettingsHomeScreen()),
  ];

  @override
  void initState() {
    super.initState();
    _startFleetHeartbeatSync();
  }

  void _startFleetHeartbeatSync() {
    _fleetHeartbeatTimer?.cancel();
    _fleetHeartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final fleet = context.read<FleetProvider>();
      if (!fleet.isFleetMode) return;

      final connection = context.read<ConnectionProvider>();
      if (!connection.isConnected || connection.robot == null) return;

      final physicalRobot = connection.robot!;
      final telemetry = context.read<RobotTelemetryProvider>();

      // Match connected robot with a registered fleet robot by IP, name, or serial
      final registered = fleet.robots.where((r) {
        final mappedIp = fleet.getRobotIp(r.id);
        if (mappedIp != null && mappedIp == physicalRobot.ip) return true;
        if (r.serial.isNotEmpty && physicalRobot.name.toLowerCase().contains(r.serial.toLowerCase())) return true;
        return r.name.toLowerCase() == physicalRobot.name.toLowerCase();
      }).firstOrNull;

      if (registered == null) return;

      // Extract coordinates (fallback to 0,0,0 if not localized yet)
      final x = telemetry.poseX ?? 0.0;
      final y = telemetry.poseY ?? 0.0;
      final yaw = telemetry.poseTheta ?? 0.0;
      final battery = telemetry.batteryPercentage;
      final mode = _lastMode ?? (telemetry.linearSpeedMps != null && telemetry.linearSpeedMps!.abs() > 0.05 ? 'moving' : 'idle');

      fleet.reportRobotHeartbeat(
        robotId: registered.id,
        x: x,
        y: y,
        yaw: yaw,
        batteryPercent: battery,
        mode: mode,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureModeSubscription();
  }

  void _ensureModeSubscription() {
    final ros2 = context.read<ConnectionProvider>().ros2;
    if (ros2 == _subscribedRos2) return;
    _modeSubscriber?.unsubscribe();
    _subscribedRos2 = ros2;
    if (ros2 == null) return;

    _modeSubscriber = Subscriber<std_msgs.StringMessage>(
      name: '/robot_mode',
      type: std_msgs.StringMessage().fullType,
      ros2: ros2,
      prototype: std_msgs.StringMessage(),
      qos: const {'durability': 'transient_local'},
      callback: _onRobotModeChanged,
    );
  }

  void _onRobotModeChanged(std_msgs.StringMessage msg) {
    final newMode = msg.data;
    if (newMode == _lastMode) return;
    final previousMode = _lastMode;
    _lastMode = newMode;

    // Feed the mode transition tracker for immediate UI feedback
    ModeTransitionTracker.instance.onSdkModeUpdated(newMode);

    // Auto-navigate to CreateMapScreen when mapping starts externally and not already opened
    if (newMode == 'mapping' &&
        !CreateMapScreen.isOpen &&
        !CreateMapScreen.isSuppressingAutoOpen &&
        !ModeTransitionTracker.instance.isStoppingMapping) {
      if (mounted) {
        context.read<RobotTelemetryProvider>().resetForMapping();
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const CreateMapScreen(alreadyMapping: true),
        ),
      );
    }

    // When mapping stops, auto-pop CreateMapScreen if it is open and return to Dashboard
    if (previousMode == 'mapping' && newMode != 'mapping') {
      if (mounted) {
        context.read<RobotTelemetryProvider>().exitMappingMode();
      }
      if (CreateMapScreen.isOpen && mounted) {
        AppShell.selectTab(0);
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  void dispose() {
    _fleetHeartbeatTimer?.cancel();
    _modeSubscriber?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: _index,
      children: [for (final d in _destinations) d.screen],
    );

    final device = Breakpoints.of(context);

    // Keep the Scaffold and IndexedStack structure stable across mobile,
    // tablet, and desktop breakpoints so the active screens and their states
    // are preserved without triggering element deactivation during resizing or window minimize.
    return Scaffold(
      body: Column(
        children: [
          if (device == DeviceClass.desktop)
            _DesktopTopBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: _destinations,
            ),
          Expanded(
            child: Row(
              children: [
                if (device == DeviceClass.tablet) ...[
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: AppColors.surface,
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1, color: AppColors.border),
                ],
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: device == DeviceClass.mobile
          ? NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            )
          : null,
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_Destination> destinations;

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final telemetry = context.watch<RobotTelemetryProvider>();
    final fleet = context.watch<FleetProvider>();
    final robot = connection.robot;
    final isFleet = fleet.isFleetMode;

    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // 1. App branding & robot identity
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isFleet ? Colors.blue.withValues(alpha: 0.12) : AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isFleet ? Colors.blue.withValues(alpha: 0.3) : AppColors.border),
            ),
            padding: const EdgeInsets.all(4),
            child: isFleet
                ? const Icon(Icons.hub_rounded, color: Colors.blue, size: 20)
                : Image.asset('assets/robot_photo.png', fit: BoxFit.contain),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isFleet ? 'NavPro Mini Fleet' : 'NavPro Mini',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                isFleet
                    ? (fleet.selectedRobot != null ? 'Unit: ${fleet.selectedRobot!.name}' : '${fleet.robots.length} Robots Online')
                    : (robot?.name ?? 'Robot Dashboard'),
                style: TextStyle(
                  fontSize: 11,
                  color: isFleet ? Colors.blue : AppColors.textSecondary,
                  fontWeight: isFleet ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(width: 24),
          const VerticalDivider(width: 1, indent: 14, endIndent: 14, color: AppColors.border),
          const SizedBox(width: 12),

          // 2. Navigation Items (Horizontal tabs)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < destinations.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _TopNavItem(
                        icon: selectedIndex == i ? destinations[i].selectedIcon : destinations[i].icon,
                        label: destinations[i].label,
                        isSelected: selectedIndex == i,
                        onTap: () => onDestinationSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),
          const VerticalDivider(width: 1, indent: 14, endIndent: 14, color: AppColors.border),
          const SizedBox(width: 16),

          // 3. Status & Telemetry Pill
          if (isFleet)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${fleet.fleetServerHost}:${fleet.fleetServerPort}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('FLEET', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${fleet.robots.length} AMRs · ${fleet.activeMissions.length} Tasks',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    robot?.ip ?? '127.0.0.1',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  if (telemetry.chargeStatus == ChargeStatus.charging ||
                      telemetry.chargeStatus == ChargeStatus.full) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.bolt_rounded, size: 14, color: AppColors.success),
                  ],
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 48,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (telemetry.batteryPercentage ?? 0) / 100.0,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          (telemetry.batteryPercentage ?? 0) <= 20 ? AppColors.danger : AppColors.success,
                        ),
                        minHeight: 5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    telemetry.batteryPercentage != null ? telemetry.formatBatteryPercent() : '—',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TopNavItem extends StatefulWidget {
  const _TopNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_TopNavItem> createState() => _TopNavItemState();
}

class _TopNavItemState extends State<_TopNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected;
    final bg = active
        ? AppColors.primary.withValues(alpha: 0.12)
        : (_hovered ? AppColors.surfaceSunken : Colors.transparent);
    final fg = active ? AppColors.primary : AppColors.textPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppColors.primary.withValues(alpha: 0.3) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
