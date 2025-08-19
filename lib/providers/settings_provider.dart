import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/modals/bookmark.dart';
import 'package:nav2_mission_planner/modals/mission.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../constants/default_settings.dart';
import 'dart:convert';

class SettingsProvider extends ChangeNotifier {
  String robotId;
  // Teleop Settings
  String _cmdVelTopic = DefaultSettings.cmdVelTopic;
  double _linearVelocity = DefaultSettings.defaultLinearVelocity;
  double _angularVelocity = DefaultSettings.defaultAngularVelocity;
  String _twistType = DefaultSettings.defaultTwistType;

  // Mapping Settings
  String _mapsPath = DefaultSettings.defaultMapsFolder;
  String _mappingLaunchFile = DefaultSettings.defaultMappingLaunchFile;
  String _mappingOdomTopic = DefaultSettings.defaultOdomTopic;
  String _mappingOdomTopicType = DefaultSettings.defaultOdomTopicType;
  List<Map<String, String>> _mappingArgs = [];

  // Add new save map settings
  String _saveMapLaunchFile = DefaultSettings.defaultSaveMapLaunchFile;
  List<Map<String, String>> _saveMapArgs = [];

  // Navigation Settings
  String _navigationLaunchFile = DefaultSettings.defaultNavigationLaunchFile;
  String _navigationOdomTopic = DefaultSettings.defaultNavigationOdomTopic;
  String _navigationOdomTopicType =
      DefaultSettings.defaultNavigationOdomTopicType;
  List<Map<String, String>> _navigationArgs = [];

  // General Settings
  String _cameraImageTopic = '/camera/image/compressed';

  // Add new property
  bool _cameraEnabled = false;

  // Add new properties
  String _odomTopic = DefaultSettings.defaultOdomTopic;
  String _odomTopicType = DefaultSettings.defaultOdomTopicType;
  // Add to existing properties
  String _lidarTopic = DefaultSettings.defaultLidarTopic;

  // Communication timeout (in seconds)
  int _communicationTimeout = DefaultSettings.defaultCommunicationTimeout;

  // Add these to the class
  bool _cameraVisible = DefaultSettings.defaultCameraVisible;
  bool _joystickVisible = DefaultSettings.defaultJoystickVisible;

  // Add path topic
  String _pathTopic = DefaultSettings.defaultPathTopic;

  // Add new properti
  Map<String, List<Bookmark>> _bookmarks =
      Map.from(DefaultSettings.defaultBookmarks);

  // Add to existing properties in the class
  bool _bookmarksVisible = DefaultSettings.defaultBookmarksVisible;

  // Add this to class properties
  Map<String, Mission> _missions = {};

  // Getters
  String get cmdVelTopic => _cmdVelTopic;
  double get linearVelocity => _linearVelocity;
  double get angularVelocity => _angularVelocity;
  String get twistType => _twistType;
  String get mapsPath => _mapsPath;
  String get mappingLaunchFile => _mappingLaunchFile;
  String get mappingOdomTopic => _mappingOdomTopic;
  String get mappingOdomTopicType => _mappingOdomTopicType;
  List<Map<String, String>> get mappingArgs => _mappingArgs;
  String get navigationLaunchFile => _navigationLaunchFile;
  String get navigationOdomTopic => _navigationOdomTopic;
  String get navigationOdomTopicType => _navigationOdomTopicType;
  List<Map<String, String>> get navigationArgs => _navigationArgs;
  String get cameraImageTopic => _cameraImageTopic;
  bool get cameraEnabled => _cameraEnabled;
  String get odomTopic => _odomTopic;
  String get odomTopicType => _odomTopicType;
  String get saveMapLaunchFile => _saveMapLaunchFile;
  List<Map<String, String>> get saveMapArgs => _saveMapArgs;
  String get lidarTopic => _lidarTopic;
  bool get cameraVisible => _cameraVisible;
  bool get joystickVisible => _joystickVisible;
  String get pathTopic => _pathTopic;
  Map<String, List<Bookmark>> get bookmarks => _bookmarks;
  int get communicationTimeout => _communicationTimeout;
  bool get bookmarksVisible => _bookmarksVisible;
  Map<String, Mission> get missions => _missions;

