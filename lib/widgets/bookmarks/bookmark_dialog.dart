import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/branding_provider.dart';

class BookmarkDialog extends StatefulWidget {
  final Function(IconData icon, String name) onDone;
  final VoidCallback onCancel;

  const BookmarkDialog({
    super.key,
    required this.onDone,
    required this.onCancel,
  });

  @override
  State<BookmarkDialog> createState() => _BookmarkDialogState();
}

class _BookmarkDialogState extends State<BookmarkDialog> {
  final TextEditingController _nameController = TextEditingController();
  IconData _selectedIcon = Icons.star;
  // List of available icons
  final List<IconData> _availableIcons = [
    Icons.star,
    Icons.assistant_photo_rounded,
    Icons.electric_bolt_rounded,
    Icons.bedroom_baby_rounded,
    Icons.bedroom_child_rounded,
    Icons.bedroom_parent_rounded,
    Icons.blender_rounded,
    Icons.bookmark,
    Icons.build,
    Icons.chair_rounded,
    Icons.clean_hands_rounded,
    Icons.cleaning_services_rounded,
    Icons.coffee_maker_rounded,
    Icons.construction_rounded,
    Icons.dining_rounded,
    Icons.directions_car_outlined,
    Icons.door_front_door_outlined,
    Icons.door_sliding_rounded,
    Icons.electrical_services_rounded,
    Icons.engineering_rounded,
    Icons.ev_station_rounded,
    Icons.factory_rounded,
    Icons.favorite_rounded,
    Icons.fitness_center_rounded,
    Icons.flag,
    Icons.group,
    Icons.health_and_safety_rounded,
    Icons.home,
    Icons.home_repair_service_rounded,
    Icons.inventory_2_rounded,
    Icons.kitchen_rounded,
    Icons.laptop_rounded,
    Icons.liquor_rounded,
    Icons.living_rounded,
    Icons.local_grocery_store_rounded,
    Icons.local_laundry_service_rounded,
    Icons.local_library_rounded,
    Icons.local_movies_rounded,
    Icons.local_mall_rounded,
    Icons.local_parking_rounded,
    Icons.local_print_shop_rounded,
    Icons.meeting_room_rounded,
    Icons.pallet,
    Icons.person,
    Icons.pets_rounded,
    Icons.propane_tank_rounded,
    Icons.room_preferences_rounded,
    Icons.room_service_rounded,
    Icons.router_rounded,
    Icons.science_rounded,
    Icons.security_rounded,
    Icons.self_improvement_rounded,
    Icons.smoking_rooms_rounded,
    Icons.sports_esports_rounded,
    Icons.storage_rounded,
    Icons.support_agent_rounded,
    Icons.weekend_rounded,
    Icons.work_rounded,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  'Add Bookmark',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // Name input field
                Consumer<BrandingProvider>(
                  builder: (context, brandingProvider, child) {
                    return TextField(
                      controller: _nameController,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Location Name',
                        labelStyle: TextStyle(color: Colors.grey[400]),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[700]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: brandingProvider.themeColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[800],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                // Icon grid
                Consumer<BrandingProvider>(
                  builder: (context, brandingProvider, child) {
                    return Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: GridView.builder(
                          physics: NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          padding: EdgeInsets.all(8),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _availableIcons.length,
                          itemBuilder: (context, index) {
                            final icon = _availableIcons[index];
                            final isSelected = icon == _selectedIcon;
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedIcon = icon;
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? brandingProvider.themeColor
                                      : Colors.grey[700],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  icon,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: widget.onCancel,
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (_nameController.text.isNotEmpty) {
                          widget.onDone(_selectedIcon, _nameController.text);
                        } else {
                          // Show a message or handle the empty case
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Please enter a location name.'),
                              backgroundColor: Colors.red.withOpacity(0.9),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Provider.of<BrandingProvider>(context,
                                listen: false)
                            .themeColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text('Done'),
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
}
