import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/branding_provider.dart';

/// Widget that shows a guide icon with optional first-time highlight
class GuideHighlightWidget extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String guideUrl;
  final bool showHighlight;
  final String? highlightMessage;
  final IconData? icon;
  final Color? iconColor;
  final double size;
  final EdgeInsets padding;

  const GuideHighlightWidget({
    super.key,
    required this.onTap,
    this.onLongPress,
    required this.guideUrl,
    this.showHighlight = false,
    this.highlightMessage,
    this.icon,
    this.iconColor,
    this.size = 24.0,
    this.padding = const EdgeInsets.all(8.0),
  });

  @override
  State<GuideHighlightWidget> createState() => _GuideHighlightWidgetState();
}

class _GuideHighlightWidgetState extends State<GuideHighlightWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;
  bool _isHighlightVisible = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _glowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    if (widget.showHighlight) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _animationController.repeat(reverse: true);
  }

  void _stopAnimation() {
    _animationController.stop();
    _animationController.reset();
  }

  void _dismissHighlight() {
    setState(() {
      _isHighlightVisible = false;
    });
    _stopAnimation();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brandingProvider =
        Provider.of<BrandingProvider>(context, listen: false);
    final themeColor = brandingProvider.themeColor;

    return Stack(
      children: [
        // Guide Icon
        Container(
          padding: widget.padding,
          child: GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(widget.size / 2),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                widget.icon ?? FontAwesomeIcons.circleQuestion,
                size: widget.size * 0.6,
                color: Colors.white, // Manual icon is now white
              ),
            ),
          ),
        ),

        // First-time Highlight (only shown once)
        if (widget.showHighlight && _isHighlightVisible)
          Positioned(
            right: -20,
            top: -20,
            child: _buildHighlight(themeColor),
          ),
      ],
    );
  }

  Widget _buildHighlight(Color themeColor) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            width: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: themeColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color:
                      themeColor.withValues(alpha: 0.3 * _glowAnimation.value),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'New User Guide',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _dismissHighlight,
                      child: Icon(
                        Icons.close,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.highlightMessage ??
                      'Click here for setup instructions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
