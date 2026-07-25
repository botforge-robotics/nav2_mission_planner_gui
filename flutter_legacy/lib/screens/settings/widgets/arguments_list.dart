import 'package:flutter/material.dart';
import 'argument_dialogs.dart';

class ArgumentsList extends StatelessWidget {
  final List<Map<String, String>> arguments;
  final Function(int) onRemove;
  final Function(String, String) onAdd;
  final Function(int, String, String) onUpdate;
  final Size screenSize;
  final Color modeColor;

  const ArgumentsList({
    super.key,
    required this.arguments,
    required this.onRemove,
    required this.onAdd,
    required this.onUpdate,
    required this.screenSize,
    required this.modeColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: screenSize.width * 0.01, // horizontal spacing
        runSpacing: screenSize.height * 0.01, // vertical spacing
        alignment: WrapAlignment.start,
        children: [
          // Argument Pills
          ...arguments.asMap().entries.map((entry) {
            final index = entry.key;
            final arg = entry.value;
            return GestureDetector(
              onTap: () => showEditArgumentDialog(
                context: context,
                screenSize: screenSize,
                modeColor: modeColor,
                name: arg['name'] ?? '',
                value: arg['value'] ?? '',
                onUpdate: (name, value) => onUpdate(index, name, value),
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: screenSize.width * 0.015,
                  vertical: screenSize.height * 0.008,
                ),
                decoration: BoxDecoration(
                  color: modeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: modeColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${arg['name']} = ${arg['value']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: screenSize.width * 0.01),
                    InkWell(
                      onTap: () => onRemove(index),
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: modeColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // Add Argument Pill
          GestureDetector(
            onTap: () => showAddArgumentDialog(
              context: context,
              screenSize: screenSize,
              modeColor: modeColor,
              onAdd: onAdd,
            ),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: screenSize.width * 0.015,
                vertical: screenSize.height * 0.008,
              ),
              decoration: BoxDecoration(
                color: modeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: modeColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add,
                    size: 12,
                    color: modeColor,
                  ),
                  SizedBox(width: screenSize.width * 0.005),
                  Text(
                    'Add Argument',
                    style: TextStyle(
                      fontSize: 12,
                      color: modeColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
