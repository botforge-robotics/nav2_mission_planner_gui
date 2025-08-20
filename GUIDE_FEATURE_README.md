# Guide Feature - First-Time User Highlight

## Overview

The Guide Feature provides first-time users with helpful highlights and easy access to the [Nav2 Mission Planner GitHub repository](https://github.com/botforge-robotics/nav2_mission_planner) for setup instructions and configuration details.

## Features

### 🎯 **First-Time Highlight**

- **Automatic Display**: Shows only for first-time users
- **Animated Highlight**: Pulsing blue highlight with glow effect
- **Clear Message**: "Click here for setup instructions and robot configuration guide"
- **Dismissible**: Users can click the X to dismiss the highlight

### 📚 **Guide Icon**

- **Permanent Placement**: Always visible in bottom-left corner
- **Professional Design**: Circular background with book icon
- **Easy Access**: One tap to open guide information
- **Testing Support**: Long press to reset guide for testing

### 🔗 **Guide Integration**

- **GitHub Repository**: Direct link to [botforge-robotics/nav2_mission_planner](https://github.com/botforge-robotics/nav2_mission_planner)
- **Setup Instructions**: Comprehensive robot configuration guide
- **Launch Files**: Required wrapper launch file templates
- **Troubleshooting**: Common issues and solutions

## Implementation Details

### **Files Created/Modified**

1. **`lib/services/guide_service.dart`** - Manages guide state persistence
2. **`lib/widgets/guide_highlight_widget.dart`** - Animated highlight widget
3. **`lib/services/guide_launcher_service.dart`** - Handles guide URL operations
4. **`lib/screens/connection_screen.dart`** - Integrated guide icon and highlight

### **Guide States**

- **`GuideIds.connectionGuide`** - Connection screen guide
- **`GuideIds.teleopGuide`** - Teleoperation guide (future)
- **`GuideIds.mappingGuide`** - Mapping guide (future)
- **`GuideIds.navigationGuide`** - Navigation guide (future)
- **`GuideIds.missionGuide`** - Mission planning guide (future)
- **`GuideIds.settingsGuide`** - Settings guide (future)

### **Storage Keys**

- **`guide_shown_connection_guide`** - Connection guide shown status
- **`guide_shown_teleop_guide`** - Teleop guide shown status
- **`guide_shown_mapping_guide`** - Mapping guide shown status
- **`guide_shown_navigation_guide`** - Navigation guide shown status
- **`guide_shown_mission_guide`** - Mission guide shown status
- **`guide_shown_settings_guide`** - Settings guide shown status

## Usage

### **For Users**

1. **First Visit**: See animated highlight with setup instructions
2. **Click Guide Icon**: Opens detailed guide dialog
3. **Copy Guide URL**: URL copied to clipboard for easy access
4. **Dismiss Highlight**: Click X to hide highlight (won't show again)
5. **Access Guide**: Guide icon remains for future reference

### **For Developers**

#### **Adding Guide to New Screen**

```dart
import '../services/guide_service.dart';
import '../services/guide_launcher_service.dart';
import '../widgets/guide_highlight_widget.dart';

// In your screen's build method
Positioned(
  left: 16,
  bottom: 16,
  child: FutureBuilder<bool>(
    future: GuideService.isGuideShown(GuideIds.yourGuideId),
    builder: (context, snapshot) {
      final showHighlight = !(snapshot.data ?? false);
      return GuideHighlightWidget(
        onTap: () => _showYourGuide(context),
        onLongPress: () => _resetYourGuide(context),
        guideUrl: 'https://github.com/botforge-robotics/nav2_mission_planner',
        showHighlight: showHighlight,
        highlightMessage: 'Your custom guide message',
        icon: FontAwesomeIcons.yourIcon,
        iconColor: Colors.blue.shade400,
        size: 32.0,
        padding: const EdgeInsets.all(12.0),
      );
    },
  ),
),
```

#### **Creating Guide Method**

```dart
Future<void> _showYourGuide(BuildContext context) async {
  await GuideService.markGuideAsShown(GuideIds.yourGuideId);

  await GuideLauncherService.showGuideDialog(
    context,
    title: 'Your Guide Title',
    content: 'Your guide content with helpful information.',
    actionLabel: 'Copy Guide URL',
    onAction: () async {
      await GuideLauncherService.launchNav2Guide();
      // Show success message
    },
  );
}

Future<void> _resetYourGuide(BuildContext context) async {
  await GuideService.resetGuide(GuideIds.yourGuideId);
  setState(() {});
}
```

#### **Adding New Guide ID**

```dart
// In lib/services/guide_service.dart
class GuideIds {
  // ... existing guides
  static const String yourNewGuide = 'your_new_guide';
}
```

## Testing

### **Reset Guide for Testing**

1. **Long Press**: Long press the guide icon
2. **Reset Message**: "Guide reset! Highlight will show again."
3. **Highlight Returns**: Animated highlight reappears
4. **Test Flow**: Verify highlight, tap, and dismiss functionality

### **Reset All Guides**

```dart
// In development/testing
await GuideService.resetAllGuides();
```

### **Check Guide Status**

```dart
// Check if specific guide shown
final isShown = await GuideService.isGuideShown(GuideIds.connectionGuide);

// Get all shown guides
final shownGuides = await GuideService.getShownGuides();

// Check if any guides shown
final hasAnyShown = await GuideService.hasAnyGuidesBeenShown();
```

## Customization

### **Visual Customization**

- **Icon**: Change `icon` parameter to any FontAwesome icon
- **Color**: Modify `iconColor` for different theme colors
- **Size**: Adjust `size` parameter for different icon sizes
- **Padding**: Customize `padding` for positioning

### **Message Customization**

- **Highlight Message**: Update `highlightMessage` for context-specific text
- **Dialog Content**: Modify guide dialog content in `_showYourGuide` method
- **Action Label**: Change button text in guide dialog

### **Animation Customization**

- **Pulse Duration**: Modify `Duration(seconds: 2)` in guide highlight widget
- **Glow Effect**: Adjust `blurRadius` and `spreadRadius` values
- **Scale Range**: Change `begin: 1.0, end: 1.2` for different pulse intensity

## Future Enhancements

### **Planned Features**

1. **Multiple Guide Types**: Different highlight styles for different guide types
2. **Interactive Tutorials**: Step-by-step in-app tutorials
3. **Video Guides**: Embedded video content
4. **Progressive Disclosure**: Show guides based on user progress
5. **Localization**: Multi-language guide support

### **Integration Opportunities**

1. **Onboarding Flow**: Integrate with app onboarding process
2. **Help System**: Connect with in-app help and support
3. **User Analytics**: Track guide usage and effectiveness
4. **Feedback System**: Collect user feedback on guide helpfulness

## Troubleshooting

### **Common Issues**

1. **Highlight Not Showing**: Check if guide was previously marked as shown
2. **Guide Icon Missing**: Verify widget is properly positioned in screen layout
3. **Animation Issues**: Check for animation controller conflicts
4. **Storage Errors**: Verify SharedPreferences permissions and initialization

### **Debug Commands**

```dart
// Debug guide service
final allGuides = await GuideService.getShownGuides();
print('Shown guides: $allGuides');

// Reset specific guide
await GuideService.resetGuide(GuideIds.connectionGuide);

// Reset all guides
await GuideService.resetAllGuides();
```

## Support

For issues or questions about the Guide Feature:

1. **Check Logs**: Look for guide service debug messages
2. **Verify Storage**: Ensure SharedPreferences is working
3. **Test Reset**: Use long press to reset guide for testing
4. **Review Code**: Check guide widget integration in screen

## Contributing

To add new guides or improve existing ones:

1. **Follow Pattern**: Use existing guide structure and naming conventions
2. **Test Thoroughly**: Verify highlight, tap, and dismiss functionality
3. **Update Documentation**: Add new guide IDs and usage examples
4. **Consider UX**: Ensure guide placement doesn't interfere with app functionality