  SettingsProvider(this.robotId) {
    _loadSettings();
  }

  // Load settings from shared preferences
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // Load settings using robot-specific key
    final settingsKey = 'settings_$robotId';

    _cmdVelTopic = prefs.getString('$settingsKey:cmdVelTopic') != null
        ? prefs.getString('$settingsKey:cmdVelTopic')!
        : DefaultSettings.cmdVelTopic;
    _linearVelocity = prefs.getDouble('$settingsKey:linearVelocity') ??
        DefaultSettings.defaultLinearVelocity;
    _angularVelocity = prefs.getDouble('$settingsKey:angularVelocity') ??
        DefaultSettings.defaultAngularVelocity;
    _twistType = prefs.getString('$settingsKey:twistType') != null
        ? prefs.getString('$settingsKey:twistType')!
        : DefaultSettings.defaultTwistType;
    _mapsPath = prefs.getString('$settingsKey:mapsPath') != null
        ? prefs.getString('$settingsKey:mapsPath')!
        : DefaultSettings.defaultMapsFolder;

    // Load mapping launch file
    final rawMappingLaunchFile =
        prefs.getString('$settingsKey:mappingLaunchFile');

    // Only use default if the value was never saved (null), not if it's an empty string
    if (rawMappingLaunchFile != null) {
      _mappingLaunchFile = rawMappingLaunchFile;
    } else {
      _mappingLaunchFile = DefaultSettings.defaultMappingLaunchFile;
    }
    _mappingOdomTopic = prefs.getString('$settingsKey:mappingOdomTopic') != null
        ? prefs.getString('$settingsKey:mappingOdomTopic')!
        : DefaultSettings.defaultOdomTopic;
    _mappingOdomTopicType =
        prefs.getString('$settingsKey:mappingOdomTopicType') != null
            ? prefs.getString('$settingsKey:mappingOdomTopicType')!
            : DefaultSettings.defaultMappingOdomTopicType;
    _navigationLaunchFile =
        prefs.getString('$settingsKey:navigationLaunchFile') != null
            ? prefs.getString('$settingsKey:navigationLaunchFile')!
            : DefaultSettings.defaultNavigationLaunchFile;
    _navigationOdomTopic =
        prefs.getString('$settingsKey:navigationOdomTopic') != null
            ? prefs.getString('$settingsKey:navigationOdomTopic')!
            : DefaultSettings.defaultNavigationOdomTopic;
    _navigationOdomTopicType =
        prefs.getString('$settingsKey:navigationOdomTopicType') != null
            ? prefs.getString('$settingsKey:navigationOdomTopicType')!
            : DefaultSettings.defaultNavigationOdomTopicType;
    // Load mapping and navigation args
    final String? mappingArgsJson = prefs.getString('$settingsKey:mappingArgs');
    if (mappingArgsJson != null) {
      List<dynamic> argsList = json.decode(mappingArgsJson);
      _mappingArgs = List<Map<String, String>>.from(
          argsList.map((item) => Map<String, String>.from(item)));
    }

    final String? navigationArgsJson =
        prefs.getString('$settingsKey:navigationArgs');
    if (navigationArgsJson != null) {
      List<dynamic> argsList = json.decode(navigationArgsJson);
      _navigationArgs = List<Map<String, String>>.from(
          argsList.map((item) => Map<String, String>.from(item)));
    }

    // Add camera topic loading
    _cameraImageTopic = prefs.getString('$settingsKey:cameraImageTopic') != null
        ? prefs.getString('$settingsKey:cameraImageTopic')!
        : DefaultSettings.defaultCameraTopic;

    // Update _cameraEnabled
    _cameraEnabled = prefs.getBool('$settingsKey:cameraEnabled') ?? false;

    // Load new topics
    _odomTopic = prefs.getString('$settingsKey:odomTopic') != null
        ? prefs.getString('$settingsKey:odomTopic')!
        : DefaultSettings.defaultOdomTopic;
    _odomTopicType = prefs.getString('$settingsKey:odomTopicType') != null
        ? prefs.getString('$settingsKey:odomTopicType')!
        : DefaultSettings.defaultOdomTopicType;

