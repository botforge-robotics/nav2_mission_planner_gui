import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import '../../../../providers/connection_provider.dart';
import 'package:rosapi_msgs/srv.dart';

class TFTopicDropdown extends StatefulWidget {
  final String initialValue;
  final Function(String) onChanged;
  final Color modeColor;

  const TFTopicDropdown({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.modeColor,
  });

  @override
  State<TFTopicDropdown> createState() => _TFTopicDropdownState();
}

class _TFTopicDropdownState extends State<TFTopicDropdown> {
  // Static list to maintain topics across widget instances
  static List<String> _sessionTopics = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Only fetch if we haven't fetched before in this session
    if (_sessionTopics.isEmpty) {
      _fetchTopics();
    }
  }

  Future<void> _fetchTopics() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final connection =
          Provider.of<ConnectionProvider>(context, listen: false);
      final client = ServiceClient<Topics, TopicsRequest, TopicsResponse>(
        ros2: connection.ros2Client,
        name: '/rosapi/topics',
        type: Topics().fullType,
        serviceType: Topics(),
        timeout: 5,
      );

      final request = TopicsRequest();
      final response = await client.call(request);

      // Filter topics that are TF2 TFMessage topics
      final tfTopics = response.topics
          .where(
              (topic) => topic.endsWith('/tf') || topic.endsWith('/tf_static'))
          .toList();

      // Sort topics alphabetically
      tfTopics.sort();

      setState(() {
        _sessionTopics = tfTopics;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to fetch TF topics: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.modeColor.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    inputDecorationTheme: InputDecorationTheme(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sessionTopics.contains(widget.initialValue)
                          ? widget.initialValue
                          : null,
                      hint: Text(
                        'Select TF topic',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 16,
                        ),
                      ),
                      dropdownColor: Colors.grey[900],
                      style: const TextStyle(color: Colors.white),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: widget.modeColor,
                      ),
                      items: _sessionTopics.map((String topic) {
                        return DropdownMenuItem<String>(
                          value: topic,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              topic,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          widget.onChanged(newValue);
                        }
                      },
                    ),
                  ),
                ),
              ),
              Container(
                height: 42,
                width: 1,
                color: widget.modeColor.withOpacity(0.3),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isLoading ? null : _fetchTopics,
                  borderRadius:
                      BorderRadius.horizontal(right: Radius.circular(11)),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.horizontal(right: Radius.circular(11)),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  widget.modeColor),
                            ),
                          )
                        : Icon(
                            Icons.refresh,
                            color: widget.modeColor,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: TextStyle(
              color: Colors.red.shade400,
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Type: tf2_msgs/msg/TFMessage',
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade400,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
