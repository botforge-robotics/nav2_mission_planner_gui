import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nav2_mission_planner/widgets/top_status_bar/top_status_bar.dart';
import 'package:nav2_mission_planner/widgets/app_shell/app_nav_rail.dart';
import '../constants/modes.dart';
import '../theme/app_theme.dart';
import 'dashboard/dashboard_screen.dart';
import 'dock/dock_screen.dart';
import 'robot_status/robot_status_screen.dart';
import 'alerts/alerts_screen.dart';
import 'tools/tools_screen.dart';
import 'mapping_screen.dart';
import 'navigation_screen.dart';
import 'settings/settings_screen.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/branding_provider.dart';
import '../services/launch_service.dart';
import '../services/mission_execution_service.dart';
import '../services/alert_log_service.dart';
import 'connection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _lastModeKey = 'lastAppMode';

  // Dashboard is the landing screen — robot-truth reconciliation
  // (_reconcileModeWithRetry) still redirects to mapping/navigation on
  // connect if the robot turns out to already be running one of those
  // sessions; this default only sticks when the robot is genuinely idle.
  AppModes _currentMode = AppModes.dashboard;
  AppModes? _previousMode;
  // Persisted mode from a previous session, applied once we're actually
  // connected (not eagerly — the disconnected-state guard below would
  // otherwise immediately stomp it back to mapping while reconnecting).
  AppModes? _pendingRestoreMode;
  // Whether this connection has already had its mode reconciled against
  // the robot's actual ROS graph (see the detectRobotMode() call in
  // _buildMainContent) — guards against re-querying on every rebuild, and
  // re-armed on each fresh connect so a reconnect (possibly to a robot
  // doing something different) gets checked again.
  bool _modeReconciled = false;

  @override
  void initState() {
    super.initState();
    _loadPersistedMode();
    // Starts the alert log's listeners once for the app's lifetime —
    // AlertLogService.observe() is idempotent, so this is safe even though
    // HomeScreen itself can theoretically rebuild/remount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AlertLogService.instance.observe(
        connection: Provider.of<ConnectionProvider>(context, listen: false),
        mission: Provider.of<MissionExecutionService>(context, listen: false),
      );
    });
  }

  Future<void> _loadPersistedMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_lastModeKey);
    if (saved == null || !mounted) return;
    for (final mode in AppModes.values) {
      if (mode.name == saved &&
          (mode == AppModes.mapping || mode == AppModes.navigation)) {
        setState(() => _pendingRestoreMode = mode);
        break;
      }
    }
  }

  void _persistMode(AppModes mode) {
    if (mode != AppModes.mapping && mode != AppModes.navigation) return;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_lastModeKey, mode.name));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connectionProvider, child) {
        return _buildMainContent(context, connectionProvider);
      },
    );
  }

  /// A single detectRobotMode() call right at connect can race rosbridge/
  /// rosapi not being fully ready yet and come back null — indistinguishable
  /// from "robot is genuinely idle" from the return value alone. Retrying a
  /// few times before accepting a null result (rather than locking it in
  /// immediately, which is what this replaced) turns "was idle" and "wasn't
  /// ready yet" into the same visible behavior for the common transient
  /// case, without polling forever if the robot really is idle.
  Future<void> _reconcileModeWithRetry(
      ConnectionProvider connectionProvider) async {
    const maxAttempts = 4;
    const retryDelay = Duration(seconds: 2);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!mounted || !connectionProvider.isConnected) return;
      final detected = await connectionProvider.detectRobotMode();
      if (!mounted) return;
      if (detected != null) {
        final mode =
            detected == 'navigation' ? AppModes.navigation : AppModes.mapping;
        setState(() {
          _currentMode = mode;
          _previousMode = null;
          _pendingRestoreMode = null; // robot truth wins over the local guess
        });
        return;
      }
      if (attempt < maxAttempts) {
        await Future.delayed(retryDelay);
      }
    }
    // Exhausted retries with no detection — leaves the SharedPreferences
    // restore (_pendingRestoreMode) alone rather than forcing anything;
    // most likely the robot really is idle.
  }

  /// Applies a mode change after the guard in [_handleDestinationTapped] has
  /// cleared it — updates local state and persists mapping/navigation
  /// choices. Split out from the guard so the guard can early-return freely
  /// without duplicating this bookkeeping.
  void _applyModeChange(AppModes mode) {
    setState(() {
      if (mode == AppModes.settings) {
        _previousMode =
            _currentMode == AppModes.teleop ? AppModes.mapping : _currentMode;
      } else {
        _previousMode = null;
      }
      _currentMode = mode == AppModes.teleop ? AppModes.mapping : mode;
    });
    _persistMode(_currentMode);
  }

  /// Guards a nav-rail destination tap against an in-progress mapping/
  /// navigation session — moved here from the old `TopStatusModeSelector`/
  /// `TopStatusBar` mode-dropdown, which owned this same logic before mode
  /// selection moved to `AppNavRail`. Behavior is unchanged: switching away
  /// from the session's own mode is blocked outright while a *different*
  /// mode's launch is merely active-but-switchable-with-confirmation.
  Future<void> _handleDestinationTapped(AppModes newMode) async {
    final launchManager = Provider.of<LaunchManager>(context, listen: false);
    final activeSession = launchManager.activeSession;

    if (activeSession == SessionType.mapping &&
        newMode != AppModes.settings &&
        newMode != AppModes.dashboard &&
        newMode != AppModes.dock &&
        newMode != AppModes.robotStatus &&
        newMode != AppModes.alerts &&
        newMode != AppModes.tools &&
        newMode != AppModes.mapping) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Stop mapping before changing modes'),
          backgroundColor: Colors.red.withValues(alpha: 0.9),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (activeSession == SessionType.navigation &&
        newMode != AppModes.settings &&
        newMode != AppModes.dashboard &&
        newMode != AppModes.dock &&
        newMode != AppModes.robotStatus &&
        newMode != AppModes.alerts &&
        newMode != AppModes.tools &&
        newMode != AppModes.navigation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Stop navigation before changing modes'),
          backgroundColor: Colors.red.withValues(alpha: 0.9),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Dashboard, Dock & Charge, and Robot Status are non-disruptive, real
    // peer screens (not an overlay like Settings) — freely viewable
    // without interrupting an active session, same as Settings. Docking
    // itself (via this screen's Dock/Undock button) is already reachable
    // regardless of session state from navigation_screen.dart's inline
    // dock button today, so this doesn't newly permit anything unsafe.
    if (newMode == AppModes.settings ||
        newMode == AppModes.dashboard ||
        newMode == AppModes.dock ||
        newMode == AppModes.robotStatus ||
        newMode == AppModes.alerts ||
        newMode == AppModes.tools) {
      _applyModeChange(newMode);
      return;
    }

    if ((_currentMode == AppModes.mapping ||
            _currentMode == AppModes.navigation) &&
        newMode != _currentMode &&
        launchManager.activeLaunches.isNotEmpty) {
      final shouldStop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Active Session'),
          content: Text(
              'You have an active ${_currentMode.name} session. Stop it before changing modes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Running'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.9),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Stop Session'),
            ),
          ],
        ),
      );

      if (shouldStop ?? false) {
        for (final entry in launchManager.activeLaunches.entries) {
          if (!mounted) return;
          try {
            await launchManager.stopLaunch(context, entry.key);
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to stop session: ${e.toString()}'),
                backgroundColor: Colors.red.withValues(alpha: 0.9),
              ),
            );
          }
        }
      } else {
        return; // Abort mode change
      }
    }

    if (!mounted) return;
    _applyModeChange(newMode);
  }

  Widget _buildMainContent(
      BuildContext context, ConnectionProvider connectionProvider) {
    // Only apply a restored mode once actually connected — applying it
    // eagerly would just get stomped back to mapping by the guard below
    // while HomeScreen is still built with isConnected == false during an
    // in-flight auto-reconnect.
    if (connectionProvider.isConnected && _pendingRestoreMode != null) {
      final restore = _pendingRestoreMode!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _currentMode = restore;
          _previousMode = null;
          _pendingRestoreMode = null;
        });
      });
    } else if (!connectionProvider.isConnected &&
        _currentMode != AppModes.dashboard &&
        _currentMode != AppModes.settings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _currentMode = AppModes.dashboard;
          _previousMode = null;
          _modeReconciled = false; // re-check against the robot next connect
        });
      });
    }

    // Robot truth over local guesswork: once connected, ask what the robot
    // is actually doing (mapping/navigation/idle) and land on THAT screen
    // rather than trusting only this device's last-remembered mode — a
    // different client (another device, a future web API) may have changed
    // it, or the robot may have kept running navigation across an app
    // close/reopen that this device never saw.
    if (connectionProvider.isConnected && !_modeReconciled) {
      _modeReconciled = true; // claim it now so this fires exactly once
      _reconcileModeWithRetry(connectionProvider);
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
        : (_currentMode == AppModes.teleop ? AppModes.mapping : _currentMode);

    final railMode =
        _currentMode == AppModes.teleop ? AppModes.mapping : _currentMode;

    return Consumer<BrandingProvider>(
      builder: (context, brandingProvider, child) {
        return Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: connectionProvider.isConnected
              ? Row(
                  children: [
                    AppNavRail(
                      currentMode: railMode,
                      onDestinationTapped: _handleDestinationTapped,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              const TopStatusBar(
                                height: AppTheme.statusBarHeight,
                              ),
                              Expanded(
                                child: IndexedStack(
                                  index: _getScreenIndex(activeScreen),
                                  children: [
                                    const DashboardScreen(),
                                    MappingScreen(
                                        modeColor: ModeColors.getModeColorMap(
                                            context)[AppModes.mapping]!),
                                    NavigationScreen(
                                        modeColor: ModeColors.getModeColorMap(
                                            context)[AppModes.navigation]!),
                                    const DockScreen(),
                                    const RobotStatusScreen(),
                                    const AlertsScreen(),
                                    const ToolsScreen(),
                                  ],
                                ),
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
                    ),
                  ],
                )
              : Column(
                  children: [
                    const TopStatusBar(height: AppTheme.statusBarHeight),
                    const Expanded(
                      child: ConnectionScreen(showTopStatusBar: false),
                    ),
                  ],
                ),
        );
      },
    );
  }

  int _getScreenIndex(AppModes mode) {
    switch (mode) {
      case AppModes.dashboard:
        return 0;
      case AppModes.mapping:
        return 1;
      case AppModes.navigation:
        return 2;
      case AppModes.dock:
        return 3;
      case AppModes.robotStatus:
        return 4;
      case AppModes.alerts:
        return 5;
      case AppModes.tools:
        return 6;
      case AppModes.teleop:
      case AppModes.settings:
        return 0;
    }
  }
}
