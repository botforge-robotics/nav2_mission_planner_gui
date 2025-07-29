class LicenseData {
  // Core license information
  final String tokenId;
  final String licenseType; // "individual" or "organisation"
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String androidId;
  final String label;
  final bool active;
  final String userId;

  // Organization-specific branding data (null for individual)
  final String? organizationId;
  final String? groupId;
  final String? companyName;
  final String? appTitle;
  final String? supportEmail;
  final String? themeColor;
  final String? website;
  final String? logoUrl;
  final String? faviconUrl;
  final String? tagLine;
  final String? footerCredits;

  // App tracking
  final DateTime lastVerified;
  final bool isOnlineVerified;

  LicenseData({
    required this.tokenId,
    required this.licenseType,
    required this.issuedAt,
    required this.expiresAt,
    required this.androidId,
    required this.label,
    required this.active,
    required this.userId,
    this.organizationId,
    this.groupId,
    this.companyName,
    this.appTitle,
    this.supportEmail,
    this.themeColor,
    this.website,
    this.logoUrl,
    this.faviconUrl,
    this.tagLine,
    this.footerCredits,
    required this.lastVerified,
    required this.isOnlineVerified,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'tokenId': tokenId,
      'licenseType': licenseType,
      'issuedAt': issuedAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'androidId': androidId,
      'label': label,
      'active': active,
      'userId': userId,
      'organizationId': organizationId,
      'groupId': groupId,
      'companyName': companyName,
      'appTitle': appTitle,
      'supportEmail': supportEmail,
      'themeColor': themeColor,
      'website': website,
      'logoUrl': logoUrl,
      'faviconUrl': faviconUrl,
      'tagLine': tagLine,
      'footerCredits': footerCredits,
      'lastVerified': lastVerified.toIso8601String(),
      'isOnlineVerified': isOnlineVerified,
    };
  }

  // Create from JSON
  factory LicenseData.fromJson(Map<String, dynamic> json) {
    return LicenseData(
      tokenId: json['tokenId'],
      licenseType: json['licenseType'],
      issuedAt: DateTime.parse(json['issuedAt']),
      expiresAt: DateTime.parse(json['expiresAt']),
      androidId: json['androidId'],
      label: json['label'],
      active: json['active'],
      userId: json['userId'],
      organizationId: json['organizationId'],
      groupId: json['groupId'],
      companyName: json['companyName'],
      appTitle: json['appTitle'],
      supportEmail: json['supportEmail'],
      themeColor: json['themeColor'],
      website: json['website'],
      logoUrl: json['logoUrl'],
      faviconUrl: json['faviconUrl'],
      tagLine: json['tagLine'],
      footerCredits: json['footerCredits'],
      lastVerified: DateTime.parse(json['lastVerified']),
      isOnlineVerified: json['isOnlineVerified'],
    );
  }

  // Check if license is expired
  bool get isExpired {
    return DateTime.now().isAfter(expiresAt);
  }

  // Check if license is within grace period (30 days)
  bool get isWithinGracePeriod {
    final gracePeriodEnd = expiresAt.add(const Duration(days: 30));
    return DateTime.now().isBefore(gracePeriodEnd);
  }

  // Check if this is an organization license
  bool get isOrganizationLicense {
    return licenseType == "organisation";
  }

  // Check if this is an individual license
  bool get isIndividualLicense {
    return licenseType == "individual";
  }

  // Check if branding is available
  bool get hasBranding {
    return isOrganizationLicense && companyName != null && appTitle != null;
  }
}
