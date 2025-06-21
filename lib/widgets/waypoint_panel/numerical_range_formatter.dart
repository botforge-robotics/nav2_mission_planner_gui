import 'package:flutter/services.dart';

/// Restricts a numeric text field to a range (inclusive).
class NumericalRangeFormatter extends TextInputFormatter {
  final int min;
  final int max;

  NumericalRangeFormatter({required this.min, required this.max});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final value = int.tryParse(newValue.text);
    if (value == null) return oldValue;

    if (value < min) return TextEditingValue(text: min.toString());
    if (value > max) return TextEditingValue(text: max.toString());

    return newValue;
  }
}
