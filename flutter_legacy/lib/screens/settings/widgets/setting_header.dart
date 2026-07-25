import 'package:flutter/material.dart';

class SettingHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Size screenSize;
  final Color modeColor;

  const SettingHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.screenSize,
    required this.modeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: modeColor,
            ),
            SizedBox(width: screenSize.width * 0.01),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: modeColor,
              ),
            ),
          ],
        ),
        Container(
          margin: EdgeInsets.symmetric(vertical: screenSize.height * 0.02),
          height: 1,
          color: Colors.grey.shade800,
        ),
      ],
    );
  }
}
