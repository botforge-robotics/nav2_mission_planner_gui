import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'categories_list.dart';
import 'settings_content.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedCategory = 'General';

  void _setSelectedCategory(String category) {
    setState(() {
      _selectedCategory = category;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final sidebarWidth = screenSize.width * 0.18;

    return Scaffold(
      body: Row(
        children: [
          // Left sidebar with categories
          SizedBox(
            width: sidebarWidth,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.toolbarColor,
                border: Border(
                  right: BorderSide(
                    color: Colors.grey.shade800,
                    width: 1,
                  ),
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
              padding: EdgeInsets.symmetric(
                horizontal: screenSize.width * 0.02,
                vertical: 0,
              ),
              child: SettingsContent(
                category: _selectedCategory,
                screenSize: screenSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
