// License status enum
enum LicenseStatus {
  checking,
  welcome,
  trial,
  expired,
  valid,
  noInternet,
  error,
  mandatoryCheckRequired,
  tamperingDetected,
}

// Trial status enum
enum TrialStatus {
  notStarted,
  active,
  expired,
}

// License data class
class LicenseData {
  final String licenseType;
  final String? companyName;
  final String? appTitle;
  final String? supportEmail;
  final String? themeColor;
  final String? website;
  final String? logoUrl;
  final String? faviconUrl;
  final String? tagLine;
  final String? footerCredits;

  LicenseData({
    required this.licenseType,
    this.companyName,
    this.appTitle,
    this.supportEmail,
    this.themeColor,
    this.website,
    this.logoUrl,
    this.faviconUrl,
    this.tagLine,
    this.footerCredits,
  });

  factory LicenseData.fromJson(Map<String, dynamic> json) {
    return LicenseData(
      licenseType: json['licenseType'] ?? 'individual',
      companyName: json['companyName'],
      appTitle: json['appTitle'],
      supportEmail: json['supportEmail'],
      themeColor: json['themeColor'],
      website: json['website'],
      logoUrl: json['logoUrl'],
      faviconUrl: json['faviconUrl'],
      tagLine: json['tagLine'],
      footerCredits: json['footerCredits'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'licenseType': licenseType,
      'companyName': companyName,
      'appTitle': appTitle,
      'supportEmail': supportEmail,
      'themeColor': themeColor,
      'website': website,
      'logoUrl': logoUrl,
      'faviconUrl': faviconUrl,
      'tagLine': tagLine,
      'footerCredits': footerCredits,
    };
  }
}

// Trial data class
class TrialData {
  final TrialStatus status;
  final int? remainingDays;
  final DateTime? startTime;
  final DateTime? endTime;

  TrialData({
    required this.status,
    this.remainingDays,
    this.startTime,
    this.endTime,
  });

  factory TrialData.fromJson(Map<String, dynamic> json) {
    return TrialData(
      status: _parseTrialStatus(json['status']),
      remainingDays: json['remainingDays'],
      startTime:
          json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'remainingDays': remainingDays,
      'startTime': startTime?.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
    };
  }

  static TrialStatus _parseTrialStatus(String status) {
    switch (status) {
      case 'notStarted':
        return TrialStatus.notStarted;
      case 'active':
        return TrialStatus.active;
      case 'expired':
        return TrialStatus.expired;
      default:
        return TrialStatus.notStarted;
    }
  }
}

// License verification response
class LicenseVerificationResponse {
  final bool licenseVerified;
  final String licenseType;
  final LicenseData? data;
  final String? errorMessage;

  LicenseVerificationResponse({
    required this.licenseVerified,
    required this.licenseType,
    this.data,
    this.errorMessage,
  });

  factory LicenseVerificationResponse.fromJson(Map<String, dynamic> json) {
    return LicenseVerificationResponse(
      licenseVerified: json['licenseVerified'] ?? false,
      licenseType: json['licenseType'] ?? 'individual',
      data: json['data'] != null ? LicenseData.fromJson(json['data']) : null,
      errorMessage: json['errorMessage'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'licenseVerified': licenseVerified,
      'licenseType': licenseType,
      'data': data?.toJson(),
      'errorMessage': errorMessage,
    };
  }
}

// Trial status response
class TrialStatusResponse {
  final bool success;
  final TrialData? data;
  final String? message;
  final String? error;

  TrialStatusResponse({
    required this.success,
    this.data,
    this.message,
    this.error,
  });

  factory TrialStatusResponse.fromJson(Map<String, dynamic> json) {
    return TrialStatusResponse(
      success: json['success'] ?? false,
      data: json['data'] != null ? TrialData.fromJson(json['data']) : null,
      message: json['message'],
      error: json['error'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'data': data?.toJson(),
      'message': message,
      'error': error,
    };
  }
}

// Generic API response
class ApiResponse {
  final bool success;
  final String? message;
  final String? error;
  final Map<String, dynamic>? data;

  ApiResponse({
    required this.success,
    this.message,
    this.error,
    this.data,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    return ApiResponse(
      success: json['success'] ?? false,
      message: json['message'],
      error: json['error'],
      data: json['data'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'error': error,
      'data': data,
    };
  }
}

// Device registration response
class DeviceRegistrationResponse {
  final bool success;
  final String? message;
  final String? error;
  final String? deviceId;

  DeviceRegistrationResponse({
    required this.success,
    this.message,
    this.error,
    this.deviceId,
  });

  factory DeviceRegistrationResponse.fromJson(Map<String, dynamic> json) {
    return DeviceRegistrationResponse(
      success: json['success'] ?? false,
      message: json['message'],
      error: json['error'],
      deviceId: json['deviceId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'error': error,
      'deviceId': deviceId,
    };
  }
}
