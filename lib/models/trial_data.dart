class TrialData {
  final DateTime startTime;
  final DateTime endTime;
  final bool isActive;
  final int remainingDays;

  TrialData({
    required this.startTime,
    required this.endTime,
    required this.isActive,
    required this.remainingDays,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'isActive': isActive,
      'remainingDays': remainingDays,
    };
  }

  // Create from JSON
  factory TrialData.fromJson(Map<String, dynamic> json) {
    return TrialData(
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      isActive: json['isActive'],
      remainingDays: json['remainingDays'],
    );
  }
}