    // Load save map settings
    _saveMapLaunchFile =
        prefs.getString('$settingsKey:saveMapLaunchFile') != null
            ? prefs.getString('$settingsKey:saveMapLaunchFile')!
            : DefaultSettings.defaultSaveMapLaunchFile;

    final String? saveMapArgsJson = prefs.getString('$settingsKey:saveMapArgs');
    if (saveMapArgsJson != null) {
      List<dynamic> argsList = json.decode(saveMapArgsJson);
      _saveMapArgs = List<Map<String, String>>.from(
          argsList.map((item) => Map<String, String>.from(item)));
    }

    // Load lidar topic and enabled status
    _lidarTopic = prefs.getString('$settingsKey:lidarTopic') != null
        ? prefs.getString('$settingsKey:lidarTopic')!
        : DefaultSettings.defaultLidarTopic;

    // Load communication timeout
    _communicationTimeout = prefs.getInt('$settingsKey:communicationTimeout') ??
        DefaultSettings.defaultCommunicationTimeout;

    // Load visibility settings
    _cameraVisible = prefs.getBool('$settingsKey:cameraVisible') ??
        DefaultSettings.defaultCameraVisible;
    _joystickVisible = prefs.getBool('$settingsKey:joystickVisible') ??
        DefaultSettings.defaultJoystickVisible;

    // Load path topic
    _pathTopic = prefs.getString('$settingsKey:pathTopic') != null
        ? prefs.getString('$settingsKey:pathTopic')!
        : DefaultSettings.defaultPathTopic;

    // Load bookmarks
    final String? bookmarksJson = prefs.getString('$settingsKey:bookmarks');
    if (bookmarksJson != null) {
      final Map<String, dynamic> bookmarksMap = json.decode(bookmarksJson);
      _bookmarks = {
        for (var entry in bookmarksMap.entries)
          entry.key: (entry.value as List)
              .map((bookmarkJson) => Bookmark.fromJson(bookmarkJson))
              .toList(),
      };
    }

    // Load bookmarks visibility
    _bookmarksVisible = prefs.getBool('$settingsKey:bookmarksVisible') ??
        DefaultSettings.defaultBookmarksVisible;

    // Load missions
    final String? missionsJson = prefs.getString('$settingsKey:missions');
    if (missionsJson != null) {
      final Map<String, dynamic> missionsMap = json.decode(missionsJson);
      _missions = {
        for (var entry in missionsMap.entries)
          entry.key: Mission.fromJson(entry.value)
      };
    }

