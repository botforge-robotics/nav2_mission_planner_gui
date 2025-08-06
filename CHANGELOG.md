# Nav2 Mission Planner - Changelog

## [1.2.2] - 2024-12-19

### 🔧 Android 15 Compatibility

- **Edge-to-edge support**: Added proper edge-to-edge display support for Android 15
- **SDK 35 targeting**: Updated to target Android SDK 35 for full Android 15 compatibility
- **16KB alignment**: Enabled 16KB native library alignment for improved performance on Android 15 devices
- **Deprecated API migration**: Removed deprecated system UI APIs in favor of modern edge-to-edge APIs

### 🛠️ Technical Improvements

- **Updated MainActivity**: Added `WindowCompat.setDecorFitsSystemWindows()` for edge-to-edge support
- **Modern system UI**: Replaced deprecated `SystemUiMode.immersiveSticky` with `SystemUiMode.edgeToEdge`
- **Transparent system bars**: Configured transparent status and navigation bars for seamless edge-to-edge experience
- **Enhanced packaging**: Added `useLegacyPackaging = false` for 16KB alignment support

### 📱 User Experience

- **Better Android 15 support**: Full compatibility with latest Android version
- **Improved performance**: 16KB alignment provides better performance on supported devices
- **Modern UI**: Edge-to-edge display provides more immersive experience
- **Future-proof**: Ready for Android 15 and beyond

## [1.2.1] - 2024-12-19

### 🎨 UI Layout Improvements

- **Consistent layout across all screen sizes**: Welcome and License Activation screens now always use Row layout (left/right) instead of responsive Column/Row switching
- **Fixed first install trial display**: Corrected trial status detection to show "Trial Available" instead of "Continue Trial" on first install
- **Improved user experience**: More predictable and consistent UI behavior across different devices and screen sizes

### 🔧 Technical Fixes

- **Fixed trial remaining days calculation**: Corrected `getTrialRemainingDays()` to return 0 instead of 7 when no trial has been started
- **Fixed 404 handler message**: Updated device registration 404 handler to show proper trial available message
- **Enhanced trial status detection**: Improved logic for determining whether to show "Start Free Trial" vs "Continue Trial"

### 📱 User Experience

- **Consistent trial flow**: First-time users now see the correct "Trial Available" message and "Start Free Trial" button
- **Better layout consistency**: All license screens now maintain the same left/right layout regardless of screen size
- **Improved onboarding**: More intuitive trial activation process for new users

## [1.2.0] - 2024-12-19

### 🔧 Technical Improvements

- **Simplified device identification**: Direct use of MediaDRM Widevine ID for device identification
- **Removed complex hashing**: Eliminated unnecessary cryptographic operations for cleaner implementation
- **Enhanced stability**: More reliable device fingerprinting using hardware-based identifiers
- **Cleaner codebase**: Removed all debug print statements for production-ready code

### 🧹 Code Quality

- **Removed debug logging**: Cleaned up all debug print statements for production-ready code
- **Optimized performance**: Improved memory usage and overall app performance
- **Enhanced code structure**: Better organization and maintainability

### 📱 User Experience

- **Cleaner console output**: Removed all debug messages for professional appearance
- **More reliable device identification**: Better license and trial management
- **Improved performance**: Faster device ID generation and reduced memory usage

## [1.1.0] - 2024-12-19

### 🐛 Bug Fixes

- **Fixed settings persistence issues**: Resolved critical bug where user-entered settings in Robot Setup Wizard were not being saved correctly
- **Improved robot connection reliability**: Enhanced connection handling to prevent settings loss during robot switching
- **Fixed robot ID management**: Corrected issue where settings were being saved to wrong robot ID
- **Enhanced error handling**: Improved error handling across all components for better stability

### 🔧 Technical Improvements

- **Enhanced device identification**: Replaced unstable Android ID with MediaDRM Widevine ID for more reliable device identification
- **Added native MediaDRM implementation**: Created platform-specific MediaDRM helper for stable device fingerprinting
- **Simplified device ID generation**: Now directly uses Widevine ID as device identifier with Android ID as fallback
- **Removed complex hashing**: Eliminated unnecessary cryptographic operations for cleaner implementation

### 🧹 Code Quality

- **Removed debug logging**: Cleaned up all debug print statements for production-ready code
- **Optimized performance**: Improved memory usage and overall app performance
- **Enhanced code structure**: Better organization and maintainability

### 🔧 Technical Improvements

- **Settings provider optimization**: Fixed `_loadSettings()` method to properly handle empty strings vs null values
- **Robot setup wizard fixes**: Corrected `_completeSetup()` method to update robot ID before applying settings
- **Connection provider enhancements**: Improved new robot creation logic to always create new robots even with same IP
- **Argument handling**: Fixed launch file argument handling to not add empty arguments

### 📱 User Experience

- **Cleaner console output**: Removed all debug messages for professional appearance
- **More reliable settings**: Settings now persist correctly across app sessions
- **Better robot management**: Improved handling of multiple robots with same IP addresses

### 🔒 Stability

- **Enhanced error recovery**: Better handling of connection failures and edge cases
- **Improved state management**: More reliable widget lifecycle management
- **Memory optimization**: Reduced memory leaks and improved resource usage

## [1.0.1] - 2024-12-18

### 🐛 Bug Fixes

- Fixed icon tree-shaking issues for Android release builds
- Resolved Android Gradle Plugin version compatibility
- Fixed keystore configuration for app signing
- Corrected R8/ProGuard rules for proper code shrinking

### 🔧 Technical Improvements

- Updated Gradle wrapper to version 8.4
- Enhanced ProGuard rules for better code optimization
- Improved Android build configuration

## [1.0.0] - 2024-12-17

### 🚀 Initial Release

- Complete ROS2 navigation mission planning application
- Support for TurtleBot4, TurtleBot3, and custom robots
- Real-time mapping and navigation capabilities
- Mission planning with waypoints and actions
- Camera integration and video streaming
- Professional-grade robot control interface

### ✨ Key Features

- Intuitive mission planning interface
- Real-time occupancy grid visualization
- Multi-robot support with individual settings
- Advanced teleoperation controls
- Bookmark and waypoint management
- Export/import capabilities for missions
