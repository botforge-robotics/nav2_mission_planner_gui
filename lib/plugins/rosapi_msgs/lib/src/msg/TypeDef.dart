import 'package:ros2_msg_utils/ros2_msg_utils.dart';
import 'dart:convert';

class TypeDef extends RosMessage<TypeDef> {
  String type;
  List<String> fieldnames;
  List<String> fieldtypes;
  List<int> fieldarraylen;
  List<String> examples;
  List<String> constnames;
  List<String> constvalues;

  static TypeDef $prototype = TypeDef();

  TypeDef({
    this.type = '',
    this.fieldnames = const [],
    this.fieldtypes = const [],
    this.fieldarraylen = const [],
    this.examples = const [],
    this.constnames = const [],
    this.constvalues = const [],
  });

  @override
  String get fullType => 'rosapi_msgs/msg/TypeDef';

  @override
  String get messageDefinition => '''string type
string[] fieldnames
string[] fieldtypes
int32[] fieldarraylen
string[] examples
string[] constnames
string[] constvalues''';

  @override
  int getMessageSize() {
    return (type.length +
            fieldnames.fold(0, (sum, name) => sum + name.length) +
            (4 * fieldnames.length) +
            fieldtypes.fold(0, (sum, type) => sum + type.length) +
            (4 * fieldtypes.length) +
            (4 * fieldarraylen.length) +
            examples.fold(0, (sum, example) => sum + example.length) +
            (4 * examples.length) +
            constnames.fold(0, (sum, name) => sum + name.length) +
            (4 * constnames.length) +
            constvalues.fold(0, (sum, value) => sum + value.length) +
            (4 * constvalues.length))
        .toInt();
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'fieldnames': fieldnames,
        'fieldtypes': fieldtypes,
        'fieldarraylen': fieldarraylen,
        'examples': examples,
        'constnames': constnames,
        'constvalues': constvalues,
      };

  @override
  String toJsonString() => json.encode(toJson());

  @override
  TypeDef fromJson(Map<String, dynamic> jsonMap) {
    return TypeDef(
      type: jsonMap['type'] as String,
      fieldnames: List<String>.from(jsonMap['fieldnames']),
      fieldtypes: List<String>.from(jsonMap['fieldtypes']),
      fieldarraylen: List<int>.from(jsonMap['fieldarraylen']),
      examples: List<String>.from(jsonMap['examples']),
      constnames: List<String>.from(jsonMap['constnames']),
      constvalues: List<String>.from(jsonMap['constvalues']),
    );
  }
}
