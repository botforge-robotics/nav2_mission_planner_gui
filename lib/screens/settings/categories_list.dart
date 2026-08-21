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

  Color _getModeColor(BuildContext context, String category) {
    switch (category) {
      case 'Teleop':
        return ModeColors.getModeColorMap(context)[AppModes.teleop]!;
      case 'Robot':
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
        // Hide Robot settings for now (keep code in settings_content.dart)
        // _buildCategoryTile(
        //   context,
        //   icon: FontAwesomeIcons.robot,
        //   title: 'Robot',
        // ),
        _buildCategoryTile(
          context,
          icon: FontAwesomeIcons.gamepad,
          title: 'Teleop',
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
    required FaIconData icon,
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
      child: InkWell(
        onTap: () => onCategorySelected(title),
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 55,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          child: Row(
            children: [
              FaIcon(
                icon,
                size: 14,
                color: isSelected ? modeColor : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: isSelected ? modeColor : Colors.grey,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
