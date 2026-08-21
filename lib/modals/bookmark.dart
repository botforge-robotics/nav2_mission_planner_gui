import 'package:flutter/material.dart';

class Bookmark {
  final String id;
  final IconData icon;
  final String name;
  final double positionX;
  final double positionY;
  final double positionZ;
  final double theta;
  bool isGoalActive;
  // Marks this bookmark as the robot's charging dock pose. At most one
  // dock bookmark is kept active per map (see SettingsProvider.addBookmark).
  final bool isDock;

  Bookmark({
    required this.id,
    required this.icon,
    required this.name,
    required this.positionX,
    required this.positionY,
    required this.positionZ,
    required this.theta,
    this.isGoalActive = false,
    this.isDock = false,
  });

  // Convert a Bookmark instance to a Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'icon': icon.codePoint, // Store the icon as an integer code point
      'name': name,
      'positionX': positionX,
      'positionY': positionY,
      'positionZ': positionZ,
      'theta': theta,
      'isGoalActive': isGoalActive,
      'isDock': isDock,
    };
  }

  // Create a Bookmark instance from a Map
  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'],
      icon: IconData(json['icon'],
          fontFamily: 'MaterialIcons'), // Recreate the IconData
      name: json['name'],
      positionX: json['positionX'],
      positionY: json['positionY'],
      positionZ: json['positionZ'],
      theta: json['theta'],
      isGoalActive: json['isGoalActive'] ?? false,
      isDock: json['isDock'] ?? false,
    );
  }

  Bookmark copyWith({
    IconData? icon,
    String? name,
    double? positionX,
    double? positionY,
    double? positionZ,
    double? theta,
    bool? isGoalActive,
    bool? isDock,
  }) {
    return Bookmark(
      id: id,
      icon: icon ?? this.icon,
      name: name ?? this.name,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      positionZ: positionZ ?? this.positionZ,
      theta: theta ?? this.theta,
      isGoalActive: isGoalActive ?? this.isGoalActive,
      isDock: isDock ?? this.isDock,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Bookmark &&
        id == other.id &&
        icon == other.icon &&
        name == other.name &&
        positionX == other.positionX &&
        positionY == other.positionY &&
        positionZ == other.positionZ &&
        theta == other.theta &&
        isDock == other.isDock;
  }

  @override
  int get hashCode {
    return Object.hash(
        id, icon, name, positionX, positionY, positionZ, theta, isDock);
  }
}

class BookmarkModal extends StatelessWidget {
  final Bookmark bookmark;

  const BookmarkModal({super.key, required this.bookmark});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(bookmark.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(bookmark.icon, size: 48),
          SizedBox(height: 16),
          Text(
              'Position: (${bookmark.positionX}, ${bookmark.positionY}, ${bookmark.positionZ})'),
          Text('Theta: ${bookmark.theta}°'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
      ],
    );
  }
}
