import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_status.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/sdk_state_service.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/push_with_telemetry.dart';
import '../../widgets/design/animated_metric.dart';
import '../../widgets/design/fade_in.dart';
import '../../widgets/design/status_pulse.dart';
import '../alerts/alerts_log_screen.dart';
import '../dock/dock_charge_screen.dart';
import '../robot_status/robot_status_screen.dart';
import 'coming_soon_screen.dart';
import 'help_about_screen.dart';
import 'tools_api_screen.dart';

/// Reference §13/§16 (Settings). Only entries backed by something real are
/// full screens here: Alerts & Fault Log (already built — reused, not
/// duplicated), Developer Tools (raw API + topics/services/actions),
/// Developer Mode (a real local preference
/// gating nothing fictional — see its own tile), Help & About (app
/// version). Robot Settings, Users & Roles, Robot Behavior, and Map
/// Settings were removed by request — none had a real backend anywhere in
/// this stack (no accounts system, no persisted robot-behavior/map-default
/// settings on the robot), so there was nothing genuine to expose there.
/// Notification Settings is the one remaining "coming soon" entry.
///
/// The Dashboard's robot card used to open Robot Status / Dock & Charge on
/// tap; that card is now purely informational, and this screen's own
/// _RobotSummaryCard — at the very top, above every other tile — is the
/// tap-through entry point instead.
class SettingsHomeScreen extends StatefulWidget {
  const SettingsHomeScreen({super.key});

  @override
  State<SettingsHomeScreen> createState() => _SettingsHomeScreenState();
}

class _SettingsHomeScreenState extends State<SettingsHomeScreen> {
  static const _devModeKey = 'dev_mode_enabled';
  bool _devMode = false;
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _devMode = prefs.getBool(_devModeKey) ?? false;
      _version = info.version;
    });
  }

  Future<void> _setDevMode(bool value) async {
    setState(() => _devMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_devModeKey, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: CenteredFormColumn(
          maxWidth: 640,
          child: FadeSlideIn(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const _RobotSummaryCard(),
                const SizedBox(height: AppSpacing.lg),
                _SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notification Settings',
                  subtitle: 'Not available yet',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ComingSoonScreen(
                        title: 'Notification Settings',
                        explanation:
                            'There\'s no notification-preference storage on the robot or in '
                            'this app yet — Alerts & Fault Log already shows every event live.',
                      ),
                    ),
                  ),
                ),
                _SettingsTile(
                  icon: Icons.report_gmailerrorred_rounded,
                  title: 'Alerts & Fault Log',
                  subtitle: 'View live event history',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AlertsLogScreen())),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Divider(),
                ),
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.code_rounded),
                    title: const Text('Developer Mode'),
                    subtitle: const Text('Show the raw API tool below'),
                    value: _devMode,
                    onChanged: _setDevMode,
                  ),
                ),
                if (_devMode)
                  _SettingsTile(
                    icon: Icons.terminal_rounded,
                    title: 'Developer Tools',
                    subtitle: 'Raw API, topics, services, actions',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ToolsApiScreen())),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Divider(),
                ),
                _SettingsTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Help & Support',
                  subtitle: 'About this app',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const HelpAboutScreen())),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.lg),
                  child: Center(
                    child: Text(
                      _version != null ? 'App version $_version' : '',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
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
}

/// The robot's live status and battery, with the two tap zones the
/// Dashboard's card used to have: the identity row opens full Robot Status,
/// the battery row opens Dock & Charge. Same underlying data/derivation as
/// the Dashboard card (deriveRobotStatus over the same shared
/// RobotTelemetryProvider + a poll of the SDK's /state) — just relocated,
/// not reimplemented.
class _RobotSummaryCard extends StatelessWidget {
  const _RobotSummaryCard();

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final telemetry = context.watch<RobotTelemetryProvider>();
    final robot = connection.robot;
    if (robot == null) return const SizedBox.shrink();

    return StreamBuilder<SdkState>(
      initialData: SdkState.unknown,
      stream: SdkStateService(robot.ip).watch(),
      builder: (context, snapshot) {
        final sdkState = snapshot.data ?? SdkState.unknown;
        final status =
            deriveRobotStatus(telemetry: telemetry, sdkState: sdkState);
        final isActive = status == RobotStatus.moving ||
            status == RobotStatus.mapping ||
            status == RobotStatus.missionInProgress ||
            status == RobotStatus.charging;
        final battery = telemetry.batteryPercentage;
        final charging = telemetry.chargeStatus == ChargeStatus.charging ||
            telemetry.chargeStatus == ChargeStatus.full;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () =>
                    pushWithTelemetry(context, const RobotStatusScreen()),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                  child: Row(
                    children: [
                      Image.asset('assets/robot_photo.png',
                          width: 48, height: 48, fit: BoxFit.contain),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(robot.name,
                                style: Theme.of(context).textTheme.titleMedium),
                            Row(
                              children: [
                                StatusPulseDot(
                                    color: status.color,
                                    live: isActive,
                                    size: 7),
                                const SizedBox(width: 6),
                                AnimatedSwitcher(
                                  duration: AppMotion.fast,
                                  child: Text(
                                    'Online · ${status.label}',
                                    key: ValueKey(status),
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () =>
                    pushWithTelemetry(context, const DockChargeScreen()),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
                  child: Row(
                    children: [
                      Icon(
                        charging
                            ? Icons.bolt_rounded
                            : Icons.battery_full_rounded,
                        size: 16,
                        color: charging
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: AnimatedMetricBar(
                          value: battery != null ? battery / 100 : 0,
                          backgroundColor: AppColors.border,
                          color:
                              charging ? AppColors.success : AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AnimatedMetricText(
                        value: battery,
                        formatter: (v) => '${v.round()}%',
                        style: AppTextStyles.metricSmall,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        subtitle: Text(subtitle,
            style: const TextStyle(color: AppColors.textSecondary)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
