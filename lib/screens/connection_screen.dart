import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/branding_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/top_status_bar/top_status_bar.dart';
import '../widgets/background_feature_cards.dart';
import '../constants/modes.dart';
import '../theme/app_theme.dart';
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
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Provider.of<BrandingProvider>(context, listen: false)
                    .themeColor,
              ),
              const SizedBox(height: 16),
              Text(
                'Connecting to $ip…',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
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
    final brand =
        Provider.of<BrandingProvider>(context, listen: false).themeColor;
    final list = _robots.values.toList()
      ..sort((a, b) {
        // claimed / online first
        if (a.source == 'claimed' && b.source != 'claimed') return -1;
        if (b.source == 'claimed' && a.source != 'claimed') return 1;
        return a.ip.compareTo(b.ip);
      });

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Stack(
        children: [
          const BackgroundFeatureCards(
            cardCount: 12,
            opacity: 0.25,
            maxRotation: 30.0,
          ),
          Column(
            children: [
              if (widget.showTopStatusBar)
                TopStatusBar(
                  currentMode: AppModes.mapping,
                  onModeChanged: (_) {},
                  statusText: 'Connect to Robot',
                  statusColor: Colors.red,
                  height: AppTheme.statusBarHeight,
                  icon: FontAwesomeIcons.robot,
                ),
              Expanded(
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Connect to Robot',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Choose a robot, then connect (port $_defaultPort)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.65),
                              ),
                            ),
                            const SizedBox(height: 22),

                            // Robot list (single select)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        14, 12, 8, 8),
                                    child: Row(
                                      children: [
                                        const Text(
                                          'Robots',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
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
                                                    color: brand,
                                                  ),
                                                )
                                              : Icon(Icons.radar,
                                                  size: 16, color: brand),
                                          label: Text(
                                            _scanning ? 'Scanning…' : 'Scan',
                                            style: TextStyle(color: brand),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (list.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 8, 16, 20),
                                      child: Text(
                                        _scanning
                                            ? 'Looking for robots on the LAN…'
                                            : 'No robots found — scan or enter an IP',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.5),
                                          fontSize: 13,
                                        ),
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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? brand.withValues(alpha: 0.15)
                                                : Colors.transparent,
                                            border: Border(
                                              top: BorderSide(
                                                color: Colors.white
                                                    .withValues(alpha: 0.06),
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                selected
                                                    ? Icons.radio_button_checked
                                                    : Icons
                                                        .radio_button_off,
                                                color: selected
                                                    ? brand
                                                    : Colors.white38,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      r.ip,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    Text(
                                                      ':${r.port} · ${r.source}',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withValues(
                                                                alpha: 0.45),
                                                        fontSize: 12,
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
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green
                                                        .withValues(
                                                            alpha: 0.2),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  child: const Text(
                                                    'online',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.greenAccent,
                                                      fontSize: 11,
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

                            const SizedBox(height: 16),

                            // ONE primary connect
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: (_isLoading ||
                                        (_selectedIp == null ||
                                            _selectedIp!.trim().isEmpty))
                                    ? null
                                    : _connect,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: brand,
                                  foregroundColor: Colors.black,
                                  disabledBackgroundColor:
                                      brand.withValues(alpha: 0.35),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
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

                            const SizedBox(height: 10),

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
                                    foregroundColor: Colors.white70,
                                  ),
                                ),
                                if (_claim != null) ...[
                                  const Text('·',
                                      style: TextStyle(color: Colors.white24)),
                                  TextButton(
                                    onPressed: _releaseClaim,
                                    child: Text(
                                      'Release claim',
                                      style: TextStyle(
                                          color: Colors.red.shade300),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => setState(
                                  () => _showManualIp = !_showManualIp),
                              child: Text(
                                _showManualIp
                                    ? 'Hide manual IP'
                                    : 'Enter IP manually',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 13,
                                ),
                              ),
                            ),

                            if (_showManualIp) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: ipController,
                                focusNode: _ipFocus,
                                style: const TextStyle(color: Colors.white),
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
                                decoration: InputDecoration(
                                  labelText: 'IP address',
                                  hintText: '192.168.0.129',
                                  labelStyle:
                                      TextStyle(color: Colors.grey.shade400),
                                  filled: true,
                                  fillColor:
                                      Colors.white.withValues(alpha: 0.06),
                                  prefixIcon: const Icon(Icons.router,
                                      color: Colors.white54),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color:
                                          Colors.white.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: brand),
                                  ),
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
