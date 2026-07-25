import 'dart:convert';
import 'package:ros2_msg_utils/ros2_msg_utils.dart';
import '../msg/TypeDef.dart';

class ServiceRequestDetailsRequest
    extends RosMessage<ServiceRequestDetailsRequest> {
  String type;

  static ServiceRequestDetailsRequest $prototype =
      ServiceRequestDetailsRequest();

  ServiceRequestDetailsRequest({this.type = ''});

  @override
  String get fullType => 'rosapi_msgs/srv/ServiceRequestDetails_Request';

  @override
  String get messageDefinition => 'string type';

  @override
  int getMessageSize() => type.length;

  @override
  Map<String, dynamic> toJson() => {'type': type};

  @override
  String toJsonString() => json.encode(toJson());

  @override
  ServiceRequestDetailsRequest fromJson(Map<String, dynamic> jsonMap) =>
      ServiceRequestDetailsRequest(
        type: jsonMap['type'] as String,
      );
}

class ServiceRequestDetailsResponse
    extends RosMessage<ServiceRequestDetailsResponse> {
  List<TypeDef> typedefs;

  static ServiceRequestDetailsResponse $prototype =
      ServiceRequestDetailsResponse();

  ServiceRequestDetailsResponse({
    this.typedefs = const [],
  });

  @override
  String get fullType => 'rosapi_msgs/srv/ServiceRequestDetails_Response';

  @override
  String get messageDefinition => '''string type
---
TypeDef[] typedefs
	string type
	string[] fieldnames
	string[] fieldtypes
	int32[] fieldarraylen
	string[] examples
	string[] constnames
	string[] constvalues''';

  @override
  int getMessageSize() {
    return typedefs.fold(0, (sum, typedef) => sum + typedef.getMessageSize());
  }

  @override
  Map<String, dynamic> toJson() => {
        'typedefs': typedefs.map((typedef) => typedef.toJson()).toList(),
      };

  @override
  String toJsonString() => json.encode(toJson());

  @override
  ServiceRequestDetailsResponse fromJson(Map<String, dynamic> jsonMap) {
    return ServiceRequestDetailsResponse(
      typedefs: (jsonMap['typedefs'] as List<dynamic>?)
              ?.map((item) => TypeDef().fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class ServiceRequestDetails extends RosServiceMessage<
    ServiceRequestDetailsRequest, ServiceRequestDetailsResponse> {
  @override
  ServiceRequestDetailsRequest get request => ServiceRequestDetailsRequest();

  @override
  ServiceRequestDetailsResponse get response => ServiceRequestDetailsResponse();

  @override
  String get fullType => 'rosapi_msgs/srv/ServiceRequestDetails';

  @override
  String get messageDefinition => '''string type
---
string type
TypeDef[] typedefs
	string type
	string[] fieldnames
	string[] fieldtypes
	int32[] fieldarraylen
	string[] examples
	string[] constnames
	string[] constvalues''';
}
