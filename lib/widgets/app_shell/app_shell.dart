import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_msgs/msg.dart' as std_msgs;

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../screens/dashboard_screen.dart';
import '../../screens/maps/create_map_screen.dart';
import '../../screens/maps/maps_list_screen.dart';
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
    if (!connection.isConnected) {
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
  bool _isSidebarCollapsed = false;
  Subscriber? _modeSubscriber;
  Ros2? _subscribedRos2;
  String? _lastMode;

  void setIndex(int index) {
    if (mounted) setState(() => _index = index);
  }

  void _toggleSidebar() {
    if (mounted) setState(() => _isSidebarCollapsed = !_isSidebarCollapsed);
  }

  static const _destinations = [
    _Destination('Dashboard', Icons.dashboard_outlined, Icons.dashboard_rounded,
        DashboardScreen()),
    _Destination(
        'Maps', Icons.map_outlined, Icons.map_rounded, MapsListScreen()),
    _Destination('Missions', Icons.flag_outlined, Icons.flag_rounded,
        MissionsListScreen()),
    _Destination('Teleop', Icons.videogame_asset_outlined,
        Icons.videogame_asset_rounded, TeleopScreen()),
    _Destination('Settings', Icons.settings_outlined, Icons.settings_rounded,
        SettingsHomeScreen()),
  ];

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
    _modeSubscriber?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final body = IndexedStack(
      index: _index,
      children: [for (final d in _destinations) d.screen],
    );

    final device = Breakpoints.of(context);

    // Keep the Scaffold and IndexedStack structure stable across mobile,
    // tablet, and desktop breakpoints so the active screens and their states
    // are preserved without triggering element deactivation during resizing or window minimize.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => setIndex(0),
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () => setIndex(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () => setIndex(1),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () => setIndex(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () => setIndex(2),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () => setIndex(2),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () => setIndex(3),
        const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () => setIndex(3),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () => setIndex(4),
        const SingleActivator(LogicalKeyboardKey.digit5, meta: true): () => setIndex(4),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): _toggleSidebar,
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): _toggleSidebar,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              if (device == DeviceClass.desktop)
                _DesktopSidebar(
                  selectedIndex: _index,
                  onDestinationSelected: setIndex,
                  destinations: _destinations,
                  isCollapsed: _isSidebarCollapsed,
                  onToggleCollapsed: _toggleSidebar,
                )
              else if (device == DeviceClass.tablet) ...[
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: setIndex,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: colors.surface,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                VerticalDivider(width: 1, color: colors.border),
              ],
              Expanded(child: body),
            ],
          ),
          bottomNavigationBar: device == DeviceClass.mobile
              ? NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: setIndex,
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
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.isCollapsed,
    required this.onToggleCollapsed,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_Destination> destinations;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final width = isCollapsed ? 72.0 : 252.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.border, width: 1)),
      ),
      child: ClipRect(
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SidebarHeader(
                isCollapsed: isCollapsed,
                onToggleCollapsed: onToggleCollapsed,
              ),
              Divider(height: 1, color: colors.border),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 8 : 10),
                  itemCount: destinations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, i) {
                    final d = destinations[i];
                    final isSelected = selectedIndex == i;
                    return _SidebarItem(
                      icon: isSelected ? d.selectedIcon : d.icon,
                      label: d.label,
                      index: i,
                      isSelected: isSelected,
                      isCollapsed: isCollapsed,
                      onTap: () => onDestinationSelected(i),
                    );
                  },
                ),
              ),
              _SidebarThemeToggle(isCollapsed: isCollapsed),
              const SizedBox(height: 4),
              _SidebarTelemetryCapsule(isCollapsed: isCollapsed),
              if (isCollapsed) ...[
                const SizedBox(height: 4),
                _SidebarExpandButton(onTap: onToggleCollapsed),
              ],
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.isCollapsed,
    required this.onToggleCollapsed,
  });

  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final robot = connection.robot;
    final colors = AppColors.of(context);
    final isOnline = connection.isConnected;

    if (isCollapsed) {
      return Container(
        height: 72,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        child: Tooltip(
          message: 'NavPro Mini • ${isOnline ? "Connected" : "Disconnected"}\nClick to expand (Ctrl+B)',
          waitDuration: const Duration(milliseconds: 300),
          child: InkWell(
            onTap: onToggleCollapsed,
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.border),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    'assets/robot_photo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.smart_toy_rounded,
                      size: 22,
                      color: colors.primary,
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isOnline ? colors.success : colors.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: (isOnline ? colors.success : colors.danger).withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 10, 14),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.surfaceSunken,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.border),
                ),
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  'assets/robot_photo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.smart_toy_rounded,
                    size: 24,
                    color: colors.primary,
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isOnline ? colors.success : colors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: (isOnline ? colors.success : colors.danger).withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'NavPro Mini',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.primary.withValues(alpha: 0.3), width: 0.8),
                      ),
                      child: Text(
                        'AMR',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  robot?.name ?? 'Robot Cockpit',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Collapse sidebar (Ctrl+B)',
            waitDuration: const Duration(milliseconds: 300),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggleCollapsed,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border.withValues(alpha: 0.6)),
                  ),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int index;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final telemetry = context.watch<RobotTelemetryProvider>();
    final active = widget.isSelected;
    final isSpeedActive = widget.label == 'Teleop' &&
        (telemetry.linearSpeedMps != null && telemetry.linearSpeedMps! > 0.05);

    final bg = active
        ? colors.primary.withValues(alpha: 0.12)
        : (_hovered ? colors.surfaceSunken : Colors.transparent);
    final fg = active ? colors.primary : colors.textPrimary;
    final iconColor = active ? colors.primary : (_hovered ? colors.textPrimary : colors.textSecondary);

    if (widget.isCollapsed) {
      return Tooltip(
        message: '${widget.label} (Ctrl+${widget.index + 1})',
        waitDuration: const Duration(milliseconds: 250),
        preferBelow: false,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 48,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? colors.primary.withValues(alpha: 0.4)
                      : (_hovered ? colors.border : Colors.transparent),
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (active)
                    Positioned(
                      left: 0,
                      top: 14,
                      bottom: 14,
                      child: Container(
                        width: 3.5,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(3),
                            bottomRight: Radius.circular(3),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.6),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  Icon(
                    widget.icon,
                    size: 22,
                    color: iconColor,
                  ),
                  if (isSpeedActive)
                    Positioned(
                      right: 12,
                      top: 10,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: colors.success,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: colors.success.withValues(alpha: 0.7),
                              blurRadius: 4,
                            ),
                          ],
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

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? colors.primary.withValues(alpha: 0.35)
                  : (_hovered ? colors.border.withValues(alpha: 0.6) : Colors.transparent),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 3.5,
                height: 20,
                decoration: BoxDecoration(
                  color: active ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.5),
                            blurRadius: 5,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                widget.icon,
                size: 20,
                color: iconColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: fg,
                    letterSpacing: -0.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSpeedActive) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.success.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${telemetry.linearSpeedMps!.toStringAsFixed(1)} m/s',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: colors.success,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: active
                      ? colors.primary.withValues(alpha: 0.15)
                      : colors.surfaceSunken,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: active
                        ? colors.primary.withValues(alpha: 0.3)
                        : colors.border.withValues(alpha: 0.7),
                  ),
                ),
                child: Text(
                  '${widget.index + 1}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: active ? colors.primary : colors.textSecondary.withValues(alpha: 0.8),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarThemeToggle extends StatelessWidget {
  const _SidebarThemeToggle({required this.isCollapsed});

  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = AppThemeController.instance.isDarkMode;

    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Tooltip(
          message: 'Switch to ${isDark ? "Factory Light" : "Industrial Dark"}',
          waitDuration: const Duration(milliseconds: 250),
          child: InkWell(
            onTap: () => AppThemeController.instance.toggleTheme(),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.border),
              ),
              child: Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                size: 18,
                color: colors.primary,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: InkWell(
        onTap: () => AppThemeController.instance.toggleTheme(),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                size: 16,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isDark ? 'Industrial Dark' : 'Factory Light',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.swap_horiz_rounded,
                size: 16,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarTelemetryCapsule extends StatelessWidget {
  const _SidebarTelemetryCapsule({required this.isCollapsed});

  final bool isCollapsed;

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final telemetry = context.watch<RobotTelemetryProvider>();
    final robot = connection.robot;
    final colors = AppColors.of(context);

    final batteryPct = telemetry.batteryPercentage ?? 0;
    final isCharging = telemetry.chargeStatus == ChargeStatus.charging ||
        telemetry.chargeStatus == ChargeStatus.full;
    final batteryColor = batteryPct <= 15
        ? colors.danger
        : (batteryPct <= 30 ? colors.warning : colors.success);

    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Tooltip(
          message:
              'Robot Telemetry\nIP: ${robot?.ip ?? "127.0.0.1"}\nBattery: ${telemetry.formatBatteryPercent()}${isCharging ? " (Charging)" : ""}\nLocalization: ${telemetry.localized ? "Localized" : "Unlocalized"}\nMode: ${telemetry.localized ? "Active" : "Degraded"}',
          waitDuration: const Duration(milliseconds: 250),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isCharging
                      ? Icons.bolt_rounded
                      : (batteryPct <= 15
                          ? Icons.battery_alert_rounded
                          : Icons.battery_charging_full_rounded),
                  size: 18,
                  color: isCharging ? colors.success : batteryColor,
                ),
                const SizedBox(height: 2),
                Text(
                  telemetry.batteryPercentage != null
                      ? '${batteryPct.toInt()}%'
                      : '—',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: telemetry.localized ? colors.success : colors.warning,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: connection.isConnected ? colors.success : colors.danger,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (connection.isConnected ? colors.success : colors.danger)
                            .withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    robot?.ip ?? '127.0.0.1',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCharging) ...[
                  Icon(Icons.bolt_rounded, size: 15, color: colors.success),
                  const SizedBox(width: 2),
                  Text(
                    'CHG',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: colors.success,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: batteryPct / 100.0,
                      backgroundColor: colors.border,
                      valueColor: AlwaysStoppedAnimation<Color>(batteryColor),
                      minHeight: 5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  telemetry.batteryPercentage != null
                      ? telemetry.formatBatteryPercent()
                      : '—',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (telemetry.localized ? colors.success : colors.warning)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: (telemetry.localized ? colors.success : colors.warning)
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        telemetry.localized
                            ? Icons.gps_fixed_rounded
                            : Icons.gps_not_fixed_rounded,
                        size: 10,
                        color: telemetry.localized ? colors.success : colors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        telemetry.localized ? 'Localized' : 'Unlocalized',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: telemetry.localized ? colors.success : colors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (telemetry.cpuLoad != null)
                  Text(
                    '${telemetry.cpuLoad!.toInt()}% CPU',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarExpandButton extends StatelessWidget {
  const _SidebarExpandButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Tooltip(
        message: 'Expand sidebar (Ctrl+B)',
        waitDuration: const Duration(milliseconds: 250),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: colors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
