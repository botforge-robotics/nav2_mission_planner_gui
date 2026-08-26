import 'package:flutter/material.dart';

import '../services/robot_connection_store.dart';
import '../services/rosbridge_probe.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell/app_shell.dart';
import '../widgets/design/fade_in.dart';
import '../widgets/design/radiating_icon.dart';
import 'setup/setup_power_screen.dart';

/// Checks for a previously set-up robot and silently attempts to reconnect;
/// on success skips straight to Dashboard, otherwise starts the setup flow.
/// Reuses the same [RadiatingIcon] "reaching out" motion AppShell's
/// ConnectingScaffold uses — this screen *is* the very first connection
/// attempt, so it should read as the same action, not a different one.
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
    Widget destination;
    if (saved != null && await probeRosbridge(saved.rosbridgeUrl)) {
      destination = const AppShell();
    } else {
      destination = const SetupPowerScreen();
    }
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Center(
        child: FadeSlideIn(
          child: Column(
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
                  child: Image.asset('assets/robot_photo.png',
                      fit: BoxFit.contain),
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
    );
  }
}
