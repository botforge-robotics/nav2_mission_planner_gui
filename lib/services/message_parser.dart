import 'package:rosapi_msgs/msg.dart';
import 'dart:developer' as developer;

class MessageParser {
  static String normalizeMessageType(String messageType) {
    // First remove _Request or _Response suffix
    String normalized = messageType.replaceAll(
        RegExp(r'(_Request|_Response|_Goal|_Result|_Feedback)$'), '');

    // Then replace /srv/, /msg/, or /action/ with /
    normalized = normalized.replaceAll(RegExp(r'/(srv|msg|action)/'), '/');

    return normalized;
  }

  static Map<String, dynamic> parseMessageStructure(
      List<TypeDef> typedefs, String targetMessageType, String context) {
    developer.log('Parsing message structure for: $targetMessageType',
        name: 'MessageParser');
    developer.log('Received typedefs: ${typedefs.length}',
        name: 'MessageParser');

    // Normalize the message type
    final strippedType = normalizeMessageType(targetMessageType);

    // Create a map to store all type definitions
    final Map<String, TypeDef> typeDefMap = {};
    for (final typedef in typedefs) {
      // Normalize typedef type
      final strippedTypedef = normalizeMessageType(typedef.type);
      typeDefMap[strippedTypedef] = typedef;
    }
    developer.log('TypeDef map: $typeDefMap', name: 'MessageParser');

    // Parse using normalized type
    return _parseTypeDefinition(strippedType, typeDefMap);
  }

  static Map<String, dynamic> _parseTypeDefinition(
      String messageType, Map<String, TypeDef> typeDefMap) {
    final typedef = typeDefMap[messageType];
    if (typedef == null) {
      developer.log('No typedef found for message type: $messageType',
          name: 'MessageParser');
      return {};
    }

    developer.log('Parsing typedef for message type: $messageType',
        name: 'MessageParser');

    // Normalize field types before processing
    final normalizedFieldTypes = typedef.fieldtypes;

    final Map<String, dynamic> fields = {};

    for (int i = 0; i < typedef.fieldnames.length; i++) {
      final fieldName = typedef.fieldnames[i];
      final fieldType = normalizedFieldTypes[i];
      final arrayLength = typedef.fieldarraylen[i];

      // Remove underscore prefix from field names
      final cleanFieldName =
          fieldName.startsWith('_') ? fieldName.substring(1) : fieldName;

      developer.log('Processing field: $cleanFieldName of type: $fieldType',
          name: 'MessageParser');

      if (_isPrimitiveType(fieldType)) {
        // Handle primitive types
        fields[cleanFieldName] =
            _createPrimitiveFieldDefinition(fieldType, arrayLength);
      } else {
        // Handle nested types
        if (arrayLength > 0) {
          // Fixed-size array of nested types
          fields[cleanFieldName] = {
            'type': 'array',
            'widget': 'array',
            'arrayType': fieldType,
            'arrayLength': arrayLength,
            'itemStructure': _parseTypeDefinition(fieldType, typeDefMap),
          };
        } else {
          // Single nested type
          fields[cleanFieldName] = {
            'type': 'nested',
            'widget': 'nested',
            'nestedType': fieldType,
            'structure': _parseTypeDefinition(fieldType, typeDefMap),
          };
        }
      }
    }

    return fields;
  }

  static bool _isPrimitiveType(String type) {
    const primitiveTypes = {
      'bool',
      'boolean',
      'int8',
      'int16',
      'int32',
      'int64',
      'uint8',
      'uint16',
      'uint32',
      'uint64',
      'float',
      'float32',
      'float64',
      'double',
      'string',
      'time',
      'duration'
    };
    return primitiveTypes.contains(type);
  }

  static Map<String, dynamic> _createPrimitiveFieldDefinition(
      String type, int arrayLength) {
    Map<String, dynamic> fieldDef = _getPrimitiveTypeInfo(type);

    // Always add original ROS type
    fieldDef['rosType'] = type;

    // Handle array types based on arrayLength
    if (arrayLength != -1) {
      // -1 means not an array
      fieldDef = {
        'type': 'array',
        'widget': 'primitive_array',
        'arrayType': type,
        'arrayLength':
            arrayLength, // 0 means dynamic array, >0 means fixed size
        'itemType': fieldDef['type'],
        'itemWidget': fieldDef['widget'],
        'rosType': type, // Store original ROS type for display
        'min': fieldDef['min'], // Preserve min/max for byte type
        'max': fieldDef['max'],
      };
    }

    return fieldDef;
  }

  static Map<String, dynamic> _getPrimitiveTypeInfo(String type) {
    switch (type) {
      case 'boolean':
      case 'bool':
        return {'type': 'bool', 'widget': 'switch'};
      case 'byte':
      case 'octet':
        return {
          'type': 'int',
          'widget': 'number',
          'signed': false,
          'min': 0,
          'max': 255,
          'rosType': 'byte'
        };
      case 'int8':
      case 'int16':
      case 'int32':
      case 'int64':
        return {'type': 'int', 'widget': 'number', 'signed': true};
      case 'uint8':
      case 'uint16':
      case 'uint32':
      case 'uint64':
        return {'type': 'int', 'widget': 'number', 'signed': false};
      case 'float':
      case 'float32':
      case 'float64':
      case 'double':
        return {'type': 'double', 'widget': 'decimal'};
      case 'string':
        return {'type': 'string', 'widget': 'text'};
      case 'time':
      case 'duration':
        return {'type': 'time', 'widget': 'time_picker'};
      default:
        return {'type': 'string', 'widget': 'text'};
    }
  }

  /// Get default value for a field based on its definition
  static dynamic getDefaultValue(Map<String, dynamic> fieldDef) {
    final type = fieldDef['type'];

    if (type == 'array') {
      final arrayLength = fieldDef['arrayLength'] as int;
      final arrayType = fieldDef['arrayType'];

      if (fieldDef['widget'] == 'primitive_array') {
        // Array of primitives
        final itemDefault = getDefaultForPrimitiveType(arrayType);
        return List.filled(arrayLength, itemDefault);
      } else {
        // Array of nested objects
        final itemStructure = fieldDef['itemStructure'] as Map<String, dynamic>;
        final itemDefault = getDefaultValueForStructure(itemStructure);
        return List.filled(arrayLength, itemDefault);
      }
    } else if (type == 'nested') {
      // Nested object
      final structure = fieldDef['structure'] as Map<String, dynamic>;
      return getDefaultValueForStructure(structure);
    } else {
      // Primitive type
      return getDefaultForPrimitiveType(type);
    }
  }

  /// Get default value for an entire message structure
  static Map<String, dynamic> getDefaultValueForStructure(
      Map<String, dynamic> structure) {
    final Map<String, dynamic> defaultValue = {};

    for (final entry in structure.entries) {
      defaultValue[entry.key] = getDefaultValue(entry.value);
    }

    return defaultValue;
  }

  static dynamic getDefaultForPrimitiveType(String type) {
    switch (type) {
      case 'boolean':
      case 'bool':
        return false;
      case 'byte':
      case 'octet':
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
      case 'double':
        return 0.0;
      case 'string':
        return '';
      case 'time':
      case 'duration':
        return {'sec': 0, 'nanosec': 0};
      default:
        return null;
    }
  }
}
