import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
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
/// The shared RobotTelemetryProvider every destination reads is created
/// above the app's Navigator (see main.dart's MaterialApp.builder), not
/// here — a provider scoped to AppShell's own returned subtree would be
/// invisible to any screen reached via Navigator.push (Map View, Create
/// Map, ...), since a pushed route is a sibling OverlayEntry to AppShell's
/// own route, not a descendant of it.
///
/// Bottom NavigationBar on mobile, a side NavigationRail on tablet/desktop —
/// same Breakpoints utility every other responsive screen this session
/// already uses. Destinations are a plain list so adding one is a one-line
/// change, not a restructure.
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

    if (Breakpoints.of(context) == DeviceClass.mobile) {
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
