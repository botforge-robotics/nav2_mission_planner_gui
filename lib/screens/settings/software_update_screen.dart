import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/gui_update_service.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/fade_in.dart';

class SoftwareUpdateScreen extends StatefulWidget {
  const SoftwareUpdateScreen({super.key});

  @override
  State<SoftwareUpdateScreen> createState() => _SoftwareUpdateScreenState();
}

class _SoftwareUpdateScreenState extends State<SoftwareUpdateScreen> {
  final GuiUpdateService _guiService = GuiUpdateService();

  // Robot state
  bool _loadingRobot = false;
  Map<String, dynamic>? _robotUpdates;
  String? _robotError;
  Timer? _statusTimer;
  Map<String, dynamic>? _liveStatus;
  List<String> _logTail = [];

  // GUI state
  bool _loadingGui = false;
  GuiReleaseInfo? _guiRelease;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    _checkGuiUpdates();
    _checkRobotUpdates(fetchRemote: false);
  }

  SdkApiService? _getSdkApi() {
    final conn = context.read<ConnectionProvider>();
    final robot = conn.robot;
    if (robot == null) return null;
    return SdkApiService(robot.ip);
  }

  Future<void> _checkGuiUpdates() async {
    if (!mounted) return;
    setState(() => _loadingGui = true);
    try {
      final info = await _guiService.checkLatestRelease();
      if (!mounted) return;
      setState(() {
        _guiRelease = info;
        _loadingGui = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingGui = false);
    }
  }

  Future<void> _checkRobotUpdates({bool fetchRemote = false}) async {
    final api = _getSdkApi();
    if (api == null) {
      setState(() {
        _robotError = 'Not connected to a robot';
        _robotUpdates = null;
      });
      return;
    }

    setState(() {
      _loadingRobot = true;
      _robotError = null;
    });

    try {
      final data = fetchRemote
          ? await api.checkRobotUpdates()
          : await api.getRobotUpdates();

      if (!mounted) return;
      setState(() {
        _robotUpdates = data;
        _loadingRobot = false;
      });

      // Check if update is currently in progress
      _pollStatusOnce();
    } catch (exc) {
      if (!mounted) return;
      setState(() {
        _robotError = exc.toString();
        _loadingRobot = false;
      });
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollStatusOnce();
    });
  }

  Future<void> _pollStatusOnce() async {
    final api = _getSdkApi();
    if (api == null) return;

    try {
      final res = await api.getRobotUpdateStatus();
      if (!mounted) return;
      final status = res['status'] as Map<String, dynamic>? ?? {};
      final logs = (res['log_tail'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      final phase = status['phase'] as String? ?? 'idle';
      setState(() {
        _liveStatus = status;
        _logTail = logs;
      });

      if (phase == 'pulling' || phase == 'building' || phase == 'restarting') {
        if (_statusTimer == null || !_statusTimer!.isActive) {
          _startStatusPolling();
        }
      } else if (phase == 'success' || phase == 'failed') {
        _statusTimer?.cancel();
        // Refresh updates state
        _checkRobotUpdates(fetchRemote: false);
      }
    } catch (_) {
      // SDK might be restarting
    }
  }

  Future<void> _applyRobotUpdate() async {
    final api = _getSdkApi();
    if (api == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Robot Update'),
        content: const Text(
          'This will pull the latest code, recompile ROS 2 packages, and restart services.\n\n'
          '• An atomic snapshot (install.prev) is automatically preserved.\n'
          '• In the event of a build error, changes are instantly rolled back.\n'
          '• Services will be briefly restarted upon completion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.system_update_alt_rounded),
            label: const Text('Start Update'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loadingRobot = true);
    try {
      await api.applyRobotUpdate();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update process started in background.')),
      );
      _startStatusPolling();
    } catch (exc) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start update: $exc')),
      );
    } finally {
      if (mounted) setState(() => _loadingRobot = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Software Updates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: SafeArea(
        child: CenteredFormColumn(
          maxWidth: 840,
          child: FadeSlideIn(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _buildRobotCard(),
                const SizedBox(height: AppSpacing.lg),
                _buildGuiCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRobotCard() {
    final updates = _robotUpdates;
    final live = _liveStatus;
    final phase = live?['phase'] as String? ?? 'idle';
    final isUpdating = phase == 'pulling' || phase == 'building' || phase == 'restarting';

    final updateAvailable = updates?['update_available'] as bool? ?? false;
    final currentCommit = updates?['current_commit_short'] as String? ?? '---';
    final branch = updates?['branch'] as String? ?? 'nav2';
    final commitsBehind = updates?['commits_behind'] as int? ?? 0;
    final changelog = (updates?['changelog'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final safety = updates?['safety'] as Map<String, dynamic>? ?? {};
    final canUpdate = safety['can_update'] as bool? ?? false;
    final blockers = (safety['blockers'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.precision_manufacturing_rounded,
                      color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Robot Companion Stack',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Branch: $branch · Commit: $currentCommit',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (_loadingRobot)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (isUpdating)
                  const Chip(
                    avatar: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: Text('Updating...'),
                  )
                else if (updateAvailable)
                  Chip(
                    backgroundColor: Colors.amber.withValues(alpha: 0.2),
                    label: Text('$commitsBehind update${commitsBehind > 1 ? 's' : ''} available'),
                  )
                else
                  const Chip(
                    avatar: Icon(Icons.check_circle_rounded,
                        size: 16, color: Colors.green),
                    label: Text('Up to date'),
                  ),
              ],
            ),
            const Divider(height: AppSpacing.xl),

            if (_robotError != null)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.red),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(_robotError!)),
                  ],
                ),
              ),

            // Live update progress banner
            if (isUpdating) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sync_rounded, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Phase: ${phase.toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text('${live?['progress'] ?? 0}%'),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    LinearProgressIndicator(
                      value: ((live?['progress'] as num?)?.toDouble() ?? 0) / 100.0,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      live?['message']?.toString() ?? 'Applying updates...',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Safety status
            if (!isUpdating && blockers.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: Colors.orange, size: 20),
                        SizedBox(width: AppSpacing.sm),
                        Text('Safety Interlocks Active',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ...blockers.map((b) => Padding(
                          padding: const EdgeInsets.only(left: 28, top: 2),
                          child: Text('• $b', style: const TextStyle(fontSize: 13)),
                        )),
                  ],
                ),
              ),

            // Changelog
            if (changelog.isNotEmpty) ...[
              const Text('Incoming Changes:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: changelog
                      .take(5)
                      .map((c) => Text('• $c',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace')))
                      .toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Terminal log viewer
            if (_logTail.isNotEmpty) ...[
              ExpansionTile(
                title: const Text('Update Logs Console',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                initiallyExpanded: isUpdating,
                children: [
                  Container(
                    width: double.infinity,
                    height: 180,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        _logTail.join('\n'),
                        style: const TextStyle(
                          color: Color(0xFF00FF66),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Action Buttons
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Check Remote'),
                  onPressed: isUpdating
                      ? null
                      : () => _checkRobotUpdates(fetchRemote: true),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton.icon(
                  icon: const Icon(Icons.system_update_alt_rounded),
                  label: const Text('Update Robot'),
                  onPressed: (!isUpdating && updateAvailable && canUpdate)
                      ? _applyRobotUpdate
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuiCard() {
    final release = _guiRelease;
    final currentVer = release?.currentVersion ?? '1.0.0';
    final latestVer = release?.latestVersion ?? '1.0.0';
    final hasUpdate = release?.hasUpdate ?? false;
    final platformName = _guiService.activePlatformName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.devices_rounded, color: Colors.blue),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mission Planner GUI App',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Platform: $platformName · Version: v$currentVer',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (_loadingGui)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (hasUpdate)
                  Chip(
                    backgroundColor: Colors.amber.withValues(alpha: 0.2),
                    label: Text('v$latestVer available'),
                  )
                else
                  const Chip(
                    avatar: Icon(Icons.check_circle_rounded,
                        size: 16, color: Colors.green),
                    label: Text('Up to date'),
                  ),
              ],
            ),
            const Divider(height: AppSpacing.xl),

            if (release != null && release.releaseNotes.isNotEmpty) ...[
              Text(
                'Latest Release: ${release.releaseName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  release.releaseNotes,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            const Text(
              'Available Release Builds:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.sm),

            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                // Web action
                if (kIsWeb)
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reload Web App'),
                    onPressed: () {
                      _guiService.openUrl('.');
                    },
                  ),

                // Android APK
                OutlinedButton.icon(
                  icon: const Icon(Icons.android_rounded, color: Colors.green),
                  label: const Text('Android APK'),
                  onPressed: release?.apkUrl != null
                      ? () => _guiService.openUrl(release!.apkUrl!)
                      : () => _guiService.openUrl(release?.releaseUrl ??
                          'https://github.com/botforge-robotics/nav2_mission_planner_gui/releases'),
                ),

                // Linux Bundle
                OutlinedButton.icon(
                  icon: const Icon(Icons.terminal_rounded, color: Colors.deepOrange),
                  label: const Text('Linux Build'),
                  onPressed: release?.linuxUrl != null
                      ? () => _guiService.openUrl(release!.linuxUrl!)
                      : () => _guiService.openUrl(release?.releaseUrl ??
                          'https://github.com/botforge-robotics/nav2_mission_planner_gui/releases'),
                ),

                // Windows
                OutlinedButton.icon(
                  icon: const Icon(Icons.desktop_windows_rounded, color: Colors.blue),
                  label: const Text('Windows Build'),
                  onPressed: release?.windowsUrl != null
                      ? () => _guiService.openUrl(release!.windowsUrl!)
                      : () => _guiService.openUrl(release?.releaseUrl ??
                          'https://github.com/botforge-robotics/nav2_mission_planner_gui/releases'),
                ),

                // GitHub Releases
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('GitHub Releases'),
                  onPressed: () => _guiService.openUrl(release?.releaseUrl ??
                      'https://github.com/botforge-robotics/nav2_mission_planner_gui/releases'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
