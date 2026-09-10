import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../screens/setup/setup_power_screen.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'design/radiating_icon.dart';

/// Shown by [AppShell] in place of the whole nav shell while the app's core
/// rosbridge connection isn't up yet — every screen behind the shell depends
/// on it (directly or via the shared RobotTelemetryProvider), so there's
/// nothing useful to show any of them until it resolves.
///
/// The connecting state animates a radiating pulse outward from the robot
/// icon — motion that reads as "actively searching for the robot", not
/// decoration — and cross-fades into a still error state if it fails. No
/// spinner: a plain indeterminate spinner communicates "waiting" but not
/// "reaching out", which is the more honest description of what's actually
/// happening (repeated connection attempts).
class ConnectingScaffold extends StatelessWidget {
  const ConnectingScaffold({super.key, required this.connection});

  final ConnectionProvider connection;

  @override
  Widget build(BuildContext context) {
    final hasError = connection.error != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: AnimatedSwitcher(
            duration: AppMotion.slow,
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: hasError
                ? _ErrorState(
                    key: const ValueKey('error'), connection: connection)
                : _ConnectingState(
                    key: const ValueKey('connecting'), connection: connection),
          ),
        ),
      ),
    );
  }
}

class _ConnectingState extends StatelessWidget {
  const _ConnectingState({super.key, required this.connection});

  final ConnectionProvider connection;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const RadiatingIcon(
          icon: Icons.smart_toy_rounded,
          iconBackground: AppColors.primary,
          iconColor: AppColors.textOnPrimary,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          connection.robot != null
              ? 'Connecting to ${connection.robot!.name}…'
              : 'Connecting…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text('Reaching the robot over the network',
            style: TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({super.key, required this.connection});

  final ConnectionProvider connection;

  Future<void> _switchRobot(BuildContext context) async {
    final conn = context.read<ConnectionProvider>();
    await conn.forget();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SetupPowerScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: const Icon(Icons.wifi_tethering_error_rounded,
              size: 36, color: AppColors.danger),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Connection Lost', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(
            connection.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ElevatedButton(
            onPressed: connection.reconnect, child: const Text('Retry')),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: () => _switchRobot(context),
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: const Text('Connect to a different robot'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
