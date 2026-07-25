import 'package:flutter/material.dart';

class VelocityControl extends StatelessWidget {
  final double value;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<double?> onChanged;
  final Size screenSize;
  final Color modeColor;

  const VelocityControl({
    super.key,
    required this.value,
    required this.onIncrement,
    required this.onDecrement,
    required this.onChanged,
    required this.screenSize,
    required this.modeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ElevatedButton(
          onPressed: onDecrement,
          style: ElevatedButton.styleFrom(
            backgroundColor: modeColor.withOpacity(0.2),
            foregroundColor: modeColor,
            shape: const CircleBorder(),
            padding: EdgeInsets.all(screenSize.height * 0.008),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            elevation: 0,
          ),
          child: Icon(
            Icons.remove,
            color: modeColor,
            size: 22,
          ),
        ),
        SizedBox(width: screenSize.width * 0.01),
        SizedBox(
          width: screenSize.width * 0.1,
          child: TextFormField(
            textAlign: TextAlign.center,
            controller: TextEditingController(
              text: value.toStringAsFixed(2),
            ),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey.shade800,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.transparent),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.transparent),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: modeColor),
              ),
              contentPadding: EdgeInsets.symmetric(
                vertical: screenSize.height * 0.015,
              ),
            ),
            onChanged: (value) {
              final parsed = double.tryParse(value);
              if (parsed != null) onChanged(parsed);
            },
          ),
        ),
        SizedBox(width: screenSize.width * 0.01),
        ElevatedButton(
          onPressed: onIncrement,
          style: ElevatedButton.styleFrom(
            backgroundColor: modeColor.withOpacity(0.2),
            foregroundColor: modeColor,
            shape: const CircleBorder(),
            padding: EdgeInsets.all(screenSize.height * 0.008),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            elevation: 0,
          ),
          child: Icon(
            Icons.add,
            color: modeColor,
            size: 22,
          ),
        ),
      ],
    );
  }
}
