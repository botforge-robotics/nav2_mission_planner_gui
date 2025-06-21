import 'package:flutter/material.dart';

class HeaderToggle extends StatelessWidget {
  final bool isCollapsed;
  final Color modeColor;
  final VoidCallback onToggle;

  const HeaderToggle({
    Key? key,
    required this.isCollapsed,
    required this.modeColor,
    required this.onToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              modeColor.withOpacity(0.1),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border(
            top: BorderSide(
              color: Colors.grey[700]!,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.route,
              color: modeColor,
              size: 24,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Mission Planner',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            AnimatedRotation(
              turns: isCollapsed ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Icon(
                Icons.keyboard_arrow_up,
                color: modeColor,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
