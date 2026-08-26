import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/setup_flow_controller.dart';
import '../../services/robot_discovery_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/design/radiating_icon.dart';
import 'setup_ap_hotspot_screen.dart';
import 'setup_robot_screen.dart';
import 'setup_scaffold.dart';

/// Discovery step: lists NavProMini robots already reachable on the
/// current network (see RobotDiscoveryService — works the same on every
/// platform, including web). "Set up a new robot" hands off to the AP-mode
/// hotspot flow for a robot that has no Wi-Fi configured yet. "Enter IP
/// manually" is always available underneath — subnet auto-detection is
/// permission-gated on Android and unreliable on several desktop/web
/// contexts, so a robot that's genuinely reachable can still fail to show
/// up in the scanned list.
class SetupWifiScreen extends StatefulWidget {
  const SetupWifiScreen({super.key});

  @override
  State<SetupWifiScreen> createState() => _SetupWifiScreenState();
}

class _SetupWifiScreenState extends State<SetupWifiScreen> {
  bool _manualEntryOpen = false;
  final _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SetupFlowController>().scanForRobots();
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  void _selectAndContinue(DiscoveredRobot robot) {
    context.read<SetupFlowController>().selectRobot(robot);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SetupRobotScreen()),
    );
  }

  Future<void> _connectByIp() async {
    final controller = context.read<SetupFlowController>();
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    final ok = await controller.connectByIp(ip);
    if (!mounted || !ok) return;
    _selectAndContinue(controller.selectedRobot!);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SetupFlowController>();

    return SetupScaffold(
      step: 2,
      totalSteps: 4,
      title: 'Connect to Your Robot',
      subtitle: 'Robots found on your current network.',
      secondaryLabel: 'Set up a new robot',
      onSecondary: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SetupApHotspotScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
              child:
                  _Body(controller: controller, onSelect: _selectAndContinue)),
          const SizedBox(height: AppSpacing.sm),
          _ManualEntry(
            open: _manualEntryOpen,
            controller: _ipController,
            busy: controller.manualLookupInProgress,
            error: controller.manualLookupError,
            onToggle: () =>
                setState(() => _manualEntryOpen = !_manualEntryOpen),
            onConnect: _connectByIp,
          ),
        ],
      ),
    );
  }
}

class _ManualEntry extends StatelessWidget {
  const _ManualEntry({
    required this.open,
    required this.controller,
    required this.busy,
    required this.error,
    required this.onToggle,
    required this.onConnect,
  });

  final bool open;
  final TextEditingController controller;
  final bool busy;
  final String? error;
  final VoidCallback onToggle;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    if (!open) {
      return TextButton.icon(
        onPressed: onToggle,
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text("Don't see your robot? Enter its IP address"),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Robot IP address',
                  hintText: '192.168.1.42',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: busy ? null : onConnect,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textOnPrimary),
                    )
                  : const Text('Go'),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.onSelect});

  final SetupFlowController controller;
  final ValueChanged<DiscoveredRobot> onSelect;

  @override
  Widget build(BuildContext context) {
    if (controller.scanError != null) {
      return _Message(
        icon: Icons.wifi_off_rounded,
        text: controller.scanError!,
        action: TextButton(
          onPressed: controller.scanForRobots,
          child: const Text('Retry'),
        ),
      );
    }

    if (controller.foundRobots.isEmpty) {
      return _Message(
        icon: controller.isScanning ? null : Icons.search_off_rounded,
        text: controller.isScanning
            ? 'Scanning your network for robots…'
            : 'No robots found on this network yet.',
        action: controller.isScanning
            ? null
            : TextButton(
                onPressed: controller.scanForRobots,
                child: const Text('Scan again')),
      );
    }

    return ListView.separated(
      itemCount:
          controller.foundRobots.length + (controller.isScanning ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        if (i >= controller.foundRobots.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final robot = controller.foundRobots[i];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            leading: const CircleAvatar(
              backgroundColor: AppColors.background,
              child: Icon(Icons.smart_toy_rounded, color: AppColors.primary),
            ),
            title: Text(robot.name,
                style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(robot.ip),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onSelect(robot),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.icon, this.action});

  final String text;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 48, color: AppColors.textSecondary)
          else
            const RadiatingIcon(
              icon: Icons.wifi_find_rounded,
              iconBackground: AppColors.primary,
              iconColor: AppColors.textOnPrimary,
              size: 96,
              coreSize: 56,
            ),
          const SizedBox(height: AppSpacing.md),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.sm),
            action!
          ],
        ],
      ),
    );
  }
}
