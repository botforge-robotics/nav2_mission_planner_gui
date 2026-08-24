import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_breakpoints.dart';
import 'categories_list.dart';
import 'settings_content.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedCategory = 'Teleop';

  void _setSelectedCategory(String category) {
    setState(() {
      _selectedCategory = category;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final sizeClass = WindowSizeClass.of(context);
    // A flat percentage gets absurdly narrow on a small window and
    // absurdly wide on a large one — clamp to a sane range per breakpoint
    // instead, following the responsive-breakpoint contract the rest of
    // the redesign uses.
    final sidebarWidth = sizeClass.isCompact
        ? 180.0
        : (screenSize.width * 0.18).clamp(220.0, 300.0);

    // Locally opted into the redesigned light theme, same as
    // ConnectionScreen — main.dart's global theme flips only once enough
    // screens are migrated.
    return Theme(
      data: AppTheme.lightTheme,
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        return Scaffold(
          backgroundColor: AppColors.lightBackground,
          body: Row(
            children: [
              // Left sidebar with categories
              SizedBox(
                width: sidebarWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.lightSurface,
                    border: Border(
                      right:
                          BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: CategoriesList(
                          selectedCategory: _selectedCategory,
                          onCategorySelected: _setSelectedCategory,
                          screenSize: screenSize,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Main content area
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SettingsContent(
                    category: _selectedCategory,
                    screenSize: screenSize,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
