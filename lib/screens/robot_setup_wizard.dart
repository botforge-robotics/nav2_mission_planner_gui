import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/branding_provider.dart';
import '../modals/robotProfile.dart';
import '../constants/default_settings.dart';
import 'home_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class RobotSetupWizard extends StatefulWidget {
  final RobotProfile robot;

  const RobotSetupWizard({super.key, required this.robot});

  @override
  State<RobotSetupWizard> createState() => _RobotSetupWizardState();
}

class _RobotSetupWizardState extends State<RobotSetupWizard>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  late AnimationController _progressAnimationController;

  int _currentStep = 0;
  final int _totalSteps = 4;

  // Temporary settings storage
  final Map<String, dynamic> _tempSettings = {};

  // Validation states
  final Map<int, bool> _stepValidations = {
    0: true, // Sensor (can use defaults, camera optional)
    1: true, // Teleop (can use defaults)
    2: false, // Mapping (required)
    3: false, // Navigation (required)
  };

  List<StepConfig> get _steps {
    final brandingProvider =
        Provider.of<BrandingProvider>(context, listen: false);
    return [
      StepConfig(
        title: 'Sensor Configuration',
        subtitle: 'Robot sensor settings',
        icon: FontAwesomeIcons.gear,
        color: brandingProvider.themeColor,
      ),
      StepConfig(
        title: 'Teleoperation Setup',
        subtitle: 'Movement and control parameters',
        icon: FontAwesomeIcons.gamepad,
        color: brandingProvider.themeColor,
      ),
      StepConfig(
        title: 'Mapping Configuration',
        subtitle: 'SLAM and mapping settings',
        icon: FontAwesomeIcons.map,
        color: brandingProvider.themeColor,
      ),
      StepConfig(
        title: 'Navigation Setup',
        subtitle: 'Path planning and navigation',
        icon: FontAwesomeIcons.route,
        color: brandingProvider.themeColor,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _initializeTempSettings();
    _updateProgress();

    // If the camera option is already enabled (e.g., user navigated back to
    // this wizard) ensure the required storage permission is granted before
    // the mission or any camera stream starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tempSettings['cameraEnabled'] == true) {
        _handleCameraToggle(true);
      }
    });
  }

  void _initializeTempSettings() {
    // Initialize with default values
    _tempSettings.addAll({
      'cameraImageTopic': '', // Empty by default, optional
      'cameraEnabled': false, // Camera enabled toggle
      'odomTopic': DefaultSettings.defaultOdomTopic,
      'odomTopicType': DefaultSettings.defaultOdomTopicType,
      'lidarTopic': DefaultSettings.defaultLidarTopic,
      'cmdVelTopic': DefaultSettings.cmdVelTopic,
      'twistType': DefaultSettings.defaultTwistType,
      'linearVelocity': DefaultSettings.defaultLinearVelocity,
      'angularVelocity': DefaultSettings.defaultAngularVelocity,
      'mapsPath': '', // Empty to force user input
      'mappingLaunchFile': '', // Empty to force user input
      'mappingArgs': <Map<String, String>>[],
      'mappingOdomTopic': DefaultSettings.defaultOdomTopic,
      'mappingOdomTopicType': DefaultSettings.defaultOdomTopicType,
      'navigationLaunchFile': '', // Empty to force user input
      'navigationArgs': <Map<String, String>>[],
      'navigationOdomTopic': DefaultSettings.defaultNavigationOdomTopic,
      'navigationOdomTopicType': DefaultSettings.defaultNavigationOdomTopicType,
      'pathTopic': DefaultSettings.defaultPathTopic,
    });
  }

  @override
  void dispose() {
    _progressAnimationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _updateProgress() {
    _progressAnimationController.animateTo((_currentStep + 1) / _totalSteps);
  }

  bool get _canProceed => _stepValidations[_currentStep] ?? false;

  @override
  Widget build(BuildContext context) {
    return Consumer<BrandingProvider>(
      builder: (context, branding, child) {
        return Scaffold(
          backgroundColor: Colors.grey.shade900,
          body: SafeArea(
            child: Stack(
              children: [
                // Main content column (header + pages)
                Column(
                  children: [
                    _buildHeader(context),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildSensorStep(),
                          _buildTeleopStep(),
                          _buildMappingStep(),
                          _buildNavigationStep(),
                        ],
                      ),
                    ),
                  ],
                ),
                // Floating navigation buttons pinned to the screen edges.
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: _buildNavigationButtons(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    // Treat devices with a shortestSide < 600px as mobile/compact (e.g., phones
    // held in landscape). Using a breakpoint instead of a percentage keeps the
    // header height predictable and responsive without relying on exact
    // percentages that can mis-size on very tall/short screens.
    final bool isMobile = screenSize.shortestSide < 600;

    // Tighter spacing on mobile to avoid the header dominating the limited
    // vertical space in landscape mode.
    final double pad = isMobile ? 8 : 16;
    final double iconSize = isMobile ? 18 : 24;
    final double titleSize = isMobile ? 14 : 20;
    final double subtitleSize = isMobile ? 11 : 14;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.grey.shade800,
            Colors.grey.shade900,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildProgressIndicator(context),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _steps[_currentStep].color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            _steps[_currentStep].color.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Icon(
                      _steps[_currentStep].icon,
                      color: _steps[_currentStep].color,
                      size: iconSize,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Setup ${widget.robot.name}',
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: isMobile ? 2 : 4),
                      Text(
                        '${_steps[_currentStep].title}',
                        style: TextStyle(
                          fontSize: subtitleSize,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                onPressed: _showExitDialog,
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isMobile = screenSize.shortestSide < 600;
    final double padV = isMobile ? 6 : 14;
    final double stepFont = isMobile ? 12 : 16;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: padV),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Step counter and colored indicators
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _steps[_currentStep].color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _steps[_currentStep].color.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Step ${_currentStep + 1}/$_totalSteps',
                  style: TextStyle(
                    color: _steps[_currentStep].color,
                    fontWeight: FontWeight.bold,
                    fontSize: stepFont,
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  children: List.generate(_totalSteps, (index) {
                    final isActive = index == _currentStep;
                    final isCompleted = index < _currentStep;
                    final isValid = _stepValidations[index] ?? false;

                    return Container(
                      margin: const EdgeInsets.only(right: 4),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCompleted
                            ? _steps[index].color
                            : isActive && isValid
                                ? _steps[index].color
                                : isActive
                                    ? _steps[index].color.withValues(alpha: 0.5)
                                    : Colors.grey.shade600,
                        border: isActive
                            ? Border.all(
                                color: Colors.white,
                                width: 2,
                              )
                            : null,
                      ),
                      child: isCompleted
                          ? Icon(
                              Icons.check,
                              size: 8,
                              color: Colors.white,
                            )
                          : null,
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorStep() {
    return _buildStepContainer(
      title: 'Sensor Configuration',
      description: 'Configure sensor topics for your robot',
      child: Column(
        children: [
          _buildSettingCard(
            'Camera Image Topic',
            'Set topic for compressed image stream',
            Icons.camera_alt,
            _buildCameraInput(),
          ),
          _buildSettingCard(
            'Odometry Topic',
            'Set topic for odometry data',
            Icons.my_location,
            _buildOdomTopicInput(),
          ),
          _buildSettingCard(
            'Lidar Topic',
            'Set topic for lidar scan data',
            Icons.radar,
            _buildTopicInput(
                'lidarTopic', 'Enter topic name (e.g., /scan)', false),
          ),
        ],
      ),
    );
  }

  Widget _buildTeleopStep() {
    return _buildStepContainer(
      title: 'Teleoperation Setup',
      description: 'Configure movement controls and velocity limits',
      child: Column(
        children: [
          _buildSettingCard(
            'CMD_VEL Topic',
            'Set the topic name for velocity commands',
            Icons.gamepad,
            _buildCmdVelTopicInput(),
          ),
          _buildSettingCard(
            'Linear Velocity',
            'Set maximum linear velocity (m/s)',
            Icons.speed,
            _buildVelocityInput('linearVelocity'),
          ),
          _buildSettingCard(
            'Angular Velocity',
            'Set maximum angular velocity (rad/s)',
            Icons.rotate_right,
            _buildVelocityInput('angularVelocity'),
          ),
        ],
      ),
    );
  }

  Widget _buildMappingStep() {
    return _buildStepContainer(
      title: 'Mapping Configuration',
      description: 'Setup SLAM and map creation parameters',
      child: Column(
        children: [
          _buildSettingCard(
            'Start Mapping Launch File *',
            'Set Launch File and Arguments for starting mapping',
            Icons.rocket_launch,
            Column(
              children: [
                _buildLaunchFileInput(
                    'mappingLaunchFile', true, 'cartographer_ros/cartographer'),
                const SizedBox(height: 20),
                _buildArgumentsList('mappingArgs'),
              ],
            ),
            required: true,
          ),
          _buildSettingCard(
            'Maps Storage Path *',
            'Set the path where maps will be saved',
            Icons.folder,
            _buildPathInput('mapsPath', 'e.g., ~/maps', true),
            required: true,
          ),
          _buildSettingCard(
            'Mapping Odom Topic',
            'Set the topic for mapping odom data',
            Icons.my_location,
            _buildMappingOdomTopicInput(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationStep() {
    return _buildStepContainer(
      title: 'Navigation Setup',
      description: 'Configure autonomous navigation parameters',
      child: Column(
        children: [
          _buildSettingCard(
            'Navigation Launch File *',
            'Set Launch File and Arguments for navigation',
            Icons.rocket_launch,
            Column(
              children: [
                _buildLaunchFileInput(
                    'navigationLaunchFile', true, 'nav2_bringup/navigation'),
                const SizedBox(height: 20),
                _buildArgumentsList('navigationArgs'),
              ],
            ),
            required: true,
          ),
          _buildSettingCard(
            'Navigation Odom Topic',
            'Set the topic for navigation odom data',
            Icons.my_location,
            _buildNavigationOdomTopicInput(),
          ),
          _buildSettingCard(
            'Navigation Path Topic',
            'Set the topic for navigation path visualization',
            Icons.route,
            _buildTopicInput(
                'pathTopic', 'Enter topic name (e.g., /plan)', false),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContainer({
    required String title,
    required String description,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // Center content
        children: [
          Expanded(
            child: Center(
              // Center the content
              child: SingleChildScrollView(
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard(
    String title,
    String description,
    IconData icon,
    Widget content, {
    bool required = false,
  }) {
    return Container(
      width: 600, // Fixed width for landscape
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: required
              ? _steps[_currentStep].color.withValues(alpha: 0.5)
              : Colors.grey.shade700,
          width: required ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _steps[_currentStep].color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: _steps[_currentStep].color,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          // Title + description column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (required) ...[
                      const SizedBox(width: 4),
                      Text(
                        '*',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade400,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 12),
                // Content widget occupies remaining width below description
                content,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraInput() {
    return SizedBox(
      width: 400, // Fixed width for landscape
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue:
                      _tempSettings['cameraImageTopic']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'e.g., /camera/image_raw/compressed',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    filled: true,
                    fillColor: Colors.grey.shade900,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _steps[_currentStep].color),
                    ),
                  ),
                  onChanged: (value) {
                    _tempSettings['cameraImageTopic'] = value;
                    _validateCurrentStep();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  Text(
                    'Enable Camera',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  Switch(
                    value: _tempSettings['cameraEnabled'] ?? false,
                    onChanged: (value) {
                      _handleCameraToggle(value);
                    },
                    activeColor: _steps[_currentStep].color,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Type: sensor_msgs/msg/CompressedImage',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade400,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOdomTopicInput() {
    return SizedBox(
      width: 400, // Fixed width for landscape
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: _tempSettings['odomTopic']?.toString() ?? '',
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter topic name (e.g., /odom)',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              filled: true,
              fillColor: Colors.grey.shade900,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _steps[_currentStep].color),
              ),
            ),
            onChanged: (value) {
              _tempSettings['odomTopic'] = value;
              _validateCurrentStep();
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Type: nav_msgs/msg/Odometry',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade400,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCmdVelTopicInput() {
    return SizedBox(
      width: 400, // Fixed width for landscape
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: _tempSettings['cmdVelTopic']?.toString() ?? '',
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter topic name (e.g., cmd_vel)',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              filled: true,
              fillColor: Colors.grey.shade900,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _steps[_currentStep].color),
              ),
            ),
            onChanged: (value) {
              _tempSettings['cmdVelTopic'] = value;
              _validateCurrentStep();
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value:
                _tempSettings['twistType'] ?? DefaultSettings.defaultTwistType,
            decoration: InputDecoration(
              hintText: 'Select message type',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              filled: true,
              fillColor: Colors.grey.shade900,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _steps[_currentStep].color),
              ),
            ),
            dropdownColor: Colors.grey.shade900,
            style: const TextStyle(color: Colors.white),
            items: DefaultSettings.availableTwistTypes.map((String type) {
              return DropdownMenuItem<String>(
                value: type,
                child: Text(type),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _tempSettings['twistType'] = newValue;
                });
                _validateCurrentStep();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMappingOdomTopicInput() {
    return SizedBox(
      width: 400, // Fixed width for landscape
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: _tempSettings['mappingOdomTopic']?.toString() ?? '',
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter topic name (e.g., /odom)',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              filled: true,
              fillColor: Colors.grey.shade900,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _steps[_currentStep].color),
              ),
            ),
            onChanged: (value) {
              _tempSettings['mappingOdomTopic'] = value;
              _validateCurrentStep();
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Type: nav_msgs/msg/Odometry',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade400,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationOdomTopicInput() {
    return SizedBox(
      width: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue:
                _tempSettings['navigationOdomTopic']?.toString() ?? '',
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter topic name (e.g., /amcl_pose)',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              filled: true,
              fillColor: Colors.grey.shade900,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _steps[_currentStep].color),
              ),
            ),
            onChanged: (value) {
              _tempSettings['navigationOdomTopic'] = value;
              _validateCurrentStep();
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Type: geometry_msgs/msg/PoseWithCovarianceStamped',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade400,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicInput(String key, String hint, bool required) {
    return SizedBox(
      width: 400, // Fixed width for landscape
      child: TextFormField(
        initialValue: _tempSettings[key]?.toString() ?? '',
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade500),
          filled: true,
          fillColor: Colors.grey.shade900,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _steps[_currentStep].color),
          ),
        ),
        onChanged: (value) {
          _tempSettings[key] = value;
          _validateCurrentStep();
        },
        validator: required
            ? (value) =>
                value?.isEmpty ?? true ? 'This field is required' : null
            : null,
      ),
    );
  }

  Widget _buildVelocityInput(String key) {
    return SizedBox(
      width: 200, // Fixed width for landscape
      child: TextFormField(
        initialValue: _tempSettings[key]?.toString() ?? '',
        style: const TextStyle(color: Colors.white),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: 'Enter velocity limit',
          hintStyle: TextStyle(color: Colors.grey.shade500),
          filled: true,
          fillColor: Colors.grey.shade900,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _steps[_currentStep].color),
          ),
          suffixText: key.contains('linear') ? 'm/s' : 'rad/s',
          suffixStyle: TextStyle(color: Colors.grey.shade400),
        ),
        onChanged: (value) {
          _tempSettings[key] = double.tryParse(value) ?? 0.0;
          _validateCurrentStep();
        },
      ),
    );
  }

  Widget _buildPathInput(String key, String hint, bool required) {
    return SizedBox(
      width: 450, // Fixed width for landscape
      child: TextFormField(
        initialValue: _tempSettings[key]?.toString() ?? '',
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade500),
          filled: true,
          fillColor: Colors.grey.shade900,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _steps[_currentStep].color),
          ),
          prefixIcon: Icon(Icons.folder, color: _steps[_currentStep].color),
        ),
        onChanged: (value) {
          _tempSettings[key] = value;
          _validateCurrentStep();
        },
        validator: required
            ? (value) =>
                value?.isEmpty ?? true ? 'This field is required' : null
            : null,
      ),
    );
  }

  Widget _buildLaunchFileInput(String key, bool required, [String? hintText]) {
    return SizedBox(
      width: 450, // Fixed width for landscape
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Format: \${package_name}/\${launchfile_name} (*dont include ".launch.py")',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _tempSettings[key]?.toString() ?? '',
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hintText ?? 'package_name/launch_file',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              filled: true,
              fillColor: Colors.grey.shade900,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _steps[_currentStep].color),
              ),
              prefixIcon:
                  Icon(Icons.rocket_launch, color: _steps[_currentStep].color),
            ),
            onChanged: (value) {
              _tempSettings[key] = value;
              _validateCurrentStep();
            },
            validator: required
                ? (value) =>
                    value?.isEmpty ?? true ? 'This field is required' : null
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildArgumentsList(String key) {
    List<Map<String, String>> args = _tempSettings[key] ?? [];

    return SizedBox(
      width: 450,
      child: Column(
        children: [
          ...args.asMap().entries.map((entry) {
            int index = entry.key;
            Map<String, String> arg = entry.value;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  // Argument name field
                  Expanded(
                    child: TextFormField(
                      initialValue: arg['name'] ?? '',
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Argument name',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                        filled: true,
                        fillColor: Colors.grey.shade900,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: _steps[_currentStep].color),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 12),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        args[index]['name'] = value;
                        _tempSettings[key] = args;
                        _validateCurrentStep();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Argument value field
                  Expanded(
                    child: TextFormField(
                      initialValue: arg['value'] ?? '',
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Value',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                        filled: true,
                        fillColor: Colors.grey.shade900,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: _steps[_currentStep].color),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 12),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        args[index]['value'] = value;
                        _tempSettings[key] = args;
                        _validateCurrentStep();
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      args.removeAt(index);
                      _tempSettings[key] = args;
                      setState(() {});
                      _validateCurrentStep();
                    },
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.red),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          SizedBox(
            width: 200, // Fixed width for add button
            child: ElevatedButton.icon(
              onPressed: () {
                args.add({'name': '', 'value': ''});
                _tempSettings[key] = args;
                setState(() {});
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Argument'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _steps[_currentStep].color.withValues(alpha: 0.2),
                foregroundColor: _steps[_currentStep].color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _validateCurrentStep() {
    bool isValid = false;

    switch (_currentStep) {
      case 0: // Sensor - Camera is optional, other topics have defaults
        isValid = true; // Can use defaults, camera is optional
        break;
      case 1: // Teleop
        isValid = true; // Can use defaults
        break;
      case 2: // Mapping - Only map path and mapping launch file are required
        final mapsPath = _tempSettings['mapsPath']?.toString() ?? '';
        final mappingLaunchFile =
            _tempSettings['mappingLaunchFile']?.toString() ?? '';

        isValid = mapsPath.isNotEmpty && mappingLaunchFile.isNotEmpty;
        break;
      case 3: // Navigation - Only navigation launch file is required
        final navigationLaunchFile =
            _tempSettings['navigationLaunchFile']?.toString() ?? '';

        isValid = navigationLaunchFile.isNotEmpty;
        break;
    }

    setState(() {
      _stepValidations[_currentStep] = isValid;
    });
  }

  Widget _buildNavigationButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            SizedBox(
              width: 120, // Fixed width
              child: ElevatedButton(
                onPressed: _previousStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Previous'),
              ),
            )
          else
            const SizedBox(
                width: 120), // maintain right-aligned spacing when first step
          SizedBox(
            width: 200, // Fixed width for the primary button
            child: ElevatedButton(
              onPressed: _canProceed
                  ? (_currentStep < _totalSteps - 1
                      ? _nextStep
                      : _completeSetup)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _steps[_currentStep].color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _currentStep < _totalSteps - 1 ? 'Next' : 'Complete Setup',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _updateProgress();
      _validateCurrentStep();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _updateProgress();
    }
  }

  void _completeSetup() async {
    // Apply all settings to the settings provider
    final settingsProvider = context.read<SettingsProvider>();
    final connectionProvider = context.read<ConnectionProvider>();

    // IMPORTANT: Update the robot ID first to ensure settings are saved to the correct robot
    final robotId = widget.robot.settingsId;
    await settingsProvider.updateRobotId(robotId);

    // Apply all temp settings to the actual settings
    await _applyTempSettings(settingsProvider);

    // Mark robot as configured
    connectionProvider.markRobotConfigured(widget.robot.id);

    // Navigate to home screen
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _applyTempSettings(SettingsProvider settings) async {
    // Sensor settings
    final cameraImageTopic =
        _tempSettings['cameraImageTopic']?.toString() ?? '';
    settings.setCameraImageTopic(cameraImageTopic);
    settings.setCameraEnabled(_tempSettings['cameraEnabled'] ?? false);

    // Set odom topic
    final odomTopicValue = _tempSettings['odomTopic']?.toString() ?? '';
    final odomTopicIsEmpty = odomTopicValue.isEmpty;
    final finalOdomTopic =
        odomTopicIsEmpty ? DefaultSettings.defaultOdomTopic : odomTopicValue;
    settings.setOdomTopic(
      finalOdomTopic,
      _tempSettings['odomTopicType']?.toString() ??
          DefaultSettings.defaultOdomTopicType,
    );
    final lidarTopicValue = _tempSettings['lidarTopic']?.toString() ?? '';
    final lidarTopicIsEmpty = lidarTopicValue.isEmpty;
    final finalLidarTopic =
        lidarTopicIsEmpty ? DefaultSettings.defaultLidarTopic : lidarTopicValue;
    settings.setLidarTopic(finalLidarTopic);

    // Teleop settings
    final cmdVelTopicValue = _tempSettings['cmdVelTopic']?.toString() ?? '';
    final cmdVelTopicIsEmpty = cmdVelTopicValue.isEmpty;
    final finalCmdVelTopic =
        cmdVelTopicIsEmpty ? DefaultSettings.cmdVelTopic : cmdVelTopicValue;
    settings.setCmdVelTopic(finalCmdVelTopic);
    settings.setTwistType(_tempSettings['twistType']?.toString() ??
        DefaultSettings.defaultTwistType);
    settings.setLinearVelocity(_tempSettings['linearVelocity'] is double
        ? _tempSettings['linearVelocity'] as double
        : DefaultSettings.defaultLinearVelocity);
    settings.setAngularVelocity(_tempSettings['angularVelocity'] is double
        ? _tempSettings['angularVelocity'] as double
        : DefaultSettings.defaultAngularVelocity);

    // Mapping settings
    settings.setMapsPath(_tempSettings['mapsPath']?.toString() ?? '');

    // Set the mapping launch file
    final mappingLaunchFileValue =
        _tempSettings['mappingLaunchFile']?.toString() ?? '';
    settings.setMappingLaunchFile(mappingLaunchFileValue);

    final mappingOdomTopicValue =
        _tempSettings['mappingOdomTopic']?.toString() ?? '';
    final mappingOdomTopicIsEmpty = mappingOdomTopicValue.isEmpty;
    final finalMappingOdomTopic = mappingOdomTopicIsEmpty
        ? DefaultSettings.defaultOdomTopic
        : mappingOdomTopicValue;
    settings.setMappingOdomTopic(
      finalMappingOdomTopic,
      _tempSettings['mappingOdomTopicType']?.toString() ??
          DefaultSettings.defaultMappingOdomTopicType,
    );

    // Apply mapping arguments
    final mappingArgs =
        _tempSettings['mappingArgs'] as List<Map<String, String>>? ?? [];
    for (var arg in mappingArgs) {
      if (arg['name']?.isNotEmpty == true && arg['value']?.isNotEmpty == true) {
        settings.addMappingArg(arg['name']!, arg['value']!);
      }
    }

    // Navigation settings
    settings.setNavigationLaunchFile(
        _tempSettings['navigationLaunchFile']?.toString() ?? '');
    final navigationOdomTopicValue =
        _tempSettings['navigationOdomTopic']?.toString() ?? '';
    final navigationOdomTopicIsEmpty = navigationOdomTopicValue.isEmpty;
    final finalNavigationOdomTopic = navigationOdomTopicIsEmpty
        ? DefaultSettings.defaultNavigationOdomTopic
        : navigationOdomTopicValue;
    settings.setNavigationOdomTopic(
      finalNavigationOdomTopic,
      _tempSettings['navigationOdomTopicType']?.toString() ??
          DefaultSettings.defaultNavigationOdomTopicType,
    );
    final pathTopicValue = _tempSettings['pathTopic']?.toString() ?? '';
    final pathTopicIsEmpty = pathTopicValue.isEmpty;
    final finalPathTopic =
        pathTopicIsEmpty ? DefaultSettings.defaultPathTopic : pathTopicValue;
    settings.setPathTopic(finalPathTopic);

    // Apply navigation arguments
    final navigationArgs =
        _tempSettings['navigationArgs'] as List<Map<String, String>>? ?? [];
    for (var arg in navigationArgs) {
      if (arg['name']?.isNotEmpty == true && arg['value']?.isNotEmpty == true) {
        settings.addNavigationArg(arg['name']!, arg['value']!);
      }
    }

    // Force save all settings to ensure they are persisted
    await settings.forceSaveSettings();
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 400, // Reduced width
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Exit Setup?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your robot setup is not complete. Exiting will disconnect from the robot and discard all changes. Are you sure?',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      // Disconnect from robot
                      final connectionProvider =
                          context.read<ConnectionProvider>();
                      if (connectionProvider.isConnected) {
                        await connectionProvider.disconnect();
                      }

                      // Delete incomplete robot configuration
                      connectionProvider.deleteRobot(widget.robot.id);

                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (context) => const HomeScreen()),
                        (route) => false,
                      );
                    },
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text(
                      'Exit & Disconnect',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Request storage permission when the user enables the camera option.
  Future<void> _handleCameraToggle(bool enable) async {
    if (!enable) {
      setState(() {
        _tempSettings['cameraEnabled'] = false;
      });
      _validateCurrentStep();
      return;
    }

    final granted = await _requestStoragePermission();

    setState(() {
      _tempSettings['cameraEnabled'] = granted;
    });

    _validateCurrentStep();
  }

  Future<bool> _requestStoragePermission() async {
    Permission permission = Permission.storage;

    if (Theme.of(context).platform == TargetPlatform.iOS) {
      permission = Permission.photosAddOnly;
    }

    Future<PermissionStatus> ask(Permission p) async {
      if (await p.isGranted) return PermissionStatus.granted;
      return p.request();
    }

    PermissionStatus status = await ask(permission);

    if (status.isDenied || status.isRestricted) {
      if (permission != Permission.photos &&
          permission != Permission.photosAddOnly) {
        status = await ask(Permission.photos);
      }
    }

    if (status.isGranted) return true;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          action: status.isPermanentlyDenied
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: openAppSettings,
                )
              : null,
          content: const Text(
              'Camera image saving requires permission. Enable it in settings.'),
          backgroundColor: Colors.red.withOpacity(0.9),
        ),
      );
    }

    return false;
  }
}

class StepConfig {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  StepConfig({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
