import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import '../../constants/modes.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/launch_service.dart';
import 'package:provider/provider.dart';

class TopStatusModeSelector extends StatelessWidget {
  final double height;
  final Color connectionStatusColor;
  final String displayStatusText;
  final AppModes currentMode;
  final Function(AppModes) onModeChanged;

  const TopStatusModeSelector({
    super.key,
    required this.height,
    required this.connectionStatusColor,
    required this.displayStatusText,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        onTap: () {
          final connection =
              Provider.of<ConnectionProvider>(context, listen: false);
          if (connection.isConnected) {
            _showModeDropdown(context);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                connectionStatusColor,
                connectionStatusColor.withValues(alpha: 0.8),
                connectionStatusColor.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.7, 1.0],
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getModeIcon(currentMode),
                color: _getTextColor(connectionStatusColor),
                size: height * 0.4,
              ),
              const SizedBox(width: 8),
              Text(
                displayStatusText,
                style: TextStyle(
                  color: _getTextColor(connectionStatusColor),
                  fontSize: height * 0.32,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              if (Provider.of<ConnectionProvider>(context).isConnected)
                Icon(
                  Icons.arrow_drop_down,
                  color: _getTextColor(connectionStatusColor),
                  size: height * 0.4,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showModeDropdown(BuildContext context) {
    final RenderBox statusBar = context.findRenderObject() as RenderBox;
    final Offset position = statusBar.localToGlobal(Offset.zero);

    showMenu<AppModes>(
      context: context,
      position: RelativeRect.fromLTRB(
        0,
        position.dy + height + 4,
        0,
        0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      color: Colors.black87,
      elevation: 8,
      constraints: const BoxConstraints(
        minWidth: 200,
        maxWidth: 280,
      ),
      items: [
        _buildDropdownItem(context, AppModes.teleop, FontAwesomeIcons.gamepad),
        _buildDropdownItem(context, AppModes.mapping, FontAwesomeIcons.map),
        _buildDropdownItem(
            context, AppModes.navigation, FontAwesomeIcons.route),
        _buildDropdownItem(context, AppModes.settings, FontAwesomeIcons.gear),
      ],
    ).then((selectedMode) async {
      if (selectedMode != null) {
        final launchManager =
            Provider.of<LaunchManager>(context, listen: false);
        final activeSession = launchManager.activeSession;

        if (activeSession == SessionType.mapping &&
            selectedMode != AppModes.mapping &&
            selectedMode != AppModes.settings) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot switch modes while mapping is active'),
              backgroundColor: Colors.red.withOpacity(0.9),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        if (activeSession == SessionType.navigation &&
            selectedMode != AppModes.navigation &&
            selectedMode != AppModes.settings) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cannot switch modes while navigation is active'),
              backgroundColor: Colors.red.withOpacity(0.9),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        onModeChanged(selectedMode);
      }
    });
  }

  PopupMenuEntry<AppModes> _buildDropdownItem(
      BuildContext context, AppModes mode, IconData icon) {
    final activeSession =
        Provider.of<LaunchManager>(context, listen: false).activeSession;

    final bool isDisabled =
        // Disable when mapping is active
        (activeSession == SessionType.mapping &&
                mode != AppModes.mapping &&
                mode != AppModes.settings) ||
            // Disable when navigation is active
            (activeSession == SessionType.navigation &&
                mode != AppModes.navigation &&
                mode != AppModes.settings);

    return PopupMenuItem<AppModes>(
      value: isDisabled ? null : mode,
      height: 45,
      onTap: isDisabled ? null : () {},
      child: Container(
        decoration: BoxDecoration(
          color: mode == currentMode
              ? ModeColors.getModeColorMap(context)[mode]!
                  .withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: isDisabled
                    ? Colors.grey
                    : ModeColors.getModeColorMap(context)[mode]!),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                mode.toString().split('.').last,
                style: TextStyle(
                  color: isDisabled ? Colors.grey : Colors.white,
                  fontSize: 14,
                  fontWeight:
                      mode == currentMode ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (mode == currentMode && !isDisabled) ...[
              const SizedBox(width: 8),
              Icon(Icons.check,
                  size: 18, color: ModeColors.getModeColorMap(context)[mode]!),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getModeIcon(AppModes mode) {
    switch (mode) {
      case AppModes.teleop:
        return FontAwesomeIcons.gamepad;
      case AppModes.mapping:
        return FontAwesomeIcons.map;
      case AppModes.navigation:
        return FontAwesomeIcons.route;
      case AppModes.settings:
        return FontAwesomeIcons.gear;
    }
  }

  Color _getTextColor(Color backgroundColor) {
    double luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}
