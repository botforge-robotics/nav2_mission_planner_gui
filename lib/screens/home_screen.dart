import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/widgets/top_status_bar/top_status_bar.dart';
import '../constants/modes.dart';
import '../theme/app_theme.dart';
import 'mapping_screen.dart';
import 'navigation_screen.dart';
import 'settings/settings_screen.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/branding_provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'connection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppModes _currentMode = AppModes.mapping;
  AppModes? _previousMode;

  @override
  void initState() {
    super.initState();
  }

  String _getModeStatusText(bool isConnected) {
    if (!isConnected) {
      return 'Connect to Robot';
    }
    switch (_currentMode) {
      case AppModes.teleop:
        // Teleop removed from mode toggle; treat as mapping if reached.
        return 'Mapping Mode';
      case AppModes.mapping:
        return 'Mapping Mode';
      case AppModes.navigation:
        return 'Navigation Mode';
      case AppModes.settings:
        return 'Settings';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connectionProvider, child) {
        return _buildMainContent(context, connectionProvider);
      },
    );
  }

  Widget _buildMainContent(
      BuildContext context, ConnectionProvider connectionProvider) {
    if (!connectionProvider.isConnected &&
        _currentMode != AppModes.mapping &&
        _currentMode != AppModes.settings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _currentMode = AppModes.mapping;
          _previousMode = null;
        });
      });
    }

    // Never land on teleop (removed from toggle)
    if (_currentMode == AppModes.teleop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _currentMode = AppModes.mapping;
          _previousMode = null;
        });
      });
    }

    final activeScreen = _currentMode == AppModes.settings
        ? (_previousMode == AppModes.teleop
            ? AppModes.mapping
            : (_previousMode ?? AppModes.mapping))
        : (_currentMode == AppModes.teleop
            ? AppModes.mapping
            : _currentMode);

    return Consumer<BrandingProvider>(
      builder: (context, brandingProvider, child) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: Stack(
            children: [
              Column(
                children: [
                  TopStatusBar(
                    currentMode: _currentMode == AppModes.teleop
                        ? AppModes.mapping
                        : _currentMode,
                    onModeChanged: (mode) {
                      setState(() {
                        if (mode == AppModes.settings) {
                          _previousMode = _currentMode == AppModes.teleop
                              ? AppModes.mapping
                              : _currentMode;
                        } else {
                          _previousMode = null;
                        }
                        _currentMode = mode == AppModes.teleop
                            ? AppModes.mapping
                            : mode;
                      });
                    },
                    statusText:
                        _getModeStatusText(connectionProvider.isConnected),
                    statusColor: connectionProvider.isConnected
                        ? ModeColors.getModeColorMap(context)[
                            _currentMode == AppModes.settings
                                ? (_previousMode ?? AppModes.mapping)
                                : (_currentMode == AppModes.teleop
                                    ? AppModes.mapping
                                    : _currentMode)]!
                        : Colors.red,
                    height: AppTheme.statusBarHeight,
                    icon: connectionProvider.isConnected
                        ? null
                        : FontAwesomeIcons.robot,
                  ),
                  Expanded(
                    child: connectionProvider.isConnected
                        ? IndexedStack(
                            index: _getScreenIndex(activeScreen),
                            children: [
                              MappingScreen(
                                  modeColor: ModeColors.getModeColorMap(
                                      context)[AppModes.mapping]!),
                              NavigationScreen(
                                  modeColor: ModeColors.getModeColorMap(
                                      context)[AppModes.navigation]!),
                            ],
                          )
                        : const ConnectionScreen(showTopStatusBar: false),
                  ),
                ],
              ),

              if (_currentMode == AppModes.settings)
                Positioned.fill(
                  top: AppTheme.statusBarHeight,
                  child: const Material(
                    color: Colors.transparent,
                    child: SettingsScreen(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  int _getScreenIndex(AppModes mode) {
    switch (mode) {
      case AppModes.mapping:
        return 0;
      case AppModes.navigation:
        return 1;
      case AppModes.teleop:
      case AppModes.settings:
        return 0;
    }
  }
}
