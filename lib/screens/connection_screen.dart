import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/branding_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/top_status_bar/top_status_bar.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../services/tf_service.dart';
import '../services/pc_api_service.dart';
import 'home_screen.dart';

class ConnectionScreen extends StatefulWidget {
  final bool showTopStatusBar;

  const ConnectionScreen({super.key, this.showTopStatusBar = true});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final ipController = TextEditingController();
  final FocusNode _ipFocus = FocusNode();
  bool _isLoading = false;
  bool _scanning = false;
  bool _showManualIp = false;
  bool _reconnecting = false;
  String? _selectedIp;
  String _selectedPort = _defaultPort;
  bool _claimedOnline = false;
  Map<String, dynamic>? _claim;

  /// Deduped robots: ip -> {ip, port, label, source}
  final Map<String, _RobotEntry> _robots = {};

  static const String _defaultPort = '9090';

  @override
  void initState() {
    super.initState();
    final connectionProvider =
        Provider.of<ConnectionProvider>(context, listen: false);
    for (final r in connectionProvider.robots) {
      _robots[r.ip] = _RobotEntry(
        ip: r.ip,
        port: r.port,
        label: r.ip,
        source: 'recent',
      );
    }
    if (connectionProvider.ip.isNotEmpty) {
      _select(connectionProvider.ip, connectionProvider.port);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshClaim();
      await _scanNearby();
    });
    // A page refresh (Flutter Web) or app relaunch drops the whole runtime,
    // including the live rosbridge connection — reconnect to whichever
    // robot was last active instead of forcing the user back through
    // manual selection every time (see ConnectionProvider.autoReconnect).
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoReconnect());
  }

  Future<void> _tryAutoReconnect() async {
    final connectionProvider =
        Provider.of<ConnectionProvider>(context, listen: false);
    if (!connectionProvider.hasLastRobot || connectionProvider.isConnected) {
      return;
    }
    setState(() => _reconnecting = true);
    try {
      final success = await connectionProvider.autoReconnect();
      if (!mounted) return;
      if (success) {
        connectionProvider.markRobotConfigured(
          connectionProvider.activeRobot!.id,
        );
        await Provider.of<SettingsProvider>(context, listen: false)
            .applyNavProMiniDefaults();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        return;
      }
    } catch (_) {
      // Silent — this is a background attempt, not a user-initiated one.
      // Falls through to the normal manual connect screen below.
    }
    if (mounted) setState(() => _reconnecting = false);
  }

  @override
  void dispose() {
    ipController.dispose();
    _ipFocus.dispose();
    super.dispose();
  }

  void _select(String ip, [String port = _defaultPort]) {
    setState(() {
      _selectedIp = ip;
      _selectedPort = port;
      ipController.text = ip;
    });
  }

  Future<void> _refreshClaim() async {
    final hb = await PcApiService.heartbeat();
    Map<String, dynamic>? claim;
    var online = false;
    if (hb != null && hb['claimed'] == true) {
      claim = Map<String, dynamic>.from(hb['robot'] as Map? ?? {});
      online = hb['online'] == true;
    } else {
      claim = await PcApiService.getClaim();
    }
    if (!mounted) return;
    setState(() {
      _claim = claim;
      _claimedOnline = online;
      final ip = claim?['ip']?.toString();
      final port = claim?['port']?.toString() ?? _defaultPort;
      if (ip != null && ip.isNotEmpty) {
        _robots[ip] = _RobotEntry(
          ip: ip,
          port: port,
          label: 'NavProMini',
          source: 'claimed',
          online: online,
        );
        _selectedIp ??= ip;
        _selectedPort = _selectedIp == ip ? port : _selectedPort;
      }
    });
  }

  Future<void> _scanNearby() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final list = await PcApiService.nearby(scan: true);
      if (!mounted) return;
      setState(() {
        for (final r in list) {
          final ip = r['ip']?.toString() ?? '';
          if (ip.isEmpty) continue;
          final port = r['port']?.toString() ?? _defaultPort;
          final prev = _robots[ip];
          _robots[ip] = _RobotEntry(
            ip: ip,
            port: port,
            label: 'NavProMini',
            source: 'scan',
            online: prev?.online ?? true,
          );
        }
        // Auto-select if nothing selected and we found robots
        if (_selectedIp == null && _robots.isNotEmpty) {
          final first = _robots.values.first;
          _selectedIp = first.ip;
          _selectedPort = first.port;
          ipController.text = first.ip;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            backgroundColor: Colors.redAccent.withValues(alpha: 0.9),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _releaseClaim() async {
    await PcApiService.releaseClaim();
    await _refreshClaim();
  }

  Future<void> _copyLink() async {
    final ip = _selectedIp ?? _claim?['ip']?.toString() ?? '';
    if (ip.isEmpty) return;
    final port = _selectedPort;
    final link = 'ws://$ip:$port';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $link'),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  Future<void> _connect() async {
    final ip = (_selectedIp ?? ipController.text).trim();
    final port = _selectedPort;
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a robot or enter an IP'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (_isLoading) return;

    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Theme(
        data: AppTheme.lightTheme,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Provider.of<BrandingProvider>(context, listen: false)
                    .themeColor,
              ),
              const SizedBox(width: AppSpacing.lg),
              Flexible(child: Text('Connecting to $ip…')),
            ],
          ),
        ),
      ),
    );

    try {
      TFService.resetAllServices();
      final connectionProvider =
          Provider.of<ConnectionProvider>(context, listen: false);
      final success = await connectionProvider.connect(
        ip,
        port,
        name: 'NavProMini $ip',
        createNew: false,
      );

      if (mounted) Navigator.pop(context);

      if (success) {
        connectionProvider.markRobotConfigured(
          connectionProvider.activeRobot!.id,
        );
        await Provider.of<SettingsProvider>(context, listen: false)
            .applyNavProMiniDefaults();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected to $ip'),
              backgroundColor: Colors.green.withValues(alpha: 0.9),
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connection failed — is rosbridge on :$port?'),
              backgroundColor: Colors.redAccent.withValues(alpha: 0.9),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.redAccent.withValues(alpha: 0.9),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _robots.values.toList()
      ..sort((a, b) {
        // claimed / online first
        if (a.source == 'claimed' && b.source != 'claimed') return -1;
        if (b.source == 'claimed' && a.source != 'claimed') return 1;
        return a.ip.compareTo(b.ip);
      });

    // Locally opted into the redesigned light theme rather than flipping
    // main.dart's global theme — most other screens still render against
    // AppTheme.darkTheme and haven't been restyled yet (see plan §1: ship
    // light+dark side by side, flip the app-wide switch only once enough
    // screens are migrated).
    return Theme(
      data: AppTheme.lightTheme,
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Scaffold(
          backgroundColor: AppColors.lightBackground,
          body: Stack(
            children: [
              if (_reconnecting)
                Positioned.fill(
                  child: Container(
                    color: AppColors.lightBackground.withValues(alpha: 0.96),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: colorScheme.primary),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            'Reconnecting to ${Provider.of<ConnectionProvider>(context, listen: false).lastRobotName ?? Provider.of<ConnectionProvider>(context, listen: false).lastRobotIp}…',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Column(
                children: [
                  if (widget.showTopStatusBar)
                    const TopStatusBar(
                      height: AppTheme.statusBarHeight,
                    ),
                  Expanded(
                    child: SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl,
                            vertical: AppSpacing.xl,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: Container(
                                    padding:
                                        const EdgeInsets.all(AppSpacing.md),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.smart_toy_outlined,
                                      size: 28,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  'Connect to Robot',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Choose a robot, then connect (port $_defaultPort)',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xl),

                                // Robot list (single select)
                                Card(
                                  margin: EdgeInsets.zero,
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            AppSpacing.md,
                                            AppSpacing.sm,
                                            AppSpacing.sm,
                                            AppSpacing.sm),
                                        child: Row(
                                          children: [
                                            Text(
                                              'Robots',
                                              style: theme.textTheme.titleSmall,
                                            ),
                                            const Spacer(),
                                            TextButton.icon(
                                              onPressed:
                                                  (_scanning || _isLoading)
                                                      ? null
                                                      : _scanNearby,
                                              icon: _scanning
                                                  ? SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color:
                                                            colorScheme.primary,
                                                      ),
                                                    )
                                                  : Icon(Icons.radar, size: 16),
                                              label: Text(_scanning
                                                  ? 'Scanning…'
                                                  : 'Scan'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (list.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              AppSpacing.lg,
                                              AppSpacing.sm,
                                              AppSpacing.lg,
                                              AppSpacing.xl),
                                          child: Text(
                                            _scanning
                                                ? 'Looking for robots on the LAN…'
                                                : 'No robots found — scan or enter an IP',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant),
                                          ),
                                        )
                                      else
                                        ...list.map((r) {
                                          final selected = _selectedIp == r.ip;
                                          return InkWell(
                                            onTap: _isLoading
                                                ? null
                                                : () => _select(r.ip, r.port),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: AppSpacing.md,
                                                vertical: AppSpacing.md,
                                              ),
                                              decoration: BoxDecoration(
                                                color: selected
                                                    ? colorScheme.primary
                                                        .withValues(alpha: 0.08)
                                                    : Colors.transparent,
                                                border: Border(
                                                  top: BorderSide(
                                                    color:
                                                        AppColors.lightOutline,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    selected
                                                        ? Icons
                                                            .radio_button_checked
                                                        : Icons
                                                            .radio_button_off,
                                                    color: selected
                                                        ? colorScheme.primary
                                                        : colorScheme
                                                            .onSurfaceVariant,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(
                                                      width: AppSpacing.md),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          r.ip,
                                                          style: theme.textTheme
                                                              .bodyLarge
                                                              ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                        Text(
                                                          ':${r.port} · ${r.source}',
                                                          style: theme.textTheme
                                                              .bodySmall
                                                              ?.copyWith(
                                                            color: colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (r.online ||
                                                      (_claim?['ip'] == r.ip &&
                                                          _claimedOnline))
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal:
                                                            AppSpacing.sm,
                                                        vertical: 3,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors
                                                            .green.shade50,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                AppSpacing
                                                                    .radiusMd),
                                                      ),
                                                      child: Text(
                                                        'online',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .green.shade700,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: AppSpacing.lg),

                                // ONE primary connect
                                SizedBox(
                                  height: 52,
                                  child: FilledButton(
                                    onPressed: (_isLoading ||
                                            (_selectedIp == null ||
                                                _selectedIp!.trim().isEmpty))
                                        ? null
                                        : _connect,
                                    child: Text(
                                      _isLoading
                                          ? 'Connecting…'
                                          : (_selectedIp != null &&
                                                  _selectedIp!.isNotEmpty
                                              ? 'Connect to $_selectedIp'
                                              : 'Select a robot'),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: AppSpacing.sm),

                                // Secondary actions — no extra Connect
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    TextButton.icon(
                                      onPressed: _selectedIp == null
                                          ? null
                                          : _copyLink,
                                      icon: const Icon(Icons.copy, size: 16),
                                      label: const Text('Copy link'),
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (_claim != null) ...[
                                      Text('·',
                                          style: TextStyle(
                                              color:
                                                  colorScheme.outlineVariant)),
                                      TextButton(
                                        onPressed: _releaseClaim,
                                        child: Text(
                                          'Release claim',
                                          style: TextStyle(
                                              color: Colors.red.shade400),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),

                                const SizedBox(height: AppSpacing.xs),
                                TextButton(
                                  onPressed: () => setState(
                                      () => _showManualIp = !_showManualIp),
                                  child: Text(
                                    _showManualIp
                                        ? 'Hide manual IP'
                                        : 'Enter IP manually',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),

                                if (_showManualIp) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  TextField(
                                    controller: ipController,
                                    focusNode: _ipFocus,
                                    keyboardType: TextInputType.url,
                                    textInputAction: TextInputAction.go,
                                    onChanged: (v) {
                                      final t = v.trim();
                                      if (t.isNotEmpty) {
                                        setState(() {
                                          _selectedIp = t;
                                          _selectedPort = _defaultPort;
                                        });
                                      }
                                    },
                                    onSubmitted: (_) => _connect(),
                                    decoration: const InputDecoration(
                                      labelText: 'IP address',
                                      hintText: '192.168.0.129',
                                      prefixIcon: Icon(Icons.router),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _RobotEntry {
  final String ip;
  final String port;
  final String label;
  final String source;
  final bool online;

  _RobotEntry({
    required this.ip,
    required this.port,
    required this.label,
    required this.source,
    this.online = false,
  });
}
