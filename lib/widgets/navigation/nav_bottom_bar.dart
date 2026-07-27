import 'package:flutter/material.dart';

// ... existing code ... (if any, but this file is empty)

// New widget for the bottom bar
class NavBottomBar extends StatefulWidget {
  final VoidCallback onSlideRight; // Callback to trigger when slid to the right
  final VoidCallback? onCancel; // Optional cancel (clears pending goal)
  final String promptText; // Text to display, e.g., "Slide to send goal"
  final bool visible; // Add visibility control
  final Color color; // Add color control

  const NavBottomBar({
    super.key,
    required this.onSlideRight,
    this.onCancel,
    this.promptText = 'Slide to send goal',
    this.visible = true, // Default to visible
    this.color = Colors.blue, // Default color
  });

  @override
  State<NavBottomBar> createState() => _NavBottomBarState();
}

class _NavBottomBarState extends State<NavBottomBar>
    with SingleTickerProviderStateMixin {
  double _dragProgress = 0.0; // 0.0 to 1.0
  final double _slideThreshold = 0.8; // 80% needed to trigger action
  late AnimationController _returnController;

  @override
  void initState() {
    super.initState();
    _returnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        setState(() {
          _dragProgress = _returnController.value * _dragProgress;
        });
      });
  }

  @override
  void dispose() {
    _returnController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) {
      return const SizedBox.shrink(); // Hide when not visible
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final barWidth = 350.0; // 50% of screen width

    return Positioned(
      bottom: 20,
      left: (screenWidth - barWidth) / 2,
      width: barWidth,
      child: Row(
        children: [
          if (widget.onCancel != null) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onCancel,
                borderRadius: BorderRadius.circular(25),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.redAccent.withOpacity(0.7)),
                  ),
                  child: const Icon(Icons.close, color: Colors.redAccent, size: 22),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;
                  return Stack(
                    children: [
                      Center(
                        child: Text(
                          widget.promptText,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            final maxDrag = trackWidth - 42 - 8;
                            final delta = details.delta.dx / maxDrag;
                            _dragProgress =
                                (_dragProgress + delta).clamp(0.0, 1.0);
                          });
                        },
                        onHorizontalDragEnd: (_) {
                          if (_dragProgress >= _slideThreshold) {
                            widget.onSlideRight();
                          }
                          _returnController.forward(from: 0.0);
                        },
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Transform.translate(
                            offset: Offset(
                              (_dragProgress * (trackWidth - 42 - 8))
                                  .clamp(0.0, trackWidth - 42 - 8),
                              0,
                            ),
                            child: Container(
                              width: 42,
                              height: 42,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: widget.color,
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                                size: 20 + (_dragProgress * 4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}