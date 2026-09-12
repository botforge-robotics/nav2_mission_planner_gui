import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/setup_flow_controller.dart';
import '../../services/provisioning_service.dart';
import '../../theme/app_theme.dart';
import 'setup_robot_screen.dart';
import 'setup_scaffold.dart';

enum _ApStep {
  scanningHotspots,
  enterSsid,
  joining,
  credentialsForm,
  submitting,
  success,
  error
}

/// AP-mode setup for a robot with no Wi-Fi configured yet: join its
/// NavPro-Setup-XXXXXX hotspot, then submit the site Wi-Fi + robot name
/// directly to provision_portal.py — all native calls, no browser/WebView.
///
/// Scans for nearby NavPro-Setup-* hotspots and offers a tap-to-select list
/// first (Android only — real scanning, not this package's fault, since
/// Apple gives apps no API to list nearby networks on iOS at all). Manual
/// SSID entry is always available underneath as a fallback, pre-filled with
/// a hint pointing at the robot's own OLED — the one path that works
/// identically everywhere `wifi_iot` runs. The whole join step is skipped
/// in favor of the manual-instructions screen on web/desktop, where there
/// is no Wi-Fi API to call at all — see WifiJoinService.isSupported.
class SetupApHotspotScreen extends StatefulWidget {
  const SetupApHotspotScreen({super.key});

  @override
  State<SetupApHotspotScreen> createState() => _SetupApHotspotScreenState();
}

class _SetupApHotspotScreenState extends State<SetupApHotspotScreen> {
  _ApStep _step = _ApStep.scanningHotspots;
  String? _error;

  List<String> _foundHotspots = [];
  bool _manualSsidOpen = false;

  final _ssidController = TextEditingController();
  final _wifiSsidController = TextEditingController();
  final _wifiPasswordController = TextEditingController();
  final _robotNameController = TextEditingController();

  ProvisioningStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanForHotspots());
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    _robotNameController.dispose();
    super.dispose();
  }

  Future<void> _scanForHotspots() async {
    setState(() => _step = _ApStep.scanningHotspots);
    final wifiJoin = context.read<SetupFlowController>().wifiJoin;
    final found = await wifiJoin.scanForSetupHotspots();
    if (!mounted) return;
    setState(() {
      _foundHotspots = found;
      _step = _ApStep.enterSsid;
      // Nothing scanned (unsupported platform, permission denied, or
      // genuinely no hotspot in range) — open manual entry immediately
      // rather than showing an empty list with a collapsed fallback hidden
      // underneath it.
      _manualSsidOpen = found.isEmpty;
    });
  }

  Future<void> _joinHotspot(String ssid) async {
    final controller = context.read<SetupFlowController>();
    if (ssid.isEmpty) return;

    setState(() => _step = _ApStep.joining);
    final ok = await controller.joinSetupHotspot(ssid);
    if (!mounted) return;
    if (ok) {
      setState(() => _step = _ApStep.credentialsForm);
    } else {
      setState(() {
        _error = controller.apJoinError;
        _step = _ApStep.error;
      });
    }
  }

  Future<void> _submit() async {
    final controller = context.read<SetupFlowController>();
    final wifiSsid = _wifiSsidController.text.trim();
    final wifiPassword = _wifiPasswordController.text;
    final robotName = _robotNameController.text.trim();
    if (wifiSsid.isEmpty || wifiPassword.isEmpty || robotName.isEmpty) return;

    setState(() => _step = _ApStep.submitting);
    await for (final status in controller.submitProvisioning(
      wifiSsid: wifiSsid,
      wifiPassword: wifiPassword,
      robotName: robotName,
    )) {
      if (!mounted) return;
      setState(() => _lastStatus = status);
      if (status.isTerminal) {
        if (status.phase == 'success') {
          setState(() => _step = _ApStep.success);
          _findRobotOnSiteNetwork(robotName);
        } else {
          setState(() {
            _error =
                status.message.isNotEmpty ? status.message : 'Setup failed.';
            _step = _ApStep.error;
          });
        }
      }
    }
  }

  /// The robot restarts onto the site network after a successful join, so
  /// it won't be reachable at 10.42.0.1 for long — poll the discovery
  /// service on the *site* network for it. The phone itself needs to have
  /// rejoined that network too; this only starts finding results once it
  /// has (handled by the user manually reconnecting, prompted below).
  Future<void> _findRobotOnSiteNetwork(String robotName) async {
    final discovery = context.read<SetupFlowController>().discovery;
    for (var attempt = 0; attempt < 20; attempt++) {
      await Future.delayed(const Duration(seconds: 2));
      final subnet = await discovery.currentSubnetPrefix();
      if (subnet == null) continue;
      await for (final robot in discovery.scan(subnetPrefix: subnet)) {
        if (robot.name == robotName && mounted) {
          context.read<SetupFlowController>().selectRobot(robot);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SetupRobotScreen()),
          );
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wifiJoin = context.read<SetupFlowController>().wifiJoin;

    if (!wifiJoin.isSupported) {
      return SetupScaffold(
        step: 2,
        totalSteps: 5,
        title: 'Set Up a New Robot',
        subtitle:
            'Hotspot setup needs a mobile device — join manually instead.',
        child: _ManualJoinInstructions(),
      );
    }

    switch (_step) {
      case _ApStep.scanningHotspots:
        return _buildBusyStep('Looking for nearby robot hotspots…', step: 2);
      case _ApStep.enterSsid:
        return _buildSsidStep(context);
      case _ApStep.joining:
        return _buildBusyStep('Joining the robot\'s hotspot…', step: 2);
      case _ApStep.credentialsForm:
        return _buildCredentialsStep(context);
      case _ApStep.submitting:
        return _buildSubmittingStep();
      case _ApStep.success:
        return _buildBusyStep('Found it — connecting…', step: 4);
      case _ApStep.error:
        return _buildErrorStep(context);
    }
  }

  Widget _buildSsidStep(BuildContext context) {
    final hasScanned = _foundHotspots.isNotEmpty;
    return SetupScaffold(
      step: 2,
      totalSteps: 5,
      title: 'Find Your Robot\'s Hotspot',
      subtitle: hasScanned
          ? 'Select your robot below.'
          : 'Its name and password are shown on the robot\'s own screen.',
      primaryLabel: _manualSsidOpen ? 'Join Hotspot' : null,
      primaryEnabled: _ssidController.text.trim().isNotEmpty,
      onPrimary: _manualSsidOpen
          ? () => _joinHotspot(_ssidController.text.trim())
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasScanned) ...[
            Expanded(
              child: ListView.separated(
                itemCount: _foundHotspots.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) {
                  final ssid = _foundHotspots[i];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.background,
                        child: Icon(Icons.wifi_tethering_rounded,
                            color: AppColors.primary),
                      ),
                      title: Text(ssid,
                          style: Theme.of(context).textTheme.titleMedium),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _joinHotspot(ssid),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: _scanForHotspots,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Scan again'),
            ),
          ],
          if (!hasScanned && !_manualSsidOpen)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off_rounded,
                        size: 48, color: AppColors.textSecondary),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'No robot hotspots found nearby.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                        onPressed: _scanForHotspots,
                        child: const Text('Scan again')),
                  ],
                ),
              ),
            ),
          if (_manualSsidOpen) ...[
            TextField(
              controller: _ssidController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Hotspot name (SSID)',
                hintText: 'NavPro-Setup-XXXXXX',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Password: navprosetup',
                style: TextStyle(color: AppColors.textSecondary)),
          ] else
            TextButton.icon(
              onPressed: () => setState(() => _manualSsidOpen = true),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text("Don't see it? Enter the name manually"),
            ),
        ],
      ),
    );
  }

  Widget _buildCredentialsStep(BuildContext context) {
    final ready = _wifiSsidController.text.trim().isNotEmpty &&
        _wifiPasswordController.text.isNotEmpty &&
        _robotNameController.text.trim().isNotEmpty;
    return SetupScaffold(
      step: 3,
      totalSteps: 5,
      title: 'Connect the Robot to Wi-Fi',
      subtitle: 'Enter your site Wi-Fi and a name for this robot.',
      primaryLabel: 'Save & Connect',
      primaryEnabled: ready,
      onPrimary: _submit,
      child: ListView(
        children: [
          TextField(
            controller: _wifiSsidController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Wi-Fi network name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _wifiPasswordController,
            onChanged: (_) => setState(() {}),
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Wi-Fi password'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _robotNameController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Robot name', hintText: 'bot-1'),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmittingStep() {
    final phase = _lastStatus?.phase ?? 'submitted';
    final label = switch (phase) {
      'joining_wifi' => 'Robot is joining your Wi-Fi…',
      'saving' => 'Saving robot name…',
      _ => 'Submitting…',
    };
    return _buildBusyStep(label);
  }

  Widget _buildBusyStep(String label, {int step = 3}) {
    return SetupScaffold(
      step: step,
      totalSteps: 5,
      title: 'Setting Up',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorStep(BuildContext context) {
    return SetupScaffold(
      step: 3,
      totalSteps: 5,
      title: 'Setup Failed',
      primaryLabel: 'Try Again',
      onPrimary: () => setState(() => _step = _ApStep.enterSsid),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.danger),
            const SizedBox(height: AppSpacing.md),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualJoinInstructions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_rounded, size: 48, color: AppColors.textSecondary),
          SizedBox(height: AppSpacing.md),
          Text(
            'Open your Wi-Fi settings, join the network named '
            '"NavPro-Setup-XXXXXX" shown on the robot\'s screen '
            '(password: navprosetup), then come back and open '
            'http://10.42.0.1 to finish setup.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