    notifyListeners();
  }

  // Save settings to shared preferences
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsKey = 'settings_$robotId';
    await prefs.setString('$settingsKey:cmdVelTopic', _cmdVelTopic);
    await prefs.setDouble('$settingsKey:linearVelocity', _linearVelocity);
    await prefs.setDouble('$settingsKey:angularVelocity', _angularVelocity);
    await prefs.setString('$settingsKey:twistType', _twistType);
    await prefs.setString('$settingsKey:mapsPath', _mapsPath);
    await prefs.setString('$settingsKey:mappingLaunchFile', _mappingLaunchFile);
    await prefs.setString('$settingsKey:mappingOdomTopic', _mappingOdomTopic);
    await prefs.setString(
        '$settingsKey:mappingOdomTopicType', _mappingOdomTopicType);
    await prefs.setString(
        '$settingsKey:navigationLaunchFile', _navigationLaunchFile);
    await prefs.setString(
        '$settingsKey:navigationOdomTopic', _navigationOdomTopic);
    await prefs.setString(
        '$settingsKey:navigationOdomTopicType', _navigationOdomTopicType);
    await prefs.setString(
        '$settingsKey:mappingArgs', json.encode(_mappingArgs));
    await prefs.setString(
        '$settingsKey:navigationArgs', json.encode(_navigationArgs));
    await prefs.setString('$settingsKey:cameraImageTopic', _cameraImageTopic);
    await prefs.setBool('$settingsKey:cameraEnabled', _cameraEnabled);
    await prefs.setString('$settingsKey:odomTopic', _odomTopic);
    await prefs.setString('$settingsKey:odomTopicType', _odomTopicType);
    await prefs.setString('$settingsKey:saveMapLaunchFile', _saveMapLaunchFile);
    await prefs.setString(
        '$settingsKey:saveMapArgs', json.encode(_saveMapArgs));
    await prefs.setString('$settingsKey:lidarTopic', _lidarTopic);
    await prefs.setInt(
        '$settingsKey:communicationTimeout', _communicationTimeout);
    await prefs.setBool('$settingsKey:cameraVisible', _cameraVisible);
    await prefs.setBool('$settingsKey:joystickVisible', _joystickVisible);
    await prefs.setString('$settingsKey:pathTopic', _pathTopic);
    await prefs.setString(
        '$settingsKey:bookmarks',
        json.encode({
          for (var entry in _bookmarks.entries)
            entry.key:
                entry.value.map((bookmark) => bookmark.toJson()).toList(),
        }));
    await prefs.setBool('$settingsKey:bookmarksVisible', _bookmarksVisible);
    await prefs.setString(
      '$settingsKey:missions',
      json.encode({
        for (var entry in _missions.entries) entry.key: entry.value.toJson()
      }),
    );
  }

  // Setters with validation
  void setCmdVelTopic(String topic) {
    _cmdVelTopic = topic.trim();
    _saveSettings(); // Save after updating
    notifyListeners();
  }

  void setTwistType(String type) {
    if (DefaultSettings.availableTwistTypes.contains(type)) {
      _twistType = type;
      _saveSettings();
      notifyListeners();
    }
  }

  void setLinearVelocity(double velocity) {
    _linearVelocity = velocity.clamp(
      DefaultSettings.minVelocity,
      DefaultSettings.maxVelocity,
    );
    _saveSettings(); // Save after updating
    notifyListeners();
  }

  void setAngularVelocity(double velocity) {
    _angularVelocity = velocity.clamp(
      DefaultSettings.minVelocity,
      DefaultSettings.maxVelocity,
    );
    _saveSettings(); // Save after updating
    notifyListeners();
  }

  // Helper methods for step increment/decrement
  void incrementLinearVelocity() {
    setLinearVelocity(_linearVelocity + DefaultSettings.velocityStep);
  }

  void decrementLinearVelocity() {
    setLinearVelocity(_linearVelocity - DefaultSettings.velocityStep);
  }

  void incrementAngularVelocity() {
    setAngularVelocity(_angularVelocity + DefaultSettings.velocityStep);
  }

  void decrementAngularVelocity() {
    setAngularVelocity(_angularVelocity - DefaultSettings.velocityStep);
  }

  // Mapping Setters
  void setMapsPath(String path) {
    _mapsPath = path.trim();
    _saveSettings(); // Save after updating
    notifyListeners();
  }

  void setMappingLaunchFile(String file) {
    _mappingLaunchFile = file.trim();
    _saveSettings(); // Save after updating
    notifyListeners();
  }

  void setMappingOdomTopic(String topic, String type) {
    _mappingOdomTopic = topic;
    _mappingOdomTopicType = type;
    _saveSettings();
    notifyListeners();
  }

  void addMappingArg(String name, String value) {
    // Only add argument if both name and value are not empty
    final trimmedName = name.trim();
    final trimmedValue = value.trim();
    if (trimmedName.isNotEmpty || trimmedValue.isNotEmpty) {
      _mappingArgs.add({'name': trimmedName, 'value': trimmedValue});
      _saveSettings(); // Save after updating
      notifyListeners();
    }
  }

  void removeMappingArg(int index) {
    if (index >= 0 && index < _mappingArgs.length) {
      _mappingArgs.removeAt(index);
      _saveSettings(); // Save after updating
      notifyListeners();
    }
  }

  void updateMappingArg(int index, String name, String value) {
    if (index >= 0 && index < _mappingArgs.length) {
      _mappingArgs[index] = {'name': name.trim(), 'value': value.trim()};
      _saveSettings(); // Save after updating
      notifyListeners();
    }
  }

  // Navigation Setters
  void setNavigationLaunchFile(String file) {
    _navigationLaunchFile = file.trim();
    _saveSettings(); // Save after updating
    notifyListeners();
  }

  void setNavigationOdomTopic(String topic, String type) {
    _navigationOdomTopic = topic;
    _navigationOdomTopicType = type;
    _saveSettings();
    notifyListeners();
  }

  void addNavigationArg(String name, String value) {
    // Only add argument if both name and value are not empty
    final trimmedName = name.trim();
    final trimmedValue = value.trim();
    if (trimmedName.isNotEmpty || trimmedValue.isNotEmpty) {
      _navigationArgs.add({'name': trimmedName, 'value': trimmedValue});
      _saveSettings(); // Save after updating
      notifyListeners();
    }
  }

  void removeNavigationArg(int index) {
    if (index >= 0 && index < _navigationArgs.length) {
      _navigationArgs.removeAt(index);
      _saveSettings(); // Save after updating
      notifyListeners();
    }
  }

  void updateNavigationArg(int index, String name, String value) {
    if (index >= 0 && index < _navigationArgs.length) {
      _navigationArgs[index] = {'name': name.trim(), 'value': value.trim()};
      _saveSettings(); // Save after updating
      notifyListeners();
    }
  }

  // General Setters
  void setCameraImageTopic(String topic) {
    _cameraImageTopic = topic.trim();
    _saveSettings();
    notifyListeners();
  }

  // Add new setter
  void setCameraEnabled(bool enabled) {
    _cameraEnabled = enabled;
    _saveSettings();
    notifyListeners();
  }

  // Add new setters
  void setOdomTopic(String topic, String topicType) {
    _odomTopic = topic.trim();
    _odomTopicType = topicType.trim();
    _saveSettings();
    notifyListeners();
  }

  // Save Map Configuration Setters
  void setSaveMapLaunchFile(String file) {
    _saveMapLaunchFile = file.trim();
    _saveSettings();
    notifyListeners();
  }

  void addSaveMapArg(String name, String value) {
    // Only add argument if both name and value are not empty
    final trimmedName = name.trim();
    final trimmedValue = value.trim();
    if (trimmedName.isNotEmpty || trimmedValue.isNotEmpty) {
      _saveMapArgs.add({'name': trimmedName, 'value': trimmedValue});
      _saveSettings();
      notifyListeners();
    }
  }

  void removeSaveMapArg(int index) {
    if (index >= 0 && index < _saveMapArgs.length) {
      _saveMapArgs.removeAt(index);
      _saveSettings();
      notifyListeners();
    }
  }

  void updateSaveMapArg(int index, String name, String value) {
    if (index >= 0 && index < _saveMapArgs.length) {
      _saveMapArgs[index] = {'name': name.trim(), 'value': value.trim()};
      _saveSettings();
      notifyListeners();
    }
  }

  // Lidar Setters
  void setLidarTopic(String topic) {
    _lidarTopic = topic.trim();
    _saveSettings();
    notifyListeners();
  }

  // Communication timeout setter
  void setCommunicationTimeout(int timeoutSeconds) {
    if (timeoutSeconds >= 0) {
      _communicationTimeout = timeoutSeconds;
      _saveSettings();
      notifyListeners();
    }
  }

  void toggleCameraVisibility() {
    _cameraVisible = !_cameraVisible;
    notifyListeners();
  }

  void toggleJoystickVisibility() {
    _joystickVisible = !_joystickVisible;
    notifyListeners();
  }

  // Path Topic Setter
  void setPathTopic(String topic) {
    _pathTopic = topic.trim();
    _saveSettings();
    notifyListeners();
  }

  void addBookmark(IconData icon, String mapName, String name, double x,
      double y, double z, double theta) {
    if (!_bookmarks.containsKey(mapName)) {
      _bookmarks[mapName] = []; // Create a new list if no mapName exists
    }
    _bookmarks[mapName]!.add(
      Bookmark(
        id: Uuid().v4(),
        icon: icon,
        name: name,
        positionX: x,
        positionY: y,
        positionZ: z,
        theta: theta,
      ),
    );
    _saveSettings();
    notifyListeners();
  }

  void removeBookmark(String mapName, int index) {
    if (_bookmarks.containsKey(mapName)) {
      if (index >= 0 && index < _bookmarks[mapName]!.length) {
        _bookmarks[mapName]!.removeAt(index);
        _saveSettings();
        notifyListeners();
      }
    }
  }

  // Add method to toggle bookmarks visibility
  void toggleBookmarksVisibility() {
    _bookmarksVisible = !_bookmarksVisible;
    _saveSettings();
    notifyListeners();
  }

  // Add these new methods
  void saveMission(Mission mission) {
    final uniqueKey = '${mission.mapName}::${mission.missionName}';

    // Check if mission name already exists for this map
    final existingMissionForMap = _missions.entries
        .where((entry) =>
            entry.value.mapName == mission.mapName &&
            entry.value.missionName == mission.missionName)
        .firstOrNull;

    // If it exists, remove the old entry first
    if (existingMissionForMap != null) {
      _missions.remove(existingMissionForMap.key);
    }

    _missions[uniqueKey] = mission;
    _saveSettings();
    notifyListeners();
  }

  void deleteMission(String mapName, String missionName) {
    final keyToRemove = _missions.entries
        .where((entry) =>
            entry.value.mapName == mapName &&
            entry.value.missionName == missionName)
        .firstOrNull
        ?.key;

    if (keyToRemove != null) {
      _missions.remove(keyToRemove);
      _saveSettings();
      notifyListeners();
    }
  }

  // Add helper method to get missions for a specific map
  Map<String, Mission> getMissionsForMap(String mapName) {
    return Map.fromEntries(
        _missions.entries.where((entry) => entry.value.mapName == mapName));
  }

  // Add helper method to check if mission name exists for a map
  bool missionExistsForMap(String mapName, String missionName) {
    return _missions.values.any((mission) =>
        mission.mapName == mapName && mission.missionName == missionName);
  }

  // Add this method to remove bookmarks from all missions
  void removeBookmarkFromAllMissions(Bookmark bookmark) {
    // 1. Remove bookmark from all missions' waypoints
    _missions.forEach((key, mission) {
      mission.waypoints
          .removeWhere((waypoint) => waypoint.bookmarkId == bookmark.id);
    });

    // 2. Remove from bookmarks storage
    _bookmarks.forEach((mapName, bookmarks) {
      bookmarks.removeWhere((b) => b.id == bookmark.id);
    });

    // 3. Update navigation screen
    _saveSettings();
    notifyListeners();
  }

  // Add this method to delete robot-specific settings
  static Future<void> deleteRobotSettings(String robotId) async {
    final prefs = await SharedPreferences.getInstance();
    final settingsKey = 'settings_$robotId';

    // List of all setting keys that use the robot-specific prefix
    final keysToDelete = [
      '$settingsKey:cmdVelTopic',
      '$settingsKey:linearVelocity',
      '$settingsKey:angularVelocity',
      '$settingsKey:mapsPath',
      '$settingsKey:mappingLaunchFile',
      '$settingsKey:mappingOdomTopic',
      '$settingsKey:mappingOdomTopicType',
      '$settingsKey:navigationLaunchFile',
      '$settingsKey:navigationOdomTopic',
      '$settingsKey:navigationOdomTopicType',
      '$settingsKey:mappingArgs',
      '$settingsKey:navigationArgs',
      '$settingsKey:cameraImageTopic',
      '$settingsKey:cameraEnabled',
      '$settingsKey:odomTopic',
      '$settingsKey:odomTopicType',
      '$settingsKey:saveMapLaunchFile',
      '$settingsKey:saveMapArgs',
      '$settingsKey:lidarTopic',
      '$settingsKey:communicationTimeout',
      '$settingsKey:cameraVisible',
      '$settingsKey:joystickVisible',
      '$settingsKey:pathTopic',
      '$settingsKey:bookmarks',
      '$settingsKey:bookmarksVisible',
      '$settingsKey:missions',
    ];

    // Remove all robot-specific settings
    for (String key in keysToDelete) {
      await prefs.remove(key);
    }
  }

  // Add public method to force save settings (for debugging)
  Future<void> forceSaveSettings() async {
    await _saveSettings();
    notifyListeners();
  }

  // Add public method to reload settings from storage (for debugging)
  Future<void> reloadSettings() async {
    await _loadSettings();
  }

  // Add debug method to debugPrint all current settings
  void debugPrintSettings() {
    // Debug method - can be used for debugging if needed
  }

  // Add method to update robot ID without recreating the provider
  Future<void> updateRobotId(String newRobotId) async {
    if (robotId != newRobotId) {
      robotId = newRobotId;
      await _loadSettings();
      notifyListeners();
    }
  }
}
