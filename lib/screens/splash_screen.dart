import 'package:flutter/material.dart';

import '../services/robot_connection_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell/app_shell.dart';
import '../widgets/design/fade_in.dart';
import '../widgets/design/radiating_icon.dart';
import 'setup/setup_power_screen.dart';

/// Routes to AppShell if a robot was previously set up, otherwise starts
/// the setup flow — a *local* decision (was one ever saved?), not a network
/// one. AppShell's own ConnectionProvider is what actually reaches out to
/// it and owns retrying — this screen deliberately doesn't pre-probe that
/// itself and second-guess "saved" into "never set up" on a failed probe;
/// see _resolve's own doc for why that was a real bug. Reuses the same
/// [RadiatingIcon] "reaching out" motion AppShell's ConnectingScaffold uses
/// even though this screen itself no longer reaches out to anything — the
/// handoff to AppShell's own identical-looking connecting state should
/// read as one continuous action, not a jump cut to a different one.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    final saved = await RobotConnectionStore().load();
    // In fleet mode or if fleet server is configured, operators enter directly
    // into NavPro Mini Fleet shell without being forced into standalone single-robot setup.
    // Adding physical robots is performed within the fleet coordinator.
    final hasRobotOrFleet = saved != null &&
        (saved.ip.isNotEmpty || saved.isFleetMode || (saved.fleetServerHost != null && saved.fleetServerHost!.isNotEmpty));

    final destination =
        hasRobotOrFleet ? const AppShell() : const SetupPowerScreen();
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FadeSlideIn(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RadiatingIcon(
                    iconBackground: AppColors.textOnPrimary.withValues(alpha: 0.16),
                    iconColor: AppColors.textOnPrimary,
                    ringColor: AppColors.textOnPrimary,
                    size: 160,
                    coreSize: 120,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Image.asset(
                        'assets/robot_photo.png',
                        width: 80,
                        height: 80,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text(
                    'NavPro Mini',
                    style: TextStyle(
                      color: AppColors.textOnPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Checking for your robot…',
                    style: TextStyle(
                        color: AppColors.textOnPrimary.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
