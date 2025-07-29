import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../constants/modes.dart';

class CategoriesList extends StatelessWidget {
  final String selectedCategory;
  final Function(String) onCategorySelected;
  final Size screenSize;

  const CategoriesList({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.screenSize,
  });

  // Helper method to get color from mode
  Color _getModeColor(BuildContext context, String category) {
    switch (category) {
      case 'General':
        return ModeColors.getModeColorMap(context)[AppModes.settings]!;
      case 'Teleop':
        return ModeColors.getModeColorMap(context)[AppModes.teleop]!;
      case 'Mapping':
        return ModeColors.getModeColorMap(context)[AppModes.mapping]!;
      case 'Navigation':
        return ModeColors.getModeColorMap(context)[AppModes.navigation]!;
      case 'About':
        return ModeColors.getModeColorMap(context)[AppModes.settings]!;

      default:
        return ModeColors.getModeColorMap(context)[AppModes.settings]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildCategoryTile(
          context,
          icon: FontAwesomeIcons.gear,
          title: 'General',
        ),
        _buildCategoryTile(
          context,
          icon: FontAwesomeIcons.gamepad,
          title: 'Teleop',
        ),
        _buildCategoryTile(
          context,
          icon: FontAwesomeIcons.map,
          title: 'Mapping',
        ),
        _buildCategoryTile(
          context,
          icon: FontAwesomeIcons.mapLocationDot,
          title: 'Navigation',
        ),
        _buildCategoryTile(
          context,
          icon: FontAwesomeIcons.circleInfo,
          title: 'About',
        ),
      ],
    );
  }

  Widget _buildCategoryTile(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) {
    final isSelected = selectedCategory == title;
    final modeColor = _getModeColor(context, title);

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: screenSize.width * 0.01,
        vertical: screenSize.height * 0.01,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isSelected ? modeColor.withOpacity(0.2) : Colors.transparent,
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: screenSize.width * 0.015,
          vertical: screenSize.height * 0.005,
        ),
        minLeadingWidth: 5,
        leading: Icon(
          icon,
          size: 14,
          color: isSelected ? modeColor : Colors.grey,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: isSelected ? modeColor : Colors.grey,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: () => onCategorySelected(title),
        selected: isSelected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
