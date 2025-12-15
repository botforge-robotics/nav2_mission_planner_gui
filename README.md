# Nav2 Mission Planner

A comprehensive cross-platform ROS2 navigation mission planning application built with Flutter. Nav2 Mission Planner provides an intuitive interface for connecting to ROS2 robots, performing teleoperation, mapping, and navigation tasks. The app supports **Linux**, **Windows**, and **Android** platforms.

## 📱 App Showcase

![Nav2 Mission Planner Screenshot 1](https://raw.githubusercontent.com/botforge-robotics/nav2_mission_planner/refs/heads/jazzy/images/mockup1.jpg)
![Nav2 Mission Planner Screenshot 2](https://raw.githubusercontent.com/botforge-robotics/nav2_mission_planner/refs/heads/jazzy/images/mockup2.jpg)
![Nav2 Mission Planner Screenshot 3](https://raw.githubusercontent.com/botforge-robotics/nav2_mission_planner/refs/heads/jazzy/images/mockup3.jpg)

## 📱 Download App

**Download Nav2 Mission Planner:**

- 🚀 **Android (Compiled App)**: [Download from Google Play Store](https://play.google.com/store/apps/details?id=com.botforge.nav2missionplanner)
- 💻 **Android/Linux/Windows**: Build from source (see [Building from Source](#building-from-source) section below)
- 🔧 **Features**: ROS 2 Mapping, Navigation, Mission Planning, Teleoperation
- 🌐 **Support**: Email support available

## Features

- **Robot Connection**: Connect to ROS2 robots via WebSocket (rosbridge)
- **Teleoperation**: Real-time robot control with intuitive joystick interface
- **Mapping**: Create and manage SLAM maps using your robot's sensors
- **Navigation**: Plan and execute navigation missions with waypoints and patterns
- **Mission Planning**: Create complex navigation patterns including loops, grids, and custom paths
- **Settings Management**: Configure robot-specific settings including topics, frames, and sensor parameters
- **Multi-Robot Support**: Manage multiple robot configurations

## Installation

### Install Compiled Android App

The compiled Android app is available on the Google Play Store:

**[📱 Download from Google Play Store](https://play.google.com/store/apps/details?id=com.botforge.nav2missionplanner)**

**▶️ Watch Installation Tutorial**

[![Installation Video Tutorial](https://raw.githubusercontent.com/botforge-robotics/nav2_mission_planner/refs/heads/jazzy/images/youtubeThumbail.png)](https://www.youtube.com/watch?v=I7syq--gEf4&feature=youtu.be)

### Robot Setup

For robot setup and configuration instructions, please visit:

**[🤖 Robot Setup Guide](https://github.com/botforge-robotics/nav2_mission_planner)**

### Building from Source

Nav2 Mission Planner is built with Flutter and supports cross-platform development for **Linux**, **Windows**, and **Android**.

1. **Prerequisites**:

   - Flutter SDK (3.6.1 or later)
   - For Android: Android Studio or VS Code with Flutter extensions, Android SDK (API 24 or higher)
   - For Linux: Linux development tools
   - For Windows: Windows development tools

2. **Clone the repository**:

   ```bash
   git clone https://github.com/botforge-robotics/nav2_mission_planner.git
   cd nav2_mission_planner
   ```

3. **Install dependencies**:

   ```bash
   flutter pub get
   ```

4. **Build the app**:

   **For Android:**

   ```bash
   flutter build apk --release
   # Or for app bundle:
   flutter build appbundle --release
   ```

   **For Linux:**

   ```bash
   flutter build linux --release
   ```

   **For Windows:**

   ```bash
   flutter build windows --release
   ```

5. **Install/Run**:

   **Android:**

   ```bash
   flutter install
   ```

   **Linux/Windows:**

   ```bash
   # Run directly
   flutter run -d linux
   # or
   flutter run -d windows

   # Or install the built executable from build/linux/release/ or build/windows/release/
   ```

## Usage

### Connecting to a Robot

1. Launch the app on your mobile device
2. Enter your robot's IP address and port (default: 9090)
3. Optionally provide a name for the robot
4. Tap "Connect"

### First-Time Setup

When connecting to a robot for the first time, you'll be guided through a setup wizard to configure:

- Camera topics
- TF (Transform) topics and frames
- Lidar topics
- Other sensor configurations

### Teleoperation

- Use the joystick interface to control your robot
- Adjust speed and rotation sensitivity in settings
- Switch between different control modes

### Mapping

- Start a mapping session to create SLAM maps
- Visualize the map in real-time
- Save maps for later use

### Navigation

- Plan missions with waypoints
- Use predefined patterns (loops, grids, etc.)
- Execute navigation missions
- Monitor robot progress in real-time

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute to this project.

### Areas for Contribution

- Bug fixes and improvements
- New features and functionality
- Documentation improvements
- UI/UX enhancements
- Testing and quality assurance

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Community

- **Issues**: Report bugs or request features on [GitHub Issues](https://github.com/botforge-robotics/nav2_mission_planner/issues)
- **Discussions**: Join discussions on [GitHub Discussions](https://github.com/botforge-robotics/nav2_mission_planner/discussions)
- **Repository**: [GitHub Repository](https://github.com/botforge-robotics/nav2_mission_planner)

## Code of Conduct

This project adheres to a Code of Conduct. Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before participating.

## Credits

- Built with Flutter (cross-platform: Linux, Windows, Android)
- ROS2 integration via rosbridge
- Community contributors

## Acknowledgments

Special thanks to the ROS2 and Flutter communities for their excellent tools and support.
