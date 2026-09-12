import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'setup_scaffold.dart';
import 'setup_wifi_screen.dart';

class SetupPowerScreen extends StatelessWidget {
  const SetupPowerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      step: 1,
      totalSteps: 5,
      title: 'Power on Your Robot',
      subtitle:
          'Make sure your robot is powered on and its status light is lit.',
      primaryLabel: 'Next',
      onPrimary: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SetupWifiScreen()),
      ),
      child: Center(
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.power_settings_new_rounded,
              size: 72, color: AppColors.primary),
        ),
      ),
    );
  }
}
