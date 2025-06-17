import 'package:flutter/material.dart';

class LaunchFileInput extends StatelessWidget {
  final String initialValue;
  final Function(String) onChanged;
  final Size screenSize;
  final Color modeColor;
  final String hintText;

  const LaunchFileInput({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.screenSize,
    required this.modeColor,
    this.hintText = 'package_name/launch_file',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Format: \${package_name}/\${launchfile_name} (*dont include ".launch.py")',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        TextFormField(
          initialValue: initialValue,
          style: TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: hintText,
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
            isDense: true,
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
