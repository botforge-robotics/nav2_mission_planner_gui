import 'package:flutter/material.dart';

class AppTheme {
  // Colors
  static const primaryColor = Color(0xFF121212); // Very dark gray
  static const secondaryColor = Color(0xFF2A2A2A); // Dark gray
  static const accentColor = Color(0xFF404040); // Medium gray
  static const backgroundColor = Color(0xFF0A0A0A); // Almost black gray
  static const toolbarColor =
      Color.fromARGB(255, 22, 22, 22); // Dark blue-gray color

  // Sizes
  static const double toolbarWidth = 60.0;
  static const double statusBarHeight = 50.0;
  static const double controlPanelWidth = 300.0;

  // Text Styles
  static const TextStyle statusTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle titleTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );

  // Theme Data
  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: backgroundColor,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: toolbarColor,
        elevation: 0,
      ),
    );
  }
}
