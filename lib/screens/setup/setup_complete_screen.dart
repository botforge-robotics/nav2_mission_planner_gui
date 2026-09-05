import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell/app_shell.dart';
import 'setup_scaffold.dart';

class SetupCompleteScreen extends StatefulWidget {
  const SetupCompleteScreen({super.key});

  @override
  State<SetupCompleteScreen> createState() => _SetupCompleteScreenState();
}

class _SetupCompleteScreenState extends State<SetupCompleteScreen> {
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    WidgetsBinding.instance.addPostFrameCallback((_) => _confetti.play());
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      step: 4,
      totalSteps: 4,
      title: 'Setup Complete!',
      subtitle: 'Your robot is ready to roll.',
      primaryLabel: 'Go to Dashboard',
      onPrimary: () {
        context.read<ConnectionProvider>().reconnect();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppShell()),
          (route) => false,
        );
      },
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          const Center(child: _RobotBadge()),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 24,
              maxBlastForce: 18,
              minBlastForce: 6,
              gravity: 0.25,
              emissionFrequency: 0.0, // one burst, not a continuous stream
              colors: const [
                AppColors.primary,
                AppColors.accent,
                AppColors.success,
                AppColors.warning,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A robot badge with a soft success ring — reuses the same
/// smart_toy_rounded glyph used for robot rows elsewhere in the app
/// (SetupWifiScreen's list, DashboardScreen), not a one-off icon choice.
class _RobotBadge extends StatelessWidget {
  const _RobotBadge();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 120,
          height: 120,
          decoration: const BoxDecoration(
              color: AppColors.primary, shape: BoxShape.circle),
          child: const Icon(Icons.smart_toy_rounded,
              size: 64, color: AppColors.textOnPrimary),
        ),
        Positioned(
          bottom: 4,
          right: 4,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 3),
            ),
            child: const Icon(Icons.check_rounded,
                size: 22, color: AppColors.textOnPrimary),
          ),
        ),
      ],
    );
  }
}
