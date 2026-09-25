import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _checkingRemote = false;
  bool _isApplyingUpdate = false;
  Map<String, dynamic>? _robotUpdates;
  String? _robotError;
  Timer? _statusTimer;
  Map<String, dynamic>? _liveStatus;
  List<String> _logTail = [];
  bool _dismissedLastFailure = false;
  bool _showLogsConsole = false;

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
      if (mounted) {
        setState(() {
          _robotError = 'Not connected to a robot';
          _robotUpdates = null;
          _loadingRobot = false;
          _checkingRemote = false;
        });
      }
      return;
    }

    if (fetchRemote) {
      setState(() => _checkingRemote = true);
    } else {
      setState(() => _loadingRobot = true);
    }
    setState(() => _robotError = null);

    try {
      final data = fetchRemote
          ? await api.checkRobotUpdates()
          : await api.getRobotUpdates();

      if (!mounted) return;
      setState(() {
        _robotUpdates = data;
        _loadingRobot = false;
        _checkingRemote = false;
      });

      // Check if an update is actively in-flight
      final lastUpdate = data['last_update'] as Map<String, dynamic>?;
      final phase = lastUpdate?['phase'] as String? ?? 'idle';
      if (phase == 'pulling' || phase == 'building' || phase == 'restarting') {
        _liveStatus = lastUpdate;
        _startStatusPolling();
      } else {
        // Just fetch the log tail once without initiating any loop
        _fetchLogTailOnce();
      }
    } catch (exc) {
      if (!mounted) return;
      setState(() {
        _robotError = exc.toString();
        _loadingRobot = false;
        _checkingRemote = false;
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
      final isUpdating = phase == 'pulling' || phase == 'building' || phase == 'restarting';

      setState(() {
        _liveStatus = status;
        _logTail = logs;
      });

      // If an update was running or being initiated
      if ((_statusTimer != null && _statusTimer!.isActive) || _isApplyingUpdate) {
        if (!isUpdating) {
          // Update completed or failed! Stop timer immediately
          _statusTimer?.cancel();
          _statusTimer = null;
          setState(() {
            _isApplyingUpdate = false;
          });
          // Refresh updates state once to reflect the new commit
          _checkRobotUpdates(fetchRemote: false);
        }
      }
    } catch (_) {
      // SDK might be restarting during service restart phase
    }
  }

  Future<void> _fetchLogTailOnce() async {
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
      setState(() {
        _liveStatus = status;
        _logTail = logs;
      });
    } catch (_) {}
  }

  Future<void> _applyRobotUpdate() async {
    final api = _getSdkApi();
    if (api == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update_alt_rounded, color: AppColors.primary),
            SizedBox(width: AppSpacing.sm),
            Text('Confirm Robot Update'),
          ],
        ),
        content: const Text(
          'This will pull the latest code, recompile ROS 2 packages, and restart companion services.\n\n'
          '• An atomic backup snapshot (install.prev) is automatically preserved.\n'
          '• In the event of a build error, changes are automatically rolled back.\n'
          '• Robot companion services will briefly restart upon completion.',
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

    setState(() {
      _isApplyingUpdate = true;
      _loadingRobot = true;
      _dismissedLastFailure = true;
      _showLogsConsole = true;
      _liveStatus = {
        'phase': 'pulling',
        'progress': 10,
        'message': 'Starting companion software update...',
      };
    });

    try {
      await api.applyRobotUpdate();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Companion update process started in background.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _startStatusPolling();
      _pollStatusOnce();
    } catch (exc) {
      if (!mounted) return;
      setState(() => _isApplyingUpdate = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start update: $exc'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingRobot = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _loadingRobot || _checkingRemote || _loadingGui;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Software Updates'),
        actions: [
          IconButton(
            icon: isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh All',
            onPressed: isBusy ? null : _refreshAll,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: CenteredFormColumn(
          maxWidth: 860,
          child: FadeSlideIn(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              children: [
                _buildRobotCard(),
                const SizedBox(height: AppSpacing.lg),
                _buildGuiCard(),
                const SizedBox(height: AppSpacing.xl),
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
    final isUpdating = _isApplyingUpdate || phase == 'pulling' || phase == 'building' || phase == 'restarting';

    final updateAvailable = updates?['update_available'] as bool? ?? false;
    final currentCommit = updates?['current_commit_short'] as String? ?? '---';
    final branch = updates?['branch'] as String? ?? 'nav2';
    final latestCommit = updates?['latest_commit'] as String? ?? '';
    final latestCommitShort = latestCommit.isNotEmpty
        ? (latestCommit.length > 7 ? latestCommit.substring(0, 7) : latestCommit)
        : currentCommit;
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

    final lastUpdate = updates?['last_update'] as Map<String, dynamic>?;
    final lastPhase = lastUpdate?['phase'] as String?;
    final lastError = lastUpdate?['error'] as String?;
    final lastMsg = lastUpdate?['message'] as String?;

    final isBusy = _loadingRobot || _checkingRemote || isUpdating;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.precision_manufacturing_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Robot Companion Stack',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSunken,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              branch,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Firmware, ROS 2 packages & companion launch services',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                if (_checkingRemote)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Checking...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isUpdating)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Updating (${live?['progress'] ?? 0}%)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (updateAvailable)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_upward_rounded, size: 14, color: AppColors.warning),
                        const SizedBox(width: 4),
                        Text(
                          '$commitsBehind new update${commitsBehind > 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
                        SizedBox(width: 4),
                        Text(
                          'Up to date',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            // Commit Comparison / Version Box
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CURRENT COMMIT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                currentCommit,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (updateAvailable) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TARGET COMMIT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: AppColors.warning,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  latestCommitShort,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (_robotError != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _robotError!,
                        style: const TextStyle(fontSize: 13, color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Last Update Failure banner (dismissible)
            if (!_dismissedLastFailure && !isUpdating && lastPhase == 'failed' && (lastError != null || lastMsg != null)) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Previous update attempt was rolled back',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lastMsg ?? lastError ?? 'Unknown error during execution.',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Dismiss',
                      onPressed: () => setState(() => _dismissedLastFailure = true),
                    ),
                  ],
                ),
              ),
            ],

            // Live update progress banner
            if (isUpdating) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sync_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Step: ${phase.toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const Spacer(),
                        Text(
                          '${live?['progress'] ?? 0}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ((live?['progress'] as num?)?.toDouble() ?? 0) / 100.0,
                        backgroundColor: AppColors.surfaceSunken,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      live?['message']?.toString() ?? 'Applying updates...',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],

            // Safety status banner
            if (!isUpdating && blockers.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: Colors.orange, size: 18),
                        SizedBox(width: AppSpacing.xs),
                        Text(
                          'Update Interlock Active',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...blockers.map((b) => Padding(
                          padding: const EdgeInsets.only(left: 22, top: 2),
                          child: Text('• $b', style: const TextStyle(fontSize: 12)),
                        )),
                  ],
                ),
              ),
            ],

            // Changelog
            if (changelog.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Incoming Commits',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: changelog.take(6).map((c) {
                    final parts = c.split(' ');
                    final hash = parts.isNotEmpty ? parts.first : '';
                    final msg = parts.length > 1 ? parts.sublist(1).join(' ') : c;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              hash,
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              msg,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            // Terminal Logs Viewer (Collapsible)
            if (_logTail.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  TextButton.icon(
                    icon: Icon(
                      _showLogsConsole ? Icons.terminal_rounded : Icons.terminal_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    label: Text(
                      _showLogsConsole ? 'Hide Update Console' : 'Show Update Console',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    onPressed: () => setState(() => _showLogsConsole = !_showLogsConsole),
                  ),
                  const Spacer(),
                  if (_showLogsConsole)
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      tooltip: 'Copy Logs',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _logTail.join('\n')));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Update logs copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                ],
              ),
              if (_showLogsConsole)
                Container(
                  width: double.infinity,
                  height: 180,
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161922),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.2)),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(
                      _logTail.join('\n'),
                      style: const TextStyle(
                        color: Color(0xFF00FF88),
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
            ],

            const SizedBox(height: AppSpacing.lg),

            // Action Buttons Row
            Row(
              children: [
                OutlinedButton.icon(
                  icon: _checkingRemote
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_rounded, size: 18),
                  label: Text(_checkingRemote ? 'Checking Remote...' : 'Check Remote'),
                  onPressed: isBusy ? null : () => _checkRobotUpdates(fetchRemote: true),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton.icon(
                  icon: const Icon(Icons.system_update_alt_rounded, size: 18),
                  label: Text('Update Robot${commitsBehind > 0 ? ' ($commitsBehind)' : ''}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: (!isBusy && updateAvailable && canUpdate)
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.devices_rounded, color: Colors.blue, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NavPro Mini GUI',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Platform: $platformName · Current: v$currentVer',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loadingGui)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (hasUpdate)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_upward_rounded, size: 14, color: AppColors.warning),
                        const SizedBox(width: 4),
                        Text(
                          'v$latestVer available',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
                        SizedBox(width: 4),
                        Text(
                          'Up to date',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            if (release != null && release.releaseNotes.isNotEmpty) ...[
              Text(
                'Release Notes (${release.releaseName})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  release.releaseNotes,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            const Text(
              'Installers & Downloads',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (kIsWeb)
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reload Web App'),
                    onPressed: () => _guiService.openUrl('.'),
                  ),

                // Android APK
                OutlinedButton.icon(
                  icon: const Icon(Icons.android_rounded, color: Colors.green, size: 18),
                  label: const Text('Android APK'),
                  onPressed: release?.apkUrl != null
                      ? () => _guiService.openUrl(release!.apkUrl!)
                      : () => _guiService.openUrl(release?.releaseUrl ??
                          'https://github.com/botforge-robotics/nav2_mission_planner_gui/releases'),
                ),

                // Linux Bundle
                OutlinedButton.icon(
                  icon: const Icon(Icons.terminal_rounded, color: Colors.deepOrange, size: 18),
                  label: const Text('Linux Build'),
                  onPressed: release?.linuxUrl != null
                      ? () => _guiService.openUrl(release!.linuxUrl!)
                      : () => _guiService.openUrl(release?.releaseUrl ??
                          'https://github.com/botforge-robotics/nav2_mission_planner_gui/releases'),
                ),

                // Windows
                OutlinedButton.icon(
                  icon: const Icon(Icons.desktop_windows_rounded, color: Colors.blue, size: 18),
                  label: const Text('Windows Build'),
                  onPressed: release?.windowsUrl != null
                      ? () => _guiService.openUrl(release!.windowsUrl!)
                      : () => _guiService.openUrl(release?.releaseUrl ??
                          'https://github.com/botforge-robotics/nav2_mission_planner_gui/releases'),
                ),

                // GitHub Releases
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
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
