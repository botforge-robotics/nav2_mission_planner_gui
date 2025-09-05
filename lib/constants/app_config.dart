class AppConfig {
  // App Check Configuration
  static const bool enableAppCheck = true;

  // App Check token refresh settings
  static const int tokenRefreshIntervalMinutes =
      30; // Refresh token every 30 minutes
  static const int minFetchIntervalSeconds =
      5; // Minimum 5 seconds between token fetches

  // Firebase Cloud Functions URL
  static const String cloudFunctionsUrl =
      'https://us-central1-nav2-mission-planner.cloudfunctions.net';

  // Google Sign-In
  static const String webClientId = '';

  // Product IDs for in-app purchases
  static const String individualLifetimeProductId = 'n2mp_individual_life';

  // Feature cards for license screens background
  static const List<Map<String, dynamic>> featureCards = [
    {
      'title': 'Teleoperation',
      'description': 'Manually control your robot using intuitive interface.',
      'icon': 'gamepad',
      'iconType': 'fontAwesome',
    },
    {
      'title': 'Navigation',
      'description': 'Set and follow goals with full nav2 support.',
      'icon': 'compass',
      'iconType': 'fontAwesome',
    },
    {
      'title': 'Bookmarks',
      'description': 'Bookmark reusable locations for quick access.',
      'icon': 'map-pin',
      'iconType': 'fontAwesome',
    },
    {
      'title': 'Trigger Services',
      'description': 'Call ROS services at mission waypoints.',
      'icon': 'bolt',
      'iconType': 'fontAwesome',
    },
    {
      'title': 'Call Actions',
      'description': 'Execute ROS action goals during mission execution.',
      'icon': 'bolt',
      'iconType': 'fontAwesome',
    },
    {
      'title': 'Capture Images',
      'description': 'Take photos at specific waypoints.',
      'icon': 'camera',
      'iconType': 'fontAwesome',
    },
    {
      'title': 'Mapping',
      'description': 'Visualise, build & Save occupancy grid map.',
      'icon': 'map',
      'iconType': 'fontAwesome',
    },
    {
      'title': 'Mission',
      'description': 'Design reusable missions with waypoints and actions.',
      'icon': 'rocket',
      'iconType': 'fontAwesome',
    },
    {
      'title': 'Multi-Robot',
      'description': 'Save multiple robot configurations.',
      'icon': 'robot',
      'iconType': 'fontAwesome',
    },
    {
      'title': 'Publish Topics',
      'description': 'Send messages to ROS topics during missions.',
      'icon': 'satellite-dish',
      'iconType': 'fontAwesome',
    },
  ];
}
