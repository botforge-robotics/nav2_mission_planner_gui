import 'package:flutter/material.dart';

class NavToolbar extends StatefulWidget {
  final Color modeColor;
  final Function(String) onToolSelected;
  final bool disableToolBar;
  const NavToolbar({
    super.key,
    required this.modeColor,
    required this.onToolSelected,
    this.disableToolBar = false,
  });

  @override
  State<NavToolbar> createState() => _NavToolbarState();
}

class _NavToolbarState extends State<NavToolbar> {
  String selectedTool = '';
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToolButton(
            context: context,
            icon: Icons.navigation,
            label: 'Pose Estimate',
            tool: 'localization',
            isActive: selectedTool == 'localization',
          ),
          _buildDivider(),
          _buildToolButton(
            context: context,
            icon: Icons.bookmark,
            label: 'Bookmarks',
            tool: 'bookmarks',
            isActive: selectedTool == 'bookmarks',
          ),
          _buildDivider(),
          _buildToolButton(
            context: context,
            icon: Icons.pin_drop,
            label: 'Send Goal',
            tool: 'goal',
            isActive: selectedTool == 'goal',
          ),
          _buildDivider(),
          _buildToolButton(
            context: context,
            icon: Icons.timeline,
            label: 'Mission',
            tool: 'mission',
            isActive: selectedTool == 'mission',
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String tool,
    required bool isActive,
  }) {
    return Tooltip(
      message: label,
      preferBelow: false,
      verticalOffset: 20,
      child: Opacity(
        opacity: widget.disableToolBar
            ? 0.5
            : 1.0, // Adjust opacity for disabled state
        child: InkWell(
          onTap: () {
            if (widget.disableToolBar) return;
            setState(() {
              selectedTool = selectedTool == tool ? '' : tool;
            });
            widget.onToolSelected(selectedTool);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 80,
            height: 60,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? widget.modeColor.withOpacity(0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive ? widget.modeColor : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: widget.modeColor.withOpacity(0.3),
                        blurRadius: 5,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isActive ? widget.modeColor : Colors.white70,
                  size: 25,
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 24,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isActive ? widget.modeColor : Colors.white70,
                        fontSize: 9,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        height: 1,
        width: 30,
        color: Colors.grey.withOpacity(0.3),
      ),
    );
  }
}
