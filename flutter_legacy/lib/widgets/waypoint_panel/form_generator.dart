import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/services/message_parser.dart';
import 'package:flutter/services.dart';

class FormGenerator {
  static Widget generateFormField(
    String fieldName,
    Map<String, dynamic> fieldDefinition,
    dynamic currentValue,
    Function(dynamic) onChanged,
    Color modeColor, {
    bool forceRefresh = false,
  }) {
    if (forceRefresh) {
      // Refreshing form field for $fieldName
    }

    // Handle null values
    final type = (fieldDefinition['type'] ?? 'string').toString();

    switch (type) {
      case 'array':
        return _buildArrayField(
            fieldName, fieldDefinition, currentValue, onChanged, modeColor);
      case 'nested':
        return _buildNestedField(
            fieldName, fieldDefinition, currentValue, onChanged, modeColor);
      default:
        // Handle primitive types
        return _buildPrimitiveField(
            fieldName, fieldDefinition, currentValue, onChanged, modeColor);
    }
  }

  static Widget _buildPrimitiveField(
    String fieldName,
    Map<String, dynamic> fieldDefinition,
    dynamic currentValue,
    Function(dynamic) onChanged,
    Color modeColor,
  ) {
    final widget = (fieldDefinition['widget'] ?? 'text').toString();
    final type = (fieldDefinition['type'] ?? 'string').toString();

    switch (widget) {
      case 'switch':
        return _buildSwitchField(fieldName, fieldDefinition['type'],
            currentValue, onChanged, modeColor);
      case 'number':
        return _buildNumberField(fieldName, fieldDefinition['type'],
            currentValue, onChanged, modeColor,
            isInteger: type.contains('int'));
      case 'decimal':
        return _buildNumberField(fieldName, fieldDefinition['type'],
            currentValue, onChanged, modeColor,
            isInteger: false);
      case 'text':
        return _buildTextField(fieldName, fieldDefinition['type'], currentValue,
            onChanged, modeColor, null);
      case 'time_picker':
        return _buildTimeField(fieldName, fieldDefinition['type'], currentValue,
            onChanged, modeColor, null);
      default:
        return _buildTextField(fieldName, fieldDefinition['type'], currentValue,
            onChanged, modeColor, null);
    }
  }

