import 'package:flutter/material.dart';

class MapsPathInput extends StatelessWidget {
  final String initialValue;
  final Function(String) onChanged;
  final Size screenSize;
  final Color modeColor;

  const MapsPathInput({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.screenSize,
    required this.modeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Format: \${package_name}/\${folder_name}',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: screenSize.height * 0.02),
        TextFormField(
          initialValue: initialValue,
          style: TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: 'slam_toolbox/maps',
            hintStyle: TextStyle(color: Colors.grey.shade700),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: modeColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: modeColor, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(
              vertical: screenSize.height * 0.015,
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
