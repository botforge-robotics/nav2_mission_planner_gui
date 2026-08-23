import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';

class VisibilityToolbar extends StatelessWidget {
  final Color modeColor;
  // RViz-style overlay toggles — live view state only (not persisted, same
  // as RViz's own Display checkboxes), so these are plain callbacks/values
  // from the parent screen rather than routed through SettingsProvider.
  final bool? showLocalCostmap;
  final ValueChanged<bool>? onLocalCostmapToggle;
  final bool? showGlobalCostmap;
  final ValueChanged<bool>? onGlobalCostmapToggle;

  const VisibilityToolbar({
    super.key,
    required this.modeColor,
    this.showLocalCostmap,
    this.onLocalCostmapToggle,
    this.showGlobalCostmap,
    this.onGlobalCostmapToggle,
  });

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomLeft: Radius.circular(12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Camera / image toggle — hidden for now (keep code)
          // _buildVisibilityToggle(
          //   icon: Icons.camera_alt,
          //   isVisible: settingsProvider.cameraVisible,
          //   onToggle: () => settingsProvider.toggleCameraVisibility(),
          // ),
          _buildVisibilityToggle(
            icon: Icons.gamepad,
            isVisible: settingsProvider.joystickVisible,
            onToggle: () => settingsProvider.toggleJoystickVisibility(),
          ),
          _buildVisibilityToggle(
            icon: Icons.bookmark,
            isVisible: settingsProvider.bookmarksVisible,
            onToggle: () => settingsProvider.toggleBookmarksVisibility(),
          ),
          _buildVisibilityToggle(
            icon: Icons.speed,
            isVisible: settingsProvider.telemetryVisible,
            onToggle: () => settingsProvider.toggleTelemetryVisibility(),
          ),
          if (onLocalCostmapToggle != null)
            _buildVisibilityToggle(
              icon: Icons.layers,
              isVisible: showLocalCostmap ?? false,
              onToggle: () =>
                  onLocalCostmapToggle!(!(showLocalCostmap ?? false)),
            ),
          if (onGlobalCostmapToggle != null)
            _buildVisibilityToggle(
              icon: Icons.public,
              isVisible: showGlobalCostmap ?? false,
              onToggle: () =>
                  onGlobalCostmapToggle!(!(showGlobalCostmap ?? false)),
            ),
        ],
      ),
    );
  }

  Widget _buildVisibilityToggle({
    required IconData icon,
    required bool isVisible,
    required VoidCallback onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isVisible ? modeColor : Colors.grey.shade700,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
