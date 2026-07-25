import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// Shows a dialog to add a new launch argument
void showAddArgumentDialog({
  required BuildContext context,
  required Size screenSize,
  required Color modeColor,
  required Function(String name, String value) onAdd,
}) {
  final nameController = TextEditingController();
  final valueController = TextEditingController();

  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppTheme.toolbarColor,
      child: SingleChildScrollView(
        child: Container(
          width: screenSize.width * 0.4,
          padding: EdgeInsets.all(screenSize.height * 0.02),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add Launch Argument',
                    style: TextStyle(
                      fontSize: screenSize.height * 0.035,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Divider(color: modeColor.withOpacity(0.2)),
              SizedBox(height: screenSize.height * 0.02),

              TextField(
                controller: nameController,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: screenSize.height * 0.03,
                ),
                decoration: InputDecoration(
                  labelText: 'Arg Name',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'e.g., use_sim_time',
                  hintStyle: TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: screenSize.width * 0.015,
                    vertical: screenSize.height * 0.015,
                  ),
                ),
              ),
              SizedBox(height: screenSize.height * 0.02),

              TextField(
                controller: valueController,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: screenSize.height * 0.03,
                ),
                decoration: InputDecoration(
                  labelText: 'Arg Value',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'e.g., true',
                  hintStyle: TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: screenSize.width * 0.015,
                    vertical: screenSize.height * 0.015,
                  ),
                ),
              ),
              SizedBox(height: screenSize.height * 0.03),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: screenSize.height * 0.03,
                      ),
                    ),
                  ),
                  SizedBox(width: screenSize.width * 0.01),
                  ElevatedButton(
                    onPressed: () {
                      if (nameController.text.isNotEmpty) {
                        onAdd(nameController.text, valueController.text);
                        Navigator.of(context).pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: modeColor,
                      padding: EdgeInsets.symmetric(
                        horizontal: screenSize.width * 0.02,
                        vertical: screenSize.height * 0.015,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Add Argument',
                      style: TextStyle(
                        fontSize: screenSize.height * 0.03,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Shows a dialog to edit an existing launch argument
void showEditArgumentDialog({
  required BuildContext context,
  required Size screenSize,
  required Color modeColor,
  required String name,
  required String value,
  required Function(String name, String value) onUpdate,
}) {
  final nameController = TextEditingController(text: name);
  final valueController = TextEditingController(text: value);

  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppTheme.toolbarColor,
      child: SingleChildScrollView(
        child: Container(
          width: screenSize.width * 0.4,
          padding: EdgeInsets.all(screenSize.height * 0.02),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Edit Launch Argument',
                    style: TextStyle(
                      fontSize: screenSize.height * 0.025,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Divider(color: modeColor.withOpacity(0.2)),
              SizedBox(height: screenSize.height * 0.02),

              // Argument Name
              Text(
                'Argument Name',
                style: TextStyle(
                  fontSize: screenSize.height * 0.02,
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: screenSize.height * 0.01),
              TextField(
                controller: nameController,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: screenSize.height * 0.022,
                ),
                decoration: InputDecoration(
                  labelText: 'Name',
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: screenSize.width * 0.015,
                    vertical: screenSize.height * 0.015,
                  ),
                ),
              ),
              SizedBox(height: screenSize.height * 0.02),

              // Argument Value
              Text(
                'Argument Value',
                style: TextStyle(
                  fontSize: screenSize.height * 0.02,
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: screenSize.height * 0.01),
              TextField(
                controller: valueController,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: screenSize.height * 0.022,
                ),
                decoration: InputDecoration(
                  labelText: 'Value',
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: screenSize.width * 0.015,
                    vertical: screenSize.height * 0.015,
                  ),
                ),
              ),
              SizedBox(height: screenSize.height * 0.03),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: screenSize.height * 0.02,
                      ),
                    ),
                  ),
                  SizedBox(width: screenSize.width * 0.01),
                  ElevatedButton(
                    onPressed: () {
                      if (nameController.text.isNotEmpty) {
                        onUpdate(nameController.text, valueController.text);
                        Navigator.of(context).pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: modeColor,
                      padding: EdgeInsets.symmetric(
                        horizontal: screenSize.width * 0.02,
                        vertical: screenSize.height * 0.015,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Update',
                      style: TextStyle(
                        fontSize: screenSize.height * 0.02,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
