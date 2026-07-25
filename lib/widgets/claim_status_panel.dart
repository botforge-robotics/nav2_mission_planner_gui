import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/branding_provider.dart';
import '../services/pc_api_service.dart';
import '../theme/app_theme.dart';

/// Claim / release / copy rosbridge link — used on connection + home.
class ClaimStatusPanel extends StatefulWidget {
  final bool compact;
  final VoidCallback? onConnectRequested;

  const ClaimStatusPanel({
    super.key,
    this.compact = false,
    this.onConnectRequested,
  });

  @override
  State<ClaimStatusPanel> createState() => _ClaimStatusPanelState();
}

class _ClaimStatusPanelState extends State<ClaimStatusPanel> {
  Map<String, dynamic>? _claim;
  bool _online = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final hb = await PcApiService.heartbeat();
    if (!mounted) return;
    setState(() {
      _online = hb != null && hb['online'] == true;
      _claim = hb != null && hb['claimed'] == true
          ? Map<String, dynamic>.from(hb['robot'] as Map? ?? {})
          : null;
      if (_claim == null) {
        // fall back to GET /api/claim
      }
    });
    if (_claim == null) {
      final c = await PcApiService.getClaim();
      if (!mounted) return;
      setState(() => _claim = c);
    }
  }

  String get _wsLink {
    final ip = _claim?['ip']?.toString() ?? '';
    final port = _claim?['port']?.toString() ?? '9090';
    if (ip.isEmpty) return '';
    return 'ws://$ip:$port';
  }

  Future<void> _copyLink() async {
    final link = _wsLink;
    if (link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $link'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _release() async {
    setState(() => _busy = true);
    await PcApiService.releaseClaim();
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final brand = Provider.of<BrandingProvider>(context, listen: false).themeColor;
    final conn = Provider.of<ConnectionProvider>(context);
    final claimed = _claim != null;
    final ip = _claim?['ip']?.toString() ?? conn.ip;
    final name = _claim?['name']?.toString() ?? 'NavProMini';

    return Container(
      width: widget.compact ? null : double.infinity,
      padding: EdgeInsets.all(widget.compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: claimed
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      _online ? Icons.wifi : Icons.wifi_off,
                      color: _online ? Colors.greenAccent : Colors.redAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$name · $ip',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _online ? 'online' : 'offline',
                      style: TextStyle(
                        color: _online ? Colors.greenAccent : Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SelectableText(
                  _wsLink,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _copyLink,
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy link'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: brand,
                        side: BorderSide(color: brand.withValues(alpha: 0.6)),
                      ),
                    ),
                    if (!conn.isConnected && ip.isNotEmpty)
                      ElevatedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => widget.onConnectRequested?.call(),
                        icon: const Icon(Icons.link, size: 16),
                        label: const Text('Connect'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brand,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    TextButton(
                      onPressed: _busy ? null : _release,
                      child: Text(
                        'Release claim',
                        style: TextStyle(color: Colors.red.shade300),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _busy ? null : _refresh,
                      icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Icon(Icons.sensors_off, color: Colors.white54, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'No robot claimed yet — scan or enter IP to connect',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                ),
              ],
            ),
    );
  }
}

/// Full-screen claim dialog shown once on home after connect.
Future<void> showClaimPopup(BuildContext context, {VoidCallback? onConnect}) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.secondaryColor,
      title: const Text('Robot claim', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 420,
        child: ClaimStatusPanel(
          onConnectRequested: () {
            Navigator.pop(ctx);
            onConnect?.call();
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
