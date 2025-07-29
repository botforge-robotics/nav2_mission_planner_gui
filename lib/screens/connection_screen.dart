import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/branding_provider.dart';
import '../widgets/top_status_bar/top_status_bar.dart';
import '../constants/modes.dart';
import '../theme/app_theme.dart';
import 'robot_setup_wizard.dart';
import 'home_screen.dart';
import 'dart:ui';

class ConnectionScreen extends StatefulWidget {
  final bool showTopStatusBar;

  const ConnectionScreen({super.key, this.showTopStatusBar = true});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final nameController = TextEditingController();
  final ipController = TextEditingController();
  final portController = TextEditingController();
  final bool _isLoading = false;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _ipFocus = FocusNode();
  final FocusNode _portFocus = FocusNode();
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final connectionProvider =
        Provider.of<ConnectionProvider>(context, listen: false);
    ipController.text = connectionProvider.ip;
    portController.text = connectionProvider.port;
  }

  @override
  void dispose() {
    nameController.dispose();
    ipController.dispose();
    portController.dispose();
    _nameFocus.dispose();
    _ipFocus.dispose();
    _portFocus.dispose();
    super.dispose();
  }

  void _showInfoSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 4,
        margin: EdgeInsets.all(8),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 4,
        margin: EdgeInsets.all(8),
      ),
    );
  }

  Future<void> _connectToRobot(
      BuildContext context, String name, String ip, String port) async {
    if (name.isEmpty) {
      setState(() => _nameError = 'Robot name is required');
      return;
    }
    if (name.length < 4) {
      setState(() => _nameError = 'Name must be at least 4 characters');
      return;
    }
    setState(() => _nameError = null);

    // Unfocus any active text fields
    FocusScope.of(context).unfocus();

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                  color: Provider.of<BrandingProvider>(context, listen: false)
                      .themeColor),
              const SizedBox(height: 16),
              Text(
                'Connecting to Robot...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Text(
                name.isNotEmpty ? '$name ($ip:$port)' : '$ip : $port',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final connectionProvider =
          Provider.of<ConnectionProvider>(context, listen: false);
      final success = await connectionProvider.connect(ip, port, name: name);

      // Dismiss loading dialog
      if (mounted) Navigator.pop(context);

      if (success) {
        _showInfoSnackBar(context, 'Connected successfully!');

        // Check if robot needs setup
        if (connectionProvider.activeRobotNeedsSetup) {
          // Navigate to setup wizard for new robots
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => RobotSetupWizard(
                  robot: connectionProvider.activeRobot!,
                ),
              ),
            );
          }
        } else {
          // Navigate to home screen for existing configured robots
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const HomeScreen(),
              ),
            );
          }
        }
      } else {
        _showErrorSnackBar(context, 'Connection failed');
      }
    } catch (e) {
      // Dismiss loading dialog
      if (mounted) Navigator.pop(context);
      _showErrorSnackBar(context, 'Connection failed: ${e.toString()}');
    }
  }

  // Method to connect to existing robot from the list
  Future<void> _connectToExistingRobot(
      BuildContext context, String name, String ip, String port) async {
    // Fill the form with existing robot details
    nameController.text = name;
    ipController.text = ip;
    portController.text = port;

    // Connect using existing name
    await _connectToRobot(context, name, ip, port);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ConnectionProvider, BrandingProvider>(
      builder: (context, connectionProvider, brandingProvider, _) {
        final hasRecentConnections = connectionProvider.robots.isNotEmpty;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              // Conditional TopStatusBar - only show when widget.showTopStatusBar is true
              if (widget.showTopStatusBar)
                TopStatusBar(
                  currentMode: AppModes.teleop,
                  onModeChanged: (mode) {
                    // No mode changes allowed on connection screen
                  },
                  statusText: 'Connect to Robot',
                  statusColor: Colors.red,
                  height: AppTheme.statusBarHeight,
                  icon: FontAwesomeIcons.robot,
                ),
              // Main content
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900.withValues(alpha: 0.3),
                    ),
                    child: SafeArea(
                      child: hasRecentConnections
                          ? _buildSplitScreen(
                              context, connectionProvider, brandingProvider)
                          : _buildFullScreen(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSplitScreen(
      BuildContext context,
      ConnectionProvider connectionProvider,
      BrandingProvider brandingProvider) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final screenHeight = MediaQuery.of(context).size.height;

    return Row(
      children: [
        if (!keyboardVisible || screenHeight > 600)
          Container(
            width: 300,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              border: Border(
                right: BorderSide(
                    color: Colors.white.withValues(alpha: 0.05), width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildListHeader(context),
                Expanded(
                  child: _buildConnectionsList(
                      context, connectionProvider, brandingProvider),
                ),
              ],
            ),
          ),
        Expanded(
          child: KeyboardDismissOnTap(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildScrollableForm(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFullScreen(BuildContext context) {
    return KeyboardDismissOnTap(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: _buildScrollableForm(context),
      ),
    );
  }

  Widget _buildScrollableForm(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        final isKeyboardVisible = keyboardHeight > 0;

        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(
            bottom: isKeyboardVisible ? keyboardHeight + 20 : 20,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight -
                  (isKeyboardVisible ? keyboardHeight : 0),
            ),
            child: Center(
              child: _buildConnectionContent(context),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionContent(BuildContext context) {
    return Container(
      width: 500,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Connect to New Robot',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter connection details',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 30),
          _buildConnectionFormFields(context),
        ],
      ),
    );
  }

  Widget _buildListHeader(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.grey.shade900.withValues(alpha: 0.7),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.05),
                width: 1,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.memory,
                    size: 20,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Saved Robots',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
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

  Widget _buildConnectionsList(
      BuildContext context,
      ConnectionProvider connectionProvider,
      BrandingProvider brandingProvider) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8),
      itemCount: connectionProvider.robots.length,
      itemBuilder: (context, index) {
        final robot = connectionProvider.robots[index];
        return Dismissible(
          key: Key(robot.id),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.symmetric(
              vertical: 4,
              horizontal: 12,
            ),
            decoration: BoxDecoration(
              color: Colors.red[600],
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            padding: EdgeInsets.only(right: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.delete,
                  color: Colors.white,
                  size: 24,
                ),
                SizedBox(height: 4),
                Text(
                  'Delete',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: Colors.grey[900],
                    title: Text(
                      'Delete Robot',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: Text(
                      'Are you sure you want to delete "${robot.name}"? This will also remove all its settings.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          'Delete',
                          style: TextStyle(color: Colors.red[400]),
                        ),
                      ),
                    ],
                  ),
                ) ??
                false;
          },
          onDismissed: (direction) {
            // Delete robot and its settings
            connectionProvider.deleteRobot(robot.id);

            // Show confirmation snackbar
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Robot "${robot.name}" deleted'),
                  ],
                ),
                backgroundColor: Colors.red[600],
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                margin: EdgeInsets.all(8),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(
              vertical: 4,
              horizontal: 12,
            ),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[700]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Robot status color indicator
                Container(
                  width: 6,
                  height: 70,
                  decoration: BoxDecoration(
                    color: brandingProvider.themeColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      splashColor:
                          brandingProvider.themeColor.withValues(alpha: 0.1),
                      highlightColor:
                          brandingProvider.themeColor.withValues(alpha: 0.05),
                      onTap: () => _connectToExistingRobot(
                        context,
                        robot.name,
                        robot.ip,
                        robot.port,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Robot icon
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: brandingProvider.themeColor
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                FontAwesomeIcons.robot,
                                color: brandingProvider.themeColor,
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 16),

                            // Robot info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          robot.name.isNotEmpty
                                              ? robot.name
                                              : 'Unnamed Robot',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.network_ping,
                                        color: Colors.grey.shade400,
                                        size: 14,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        '${robot.ip}:${robot.port}',
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionFormFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField(
          context: context,
          controller: nameController,
          focusNode: _nameFocus,
          label: 'Robot Name',
          hint: 'Enter robot name',
          icon: FontAwesomeIcons.robot,
          errorText: _nameError,
          onEditingComplete: () => _ipFocus.requestFocus(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                context: context,
                controller: ipController,
                focusNode: _ipFocus,
                label: 'IP Address',
                hint: 'Enter robot IP',
                icon: Icons.router,
                onEditingComplete: () => _portFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                context: context,
                controller: portController,
                focusNode: _portFocus,
                label: 'Port',
                hint: 'Port number',
                icon: Icons.settings_ethernet,
                keyboardType: TextInputType.number,
                onEditingComplete: () => FocusScope.of(context).unfocus(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildConnectButton(context),
      ],
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? errorText,
    VoidCallback? onEditingComplete,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          hoverColor: Colors.white.withValues(alpha: 0.1),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: Provider.of<BrandingProvider>(context, listen: false)
                    .themeColor
                    .withValues(alpha: 0.5),
                width: 1),
          ),
          labelStyle: TextStyle(color: Colors.grey.shade400),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: const TextStyle(color: Colors.white),
        keyboardType: keyboardType,
        textInputAction: TextInputAction.next,
        onTap: () {
          Future.delayed(Duration(milliseconds: 300), () {
            Scrollable.ensureVisible(
              context,
              duration: Duration(milliseconds: 300),
              curve: Curves.easeOut,
              alignment: 0.5,
            );
          });
        },
        onEditingComplete: onEditingComplete,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          prefixIcon: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
            child: Icon(icon,
                color: Colors.white.withValues(alpha: 0.7), size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.zero,
          elevation: 4,
        ),
        onPressed: _isLoading
            ? null
            : () => _connectToRobot(context, nameController.text,
                ipController.text, portController.text),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Provider.of<BrandingProvider>(context, listen: false)
                    .themeColor,
                Provider.of<BrandingProvider>(context, listen: false)
                    .themeColor
                    .withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            constraints: BoxConstraints(minHeight: 50),
            alignment: Alignment.center,
            child: _isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.link, size: 16),
                      SizedBox(width: 10),
                      Text(
                        _isLoading ? 'Connecting...' : 'Connect',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class KeyboardDismissOnTap extends StatelessWidget {
  final Widget child;
  const KeyboardDismissOnTap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
