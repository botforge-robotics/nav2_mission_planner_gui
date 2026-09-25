import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:provider/provider.dart';

import '../../providers/setup_flow_controller.dart';
import '../../services/provisioning_service.dart';
import '../../services/wifi_join_service.dart';
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
  String? _joiningSsid;

  List<String> _availableNetworks = [];
  bool _loadingAvailableNetworks = false;
  bool _customSsidSelected = false;

  final _ssidController = TextEditingController();
  final _wifiSsidController = TextEditingController();
  final _wifiPasswordController = TextEditingController();
  final _robotNameController = TextEditingController();
  final _countryCodeController = TextEditingController();
  final _timezoneController = TextEditingController();

  bool _obscurePassword = true;
  ProvisioningStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCountryTimezone();
      _scanForHotspots();
    });
  }

  Future<void> _initCountryTimezone() async {
    // 1. Timezone detection
    String detectedTz = 'Asia/Kolkata';
    try {
      final tz = await FlutterTimezone.getLocalTimezone();
      if (tz.isNotEmpty) {
        detectedTz = tz;
      }
    } catch (_) {}
    if (_timezoneController.text.isEmpty && mounted) {
      setState(() => _timezoneController.text = detectedTz);
    }

    // 2. Wi-Fi Country Code detection (e.g. IN, US, GB, DE)
    if (_countryCodeController.text.isEmpty && mounted) {
      String cc = 'IN';
      try {
        final localeCc =
            WidgetsBinding.instance.platformDispatcher.locale.countryCode;
        if (localeCc != null && localeCc.isNotEmpty) {
          cc = localeCc.toUpperCase();
        } else if (detectedTz.contains('Kolkata') ||
            detectedTz.contains('India')) {
          cc = 'IN';
        } else if (detectedTz.contains('New_York') ||
            detectedTz.contains('Los_Angeles') ||
            detectedTz.contains('Chicago')) {
          cc = 'US';
        } else if (detectedTz.contains('London')) {
          cc = 'GB';
        }
      } catch (_) {}
      setState(() => _countryCodeController.text = cc);
    }
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    _robotNameController.dispose();
    _countryCodeController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  Future<void> _scanForHotspots() async {
    setState(() => _step = _ApStep.scanningHotspots);
    final wifiJoin = context.read<SetupFlowController>().wifiJoin;

    // Prefill site Wi-Fi name if device is currently on Wi-Fi (before joining robot AP)
    if (_wifiSsidController.text.trim().isEmpty) {
      try {
        final current = await wifiJoin.currentSsid();
        if (current != null &&
            current.isNotEmpty &&
            !current.startsWith(kSetupHotspotPrefix)) {
          _wifiSsidController.text = current;
        }
      } catch (_) {}
    }

    final found = await wifiJoin.scanForSetupHotspots();
    if (!mounted) return;
    setState(() {
      _foundHotspots = found;
      _step = _ApStep.enterSsid;
      // Nothing scanned (unsupported platform, permission denied, or
      // genuinely no hotspot in range) — open manual entry immediately.
      _manualSsidOpen = found.isEmpty;
    });
  }

  Future<void> _loadAvailableNetworks() async {
    setState(() => _loadingAvailableNetworks = true);
    final controller = context.read<SetupFlowController>();
    final networks = await controller.getAvailableSiteNetworks();
    if (!mounted) return;
    setState(() {
      // Filter out any potential non-SSID values (like timezone strings containing '/')
      _availableNetworks = networks
          .where((s) => !s.contains('/') && !s.startsWith(kSetupHotspotPrefix))
          .toList();
      _loadingAvailableNetworks = false;
      // Pre-fill with the first network if currently empty
      if (_wifiSsidController.text.trim().isEmpty && _availableNetworks.isNotEmpty) {
        _wifiSsidController.text = _availableNetworks.first;
      }
      // If current text isn't in scanned networks, select custom mode
      if (_wifiSsidController.text.trim().isNotEmpty &&
          !_availableNetworks.contains(_wifiSsidController.text.trim())) {
        _customSsidSelected = true;
      }
    });
  }

  Future<void> _joinHotspot(String ssid) async {
    final controller = context.read<SetupFlowController>();
    if (ssid.isEmpty) return;

    setState(() {
      _joiningSsid = ssid;
      _step = _ApStep.joining;
    });
    final ok = await controller.joinSetupHotspot(ssid);
    if (!mounted) return;
    if (ok) {
      setState(() => _step = _ApStep.credentialsForm);
      _loadAvailableNetworks();
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
    final tz = _timezoneController.text.trim();
    final cc = _countryCodeController.text.trim().toUpperCase();
    if (wifiSsid.isEmpty || wifiPassword.isEmpty || robotName.isEmpty) return;

    setState(() => _step = _ApStep.submitting);
    await for (final status in controller.submitProvisioning(
      wifiSsid: wifiSsid,
      wifiPassword: wifiPassword,
      robotName: robotName,
      timezone: tz.isNotEmpty ? tz : null,
      countryCode: cc.isNotEmpty ? cc : null,
    )) {
      if (!mounted) return;
      setState(() => _lastStatus = status);
      if (status.isTerminal) {
        if (status.phase == 'success') {
          setState(() => _step = _ApStep.success);
          if (controller.selectedRobot != null) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const SetupRobotScreen()),
            );
          } else {
            _findRobotOnSiteNetwork(robotName);
          }
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
        return _buildBusyStep(
          _joiningSsid != null
              ? 'Connecting to $_joiningSsid…\n(Auto-connecting with default password)'
              : 'Joining the robot\'s hotspot…',
          step: 2,
        );
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
          ? 'Select your robot below to connect automatically.'
          : 'Its name and password are shown on the robot\'s own screen.',
      primaryLabel: _manualSsidOpen ? 'Join Hotspot' : null,
      primaryEnabled: _ssidController.text.trim().isNotEmpty,
      onPrimary: _manualSsidOpen
          ? () => _joinHotspot(_ssidController.text.trim())
          : null,
      onBack: () {
        if (_manualSsidOpen && hasScanned) {
          setState(() => _manualSsidOpen = false);
        } else {
          Navigator.of(context).maybePop();
        }
      },
      backLabel: 'Back',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasScanned && !_manualSsidOpen) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Found ${_foundHotspots.length} nearby robot hotspot${_foundHotspots.length > 1 ? 's' : ''}:',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _foundHotspots.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) {
                  final ssid = _foundHotspots[i];
                  return Card(
                    elevation: 1,
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
                      title: Text(
                        ssid,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      subtitle: const Text(
                        'Tap to auto-connect',
                        style: TextStyle(color: AppColors.primary, fontSize: 13),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.primary),
                      onTap: () => _joinHotspot(ssid),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _scanForHotspots,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Scan again'),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _manualSsidOpen = true),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Enter manually'),
                ),
              ],
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
                    TextButton.icon(
                      onPressed: _scanForHotspots,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Scan again'),
                    ),
                  ],
                ),
              ),
            ),
          if (_manualSsidOpen) ...[
            if (hasScanned)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _manualSsidOpen = false),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back to nearby hotspots'),
                ),
              ),
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
            const SizedBox(height: AppSpacing.md),
            if (!hasScanned)
              TextButton.icon(
                onPressed: _scanForHotspots,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Scan again for hotspots'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCredentialsStep(BuildContext context) {
    final ready = _wifiSsidController.text.trim().isNotEmpty &&
        _wifiPasswordController.text.isNotEmpty &&
        _robotNameController.text.trim().isNotEmpty;

    final currentSsid = _wifiSsidController.text.trim();
    final isInList = _availableNetworks.contains(currentSsid);
    final String? dropdownValue = _customSsidSelected
        ? '__other__'
        : (isInList ? currentSsid : (_availableNetworks.isNotEmpty ? null : '__other__'));

    return SetupScaffold(
      step: 3,
      totalSteps: 5,
      title: 'Connect the Robot to Wi-Fi',
      subtitle: 'Select your site Wi-Fi network and name this robot.',
      primaryLabel: 'Save & Connect',
      primaryEnabled: ready,
      onPrimary: _submit,
      onBack: () => setState(() => _step = _ApStep.enterSsid),
      backLabel: 'Back to Hotspots',
      child: ListView(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Wi-Fi Network (SSID)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              if (_loadingAvailableNetworks)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                InkWell(
                  onTap: _loadAvailableNetworks,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded,
                            size: 14, color: AppColors.primary),
                        SizedBox(width: 4),
                        Text(
                          'Rescan',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_availableNetworks.isNotEmpty) ...[
            InputDecorator(
              decoration: const InputDecoration(
                prefixIcon:
                    Icon(Icons.wifi_rounded, color: AppColors.primary),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: dropdownValue,
                  isExpanded: true,
                  hint: const Text('Select available Wi-Fi network…'),
                  items: [
                    for (final net in _availableNetworks)
                      DropdownMenuItem<String>(
                        value: net,
                        child: Text(net, overflow: TextOverflow.ellipsis),
                      ),
                    const DropdownMenuItem<String>(
                      value: '__other__',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded,
                              size: 16, color: AppColors.textSecondary),
                          SizedBox(width: 8),
                          Text('Enter hidden / custom SSID…',
                              style: TextStyle(fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val == '__other__') {
                      setState(() {
                        _customSsidSelected = true;
                        if (_availableNetworks
                            .contains(_wifiSsidController.text.trim())) {
                          _wifiSsidController.clear();
                        }
                      });
                    } else if (val != null) {
                      setState(() {
                        _customSsidSelected = false;
                        _wifiSsidController.text = val;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (_customSsidSelected || _availableNetworks.isEmpty) ...[
            TextField(
              controller: _wifiSsidController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _availableNetworks.isNotEmpty
                    ? 'Custom Wi-Fi Network Name'
                    : 'Wi-Fi Network Name',
                hintText: 'Enter SSID',
                prefixIcon: const Icon(Icons.wifi_lock_rounded),
                suffixIcon: _availableNetworks.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Back to dropdown list',
                        onPressed: () {
                          setState(() {
                            _customSsidSelected = false;
                            if (_availableNetworks.isNotEmpty) {
                              _wifiSsidController.text =
                                  _availableNetworks.first;
                            }
                          });
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(
            controller: _wifiPasswordController,
            onChanged: (_) => setState(() {}),
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Wi-Fi Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _robotNameController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Robot Name',
              hintText: 'bot-1',
              prefixIcon: Icon(Icons.smart_toy_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _countryCodeController,
                  maxLength: 2,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (val) {
                    final upper = val.toUpperCase();
                    if (upper != val) {
                      _countryCodeController.value =
                          _countryCodeController.value.copyWith(
                        text: upper,
                        selection:
                            TextSelection.collapsed(offset: upper.length),
                      );
                    }
                    setState(() {});
                  },
                  decoration: const InputDecoration(
                    labelText: 'Country Code',
                    hintText: 'IN, US, GB',
                    counterText: '',
                    prefixIcon: Icon(Icons.flag_outlined),
                    helperText: 'Wi-Fi domain',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 6,
                child: TextField(
                  controller: _timezoneController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Timezone',
                    hintText: 'Asia/Kolkata',
                    prefixIcon: Icon(Icons.schedule_rounded),
                    helperText: 'Schedules & clock',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubmittingStep() {
    final phase = _lastStatus?.phase ?? 'submitted';
    final message = _lastStatus?.message;
    final label = (message != null && message.isNotEmpty)
        ? message
        : switch (phase) {
            'joining_wifi' => 'Robot is joining your Wi-Fi…',
            'saving' => 'Saving robot settings…',
            _ => 'Connecting to robot on Wi-Fi…',
          };
    return _buildBusyStep(label);
  }

  Widget _buildBusyStep(String label, {int step = 3}) {
    return SetupScaffold(
      step: step,
      totalSteps: 5,
      title: 'Setting Up',
      showBackButton: false,
      showBottomBackButton: false,
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
      onBack: () => setState(() => _step = _ApStep.enterSsid),
      backLabel: 'Back to Hotspots',
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