  static Widget _buildNestedField(
    String fieldName,
    Map<String, dynamic> fieldDefinition,
    dynamic currentValue,
    Function(dynamic) onChanged,
    Color modeColor,
  ) {
    final structure = fieldDefinition['structure'] as Map<String, dynamic>;
    final nestedType = fieldDefinition['nestedType'] as String?;

    // Initialize currentValue as Map if null
    final Map<String, dynamic> nestedValue =
        currentValue as Map<String, dynamic>? ?? {};

    return ExpansionTile(
      title: RichText(
        text: TextSpan(
          text: _formatFieldName(fieldName),
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      subtitle: nestedType != null
          ? Text(
              nestedType,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
              ),
            )
          : null,
      iconColor: modeColor,
      collapsedIconColor: modeColor,
      backgroundColor: Colors.grey[800]?.withValues(alpha: 0.5),
      collapsedBackgroundColor: Colors.grey[800]?.withValues(alpha: 0.3),
      childrenPadding: EdgeInsets.all(16),
      children: structure.entries.map((entry) {
        final subFieldName = entry.key;
        final subFieldDef = entry.value as Map<String, dynamic>;
        final subValue = nestedValue[subFieldName];

        return generateFormField(
          subFieldName,
          subFieldDef,
          subValue,
          (newValue) {
            final updatedNestedValue = Map<String, dynamic>.from(nestedValue);
            updatedNestedValue[subFieldName] = newValue;
            onChanged(updatedNestedValue);
          },
          modeColor,
        );
      }).toList(),
    );
  }

  static Widget _buildSwitchField(
    String fieldName,
    String type,
    dynamic currentValue,
    Function(dynamic) onChanged,
    Color modeColor,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatFieldName(fieldName),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: currentValue ?? false,
            onChanged: onChanged,
            activeColor: modeColor,
          ),
        ],
      ),
    );
  }

  static Widget _buildNumberField(
    String fieldName,
    String type,
    dynamic currentValue,
    Function(dynamic) onChanged,
    Color modeColor, {
    required bool isInteger,
    String? example,
    Map<String, dynamic>? fieldDefinition,
  }) {
    final min = fieldDefinition?['min'] as int?;
    final max = fieldDefinition?['max'] as int?;
    final rosType = fieldDefinition?['rosType'] as String? ?? type;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: currentValue?.toString() ?? '',
            style: TextStyle(color: Colors.white),
            keyboardType: isInteger
                ? TextInputType.number
                : TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _formatFieldName(fieldName),
              labelStyle: WidgetStateTextStyle.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return TextStyle(color: modeColor);
                }
                return TextStyle(color: Colors.grey[400]);
              }),
              floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return TextStyle(color: modeColor);
                }
                return TextStyle(color: Colors.grey[400]);
              }),
              suffixText: rosType,
              helperText: min != null && max != null
                  ? 'Enter value between $min-$max'
                  : null,
              helperStyle: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
              ),
              suffixStyle: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              filled: true,
              fillColor: Color(0xFF1E1E1E),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[600]!, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: modeColor, width: 2),
              ),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            inputFormatters: isInteger
                ? [FilteringTextInputFormatter.digitsOnly]
                : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onChanged: (value) {
              if (value.isEmpty) {
                onChanged(0);
                return;
              }

              final numValue = int.tryParse(value) ?? 0;
              if (min != null && max != null) {
                onChanged(numValue.clamp(min, max));
              } else {
                onChanged(numValue);
              }
            },
          ),
          if (example != null) ...[
            SizedBox(height: 4),
            Text(
              'Example: $example',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _buildTextField(
    String fieldName,
    String type,
    dynamic currentValue,
    Function(dynamic) onChanged,
    Color modeColor,
    String? example,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: currentValue?.toString() ?? '',
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: _formatFieldName(fieldName),
              labelStyle: WidgetStateTextStyle.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return TextStyle(color: modeColor);
                }
                return TextStyle(color: Colors.grey[400]);
              }),
              floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return TextStyle(color: modeColor);
                }
                return TextStyle(color: Colors.grey[400]);
              }),
              suffixText: type,
              suffixStyle: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              filled: true,
              fillColor: Color(0xFF1E1E1E),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[600]!, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: modeColor, width: 2),
              ),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onChanged: onChanged,
          ),
          if (example != null) ...[
            SizedBox(height: 4),
            Text(
              'Example: $example',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _buildTimeField(
    String fieldName,
    String type,
    dynamic currentValue,
    Function(dynamic) onChanged,
    Color modeColor,
    String? example,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatFieldName(fieldName),
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: (currentValue as Map<String, dynamic>?)?['sec']
                          ?.toString() ??
                      '0',
                  style: TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Seconds',
                    labelStyle: WidgetStateTextStyle.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return TextStyle(color: modeColor);
                      }
                      return TextStyle(color: Colors.grey[400]);
                    }),
                    floatingLabelStyle:
                        WidgetStateTextStyle.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return TextStyle(color: modeColor);
                      }
                      return TextStyle(color: Colors.grey[400]);
                    }),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Colors.grey[600]!, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: modeColor, width: 2),
                    ),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  onChanged: (value) {
                    final current = currentValue ?? {};
                    current['sec'] = int.tryParse(value) ?? 0;
                    onChanged(current);
                  },
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: (currentValue)?['nanosec']?.toString() ?? '0',
                  style: TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Nanoseconds',
                    labelStyle: WidgetStateTextStyle.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return TextStyle(color: modeColor);
                      }
                      return TextStyle(color: Colors.grey[400]);
                    }),
                    floatingLabelStyle:
                        WidgetStateTextStyle.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return TextStyle(color: modeColor);
                      }
                      return TextStyle(color: Colors.grey[400]);
                    }),
                    filled: true,
                    fillColor: Color(0xFF1E1E1E),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Colors.grey[600]!, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: modeColor, width: 2),
                    ),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  onChanged: (value) {
                    final current = currentValue ?? {};
                    current['nanosec'] = int.tryParse(value) ?? 0;
                    onChanged(current);
                  },
                ),
              ),
            ],
          ),
          if (example != null) ...[
            SizedBox(height: 4),
            Text(
              'Example: $example',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _buildObjectField(
    String fieldName,
    Map<String, dynamic> fieldDefinition,
    String type,
    dynamic currentValue,
    Function(dynamic) onChanged,
    Color modeColor,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[700]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        title: Text(
          _formatFieldName(fieldName),
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        iconColor: modeColor,
        collapsedIconColor: modeColor,
        children: [
          Container(
            padding: EdgeInsets.all(12),
            child: Text(
              'Complex object: ${fieldDefinition['type']}',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildArrayField(
    String fieldName,
    Map<String, dynamic> fieldDefinition,
    dynamic currentValue,
    Function(dynamic) onChanged,
    Color modeColor,
  ) {
    final arrayType = fieldDefinition['arrayType'] as String;
    final arrayLength = fieldDefinition['arrayLength'] as int;
    final isByteArray = arrayType == 'byte' || arrayType == 'octet';

    // For byte/octet arrays, show a single text field with comma-separated values
    if (isByteArray) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: currentValue is List ? currentValue.join(', ') : '',
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: _formatFieldName(fieldName),
              labelStyle: WidgetStateTextStyle.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return TextStyle(color: modeColor);
                }
                return TextStyle(color: Colors.grey[400]);
              }),
              filled: true,
              fillColor: Color(0xFF1E1E1E),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[600]!, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: modeColor, width: 2),
              ),
              suffixText: arrayType,
              helperText: 'Enter values (0-255) separated by commas',
              helperStyle: TextStyle(color: Colors.grey[400]),
            ),
            onChanged: (value) {
              final values = value.split(',').map((s) {
                final parsed = int.tryParse(s.trim());
                return parsed != null && parsed >= 0 && parsed <= 255
                    ? parsed
                    : 0;
              }).toList();
              onChanged(values);
            },
          ),
        ],
      );
    }

    final List<dynamic> arrayValue = currentValue as List<dynamic>? ?? [];
    final widget = fieldDefinition['widget'] as String;
    final itemType = fieldDefinition['itemType'] as String? ?? 'string';
    final rosType = fieldDefinition['rosType'] as String? ?? itemType;

    // Handle primitive arrays vs nested arrays
    bool isPrimitiveArray = widget == 'primitive_array';

    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatFieldName(fieldName),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (arrayLength > 0)
                    Text(
                      'Fixed size array [$arrayLength]',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              if (arrayLength == 0 &&
                  !isPrimitiveArray) // Only for non-primitive dynamic arrays
                IconButton(
                  onPressed: () {
                    final newArray = List<dynamic>.from(arrayValue);
                    final itemStructure = fieldDefinition['itemStructure']
                        as Map<String, dynamic>;
                    newArray.add(MessageParser.getDefaultValueForStructure(
                        itemStructure));
                    onChanged(newArray);
                  },
                  icon: Icon(Icons.add, color: modeColor),
                ),
            ],
          ),

          // For dynamic primitive arrays, show a single text field with comma-separated values
          if (isPrimitiveArray && arrayLength == 0)
            Container(
              margin: EdgeInsets.only(top: 8),
              child: TextFormField(
                initialValue: arrayValue.isEmpty ? '' : arrayValue.join(', '),
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Values',
                  labelStyle: WidgetStateTextStyle.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return TextStyle(color: modeColor);
                    }
                    return TextStyle(color: Colors.grey[400]);
                  }),
                  floatingLabelStyle:
                      WidgetStateTextStyle.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return TextStyle(color: modeColor);
                    }
                    return TextStyle(color: Colors.grey[400]);
                  }),
                  hintText: _getArrayHintText(rosType),
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  helperText: _getArrayHelperText(rosType),
                  helperStyle: TextStyle(color: Colors.grey[400]),
                  suffixText: '$rosType[]',
                  suffixStyle: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[600]!, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: modeColor, width: 2),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                onChanged: (value) {
                  final values = value
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                  final typedValues = values
                      .map((v) => _parseValueForType(v, rosType))
                      .toList();
                  onChanged(typedValues);
                },
              ),
            ),

          // For fixed size arrays or nested arrays, keep the existing individual field approach
          if (!isPrimitiveArray || arrayLength > 0)
            ...List.generate(
              arrayLength > 0 ? arrayLength : arrayValue.length,
              (index) {
                final value =
                    index < arrayValue.length ? arrayValue[index] : null;

                if (isPrimitiveArray) {
                  // Primitive array items
                  final itemWidget = fieldDefinition['itemWidget'] as String;

                  final itemFieldDefinition = {
                    'type': itemType,
                    'widget': itemWidget,
                  };

                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: generateFormField(
                            '[$index]',
                            itemFieldDefinition,
                            value,
                            (newValue) {
                              final newArray = List<dynamic>.from(arrayValue);
                              // Ensure array is the right size
                              while (newArray.length <= index) {
                                newArray.add(
                                    MessageParser.getDefaultForPrimitiveType(
                                        itemType));
                              }
                              newArray[index] = newValue;
                              onChanged(newArray);
                            },
                            modeColor,
                          ),
                        ),
                        if (arrayLength ==
                            0) // Only show remove for dynamic arrays
                          IconButton(
                            onPressed: () {
                              final newArray = List<dynamic>.from(arrayValue);
                              newArray.removeAt(index);
                              onChanged(newArray);
                            },
                            icon: Icon(Icons.remove_circle, color: Colors.red),
                          ),
                      ],
                    ),
                  );
                } else {
                  // Nested object array items
                  final itemStructure =
                      fieldDefinition['itemStructure'] as Map<String, dynamic>;

                  final itemFieldDefinition = {
                    'type': 'nested',
                    'widget': 'nested',
                    'structure': itemStructure,
                  };

                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: generateFormField(
                            '[$index]',
                            itemFieldDefinition,
                            value,
                            (newValue) {
                              final newArray = List<dynamic>.from(arrayValue);
                              // Ensure array is the right size
                              while (newArray.length <= index) {
                                newArray.add(
                                    MessageParser.getDefaultValueForStructure(
                                        itemStructure));
                              }
                              newArray[index] = newValue;
                              onChanged(newArray);
                            },
                            modeColor,
                          ),
                        ),
                        if (arrayLength ==
                            0) // Only show remove for dynamic arrays
                          IconButton(
                            onPressed: () {
                              final newArray = List<dynamic>.from(arrayValue);
                              newArray.removeAt(index);
                              onChanged(newArray);
                            },
                            icon: Icon(Icons.remove_circle, color: Colors.red),
                          ),
                      ],
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  static String _getArrayHintText(String type) {
    switch (type) {
      case 'bool':
      case 'boolean':
        return 'Enter true/false values separated by commas';
      case 'byte':
      case 'octet':
        return 'Enter byte values (0-255) separated by commas';
      case 'int8':
      case 'int16':
      case 'int32':
      case 'int64':
        return 'Enter integer values separated by commas';
      case 'float':
      case 'float32':
      case 'float64':
      case 'double':
        return 'Enter decimal values separated by commas';
      case 'string':
        return 'Enter text values separated by commas';
      default:
        return 'Enter values separated by commas';
    }
  }

  static String _getArrayHelperText(String type) {
    switch (type) {
      case 'bool':
      case 'boolean':
        return 'Example: true, false, true';
      case 'byte':
      case 'octet':
        return 'Example: 0, 128, 255 (values between 0-255)';
      case 'int8':
      case 'int16':
      case 'int32':
      case 'int64':
        return 'Example: 1, 2, 3, 4';
      case 'float':
      case 'float32':
      case 'float64':
      case 'double':
        return 'Example: 1.0, 2.5, 3.14';
      case 'string':
        return 'Example: hello, world, ros2';
      default:
        return '';
    }
  }

  // Add helper method to parse values based on type
  static dynamic _parseValueForType(String value, String type) {
    switch (type) {
      case 'bool':
      case 'boolean':
        return value.toLowerCase() == 'true';
      case 'byte':
      case 'octet':
        final intValue = int.tryParse(value) ?? 0;
        return intValue.clamp(0, 255);
      case 'int8':
      case 'int16':
      case 'int32':
      case 'int64':
      case 'uint8':
      case 'uint16':
      case 'uint32':
      case 'uint64':
        return int.tryParse(value) ?? 0;
      case 'float':
      case 'float32':
      case 'float64':
      case 'double':
        return double.tryParse(value) ?? 0.0;
      default:
        return value;
    }
  }

  static String _formatFieldName(String fieldName) {
    return fieldName
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) =>
            word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : word)
        .join(' ');
  }

  static String _getWidgetTypeForType(String type) {
    switch (type) {
      case 'bool':
        return 'switch';
      case 'int8':
      case 'int16':
      case 'int32':
      case 'int64':
      case 'uint8':
      case 'uint16':
      case 'uint32':
      case 'uint64':
        return 'number';
      case 'float':
      case 'float32':
      case 'float64':
        return 'decimal';
      case 'string':
        return 'text';
      case 'time':
      case 'duration':
        return 'time';
      default:
        return 'object';
    }
  }

  static dynamic _getDefaultValue(String type) {
    switch (type) {
      case 'bool':
        return false;
      case 'int8':
      case 'int16':
      case 'int32':
      case 'int64':
      case 'uint8':
      case 'uint16':
      case 'uint32':
      case 'uint64':
        return 0;
      case 'float':
      case 'float32':
      case 'float64':
        return 0.0;
      case 'string':
        return '';
      case 'time':
      case 'duration':
        return {'sec': 0, 'nanosec': 0};
      default:
        return {};
    }
  }
}
