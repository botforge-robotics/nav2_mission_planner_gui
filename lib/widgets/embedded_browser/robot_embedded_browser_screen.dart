import 'package:flutter/material.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import 'browser_frame.dart';

/// Embedded full-screen browser view displayed on the robot UI.
///
/// Features requested:
/// 1. Embedded browser inside robot UI.
/// 2. Does NOT show the URL bar.
/// 3. Browser content is shown directly below the AppBar.
/// 4. A prominent Close button is pinned to the bottom-left.
/// 5. Closes the browser view and sends 'closed' action to the SDK
///    to trigger the mission transition to the next step.
class RobotEmbeddedBrowserScreen extends StatefulWidget {
  const RobotEmbeddedBrowserScreen({
    super.key,
    required this.api,
    required this.interactionId,
    required this.url,
    this.title = 'Web Browser',
    this.onDismissed,
  });

  final SdkApiService api;
  final String interactionId;
  final String url;
  final String title;
  final VoidCallback? onDismissed;

  /// Convenience helper to push this screen.
  static Future<void> show(
    BuildContext context, {
    required SdkApiService api,
    required String interactionId,
    required String url,
    String title = 'Web Browser',
    VoidCallback? onDismissed,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RobotEmbeddedBrowserScreen(
          api: api,
          interactionId: interactionId,
          url: url,
          title: title,
          onDismissed: onDismissed,
        ),
      ),
    );
  }

  @override
  State<RobotEmbeddedBrowserScreen> createState() => _RobotEmbeddedBrowserScreenState();
}

class _RobotEmbeddedBrowserScreenState extends State<RobotEmbeddedBrowserScreen> {
  bool _isClosing = false;
  late String _currentUrl;
  int _reloadKey = 0;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url.trim();
  }

  Future<void> _handleClose() async {
    if (_isClosing) return;
    setState(() => _isClosing = true);

    try {
      if (widget.interactionId.isNotEmpty) {
        await widget.api.submitUiResponse(
          widget.interactionId,
          action: 'closed',
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        widget.onDismissed?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error closing browser session: $e')),
        );
        setState(() => _isClosing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.title.isNotEmpty ? widget.title : 'Web Browser'),
        centerTitle: false,
        automaticallyImplyLeading: false, // User advances ONLY via the bottom-left Close button
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
            onPressed: () {
              setState(() {
                _reloadKey++;
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Browser content displayed directly below the AppBar (No URL bar)
          Positioned.fill(
            key: ValueKey('browser_content_${widget.url}_$_reloadKey'),
            child: buildBrowserFrame(_currentUrl),
          ),

          // Pinned Close button at the bottom-left
          Positioned(
            left: 20,
            bottom: 20,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isClosing ? null : _handleClose,
                borderRadius: BorderRadius.circular(32),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626), // High-visibility red close button
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isClosing)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      const SizedBox(width: 10),
                      const Text(
                        'Close & Continue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
