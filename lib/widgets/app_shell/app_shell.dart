import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../screens/dashboard_screen.dart';
import '../../screens/maps/maps_list_screen.dart';
import '../../screens/missions/missions_list_screen.dart';
import '../../screens/settings/settings_home_screen.dart';
import '../../screens/teleop/teleop_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    if (!connection.isConnected) {
      return ConnectingScaffold(connection: connection);
    }
    return const _ShellNav();
  }
}

class _ShellNav extends StatefulWidget {
  const _ShellNav();

  @override
  State<_ShellNav> createState() => _ShellNavState();
}

class _ShellNavState extends State<_ShellNav> {
  int _index = 0;

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
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: _index,
      children: [for (final d in _destinations) d.screen],
    );

    final device = Breakpoints.of(context);

    // 1. Mobile Layout: Bottom NavigationBar
    if (device == DeviceClass.mobile) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label),
          ],
        ),
      );
    }

    // 2. Desktop Layout: Modern, dedicated sidebar with branding and live status
    if (device == DeviceClass.desktop) {
      return Scaffold(
        body: Row(
          children: [
            _DesktopSidebar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: _destinations,
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    // 3. Tablet Layout: Compact NavigationRail
    return Scaffold(
      body: Row(
        children: [
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
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
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
    final robot = connection.robot;

    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. App branding & robot identity
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Image.asset('assets/robot_photo.png', fit: BoxFit.contain),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'NavPro Mini',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        robot?.name ?? 'Robot Dashboard',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),

          // 2. Navigation List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: destinations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) {
                final d = destinations[i];
                final isSelected = selectedIndex == i;
                return _SidebarItem(
                  icon: isSelected ? d.selectedIcon : d.icon,
                  label: d.label,
                  isSelected: isSelected,
                  onTap: () => onDestinationSelected(i),
                );
              },
            ),
          ),

          // 3. Bottom Robot Telemetry Card
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          robot?.ip ?? '127.0.0.1',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (telemetry.chargeStatus == ChargeStatus.charging ||
                          telemetry.chargeStatus == ChargeStatus.full)
                        const Icon(Icons.bolt_rounded, size: 16, color: AppColors.success),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (telemetry.batteryPercentage ?? 0) / 100.0,
                            backgroundColor: AppColors.border,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              (telemetry.batteryPercentage ?? 0) <= 20
                                  ? AppColors.danger
                                  : AppColors.success,
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        telemetry.batteryPercentage != null
                            ? '${telemetry.batteryPercentage!.round()}%'
                            : '—',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
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
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected;
    final bg = active
        ? AppColors.primary.withValues(alpha: 0.10)
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
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
