import 'package:flutter/material.dart';
import '../../modals/mission.dart';
import 'numerical_range_formatter.dart';
import 'package:flutter/services.dart';

class FrequencySelector extends StatefulWidget {
  final MissionItem item;
  final Color modeColor;
  final VoidCallback onChanged;

  const FrequencySelector({
    Key? key,
    required this.item,
    required this.modeColor,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<FrequencySelector> createState() => _FrequencySelectorState();
}

class _FrequencySelectorState extends State<FrequencySelector> {
  MissionItem get _item => widget.item;

  late final TextEditingController _hzController;
  late final TextEditingController _durationController;
  final FocusNode _hzFocus = FocusNode();
  final FocusNode _durationFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Ensure defaults
    _item.publishFrequencyType ??= 'once';

    _hzController = TextEditingController(
        text: (_item.publishFrequency ?? 1).toInt().toString());
    _durationController = TextEditingController(
        text: (_item.publishDuration ?? 5).toInt().toString());
  }

  @override
  void dispose() {
    _hzFocus.dispose();
    _durationFocus.dispose();
    _hzController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  // Call this whenever underlying mission item values change to keep controllers
  void _syncControllers() {
    if (!_hzFocus.hasFocus) {
      _hzController.text = (_item.publishFrequency ?? 1).toInt().toString();
    }
    if (!_durationFocus.hasFocus) {
      if (_item.publishDuration != null && _item.publishDuration! > 0) {
        _durationController.text = _item.publishDuration!.toInt().toString();
      }
    }
  }

  void _notify() {
    widget.onChanged();
    setState(() {});
    _syncControllers();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Publishing Mode',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        // Once option
        _buildModeOption(
          value: 'once',
          title: 'Publish Once',
          description: 'Send message only once',
          icon: Icons.check_circle_outline,
        ),
        const SizedBox(height: 12),
        // Frequency option
        _buildModeOption(
          value: 'frequency',
          title: 'Publish at Frequency',
          description: 'Send message continuously',
          icon: Icons.repeat,
        ),

        if (_item.publishFrequencyType == 'frequency') ...[
          const SizedBox(height: 16),
          _buildFrequencyControls(),
        ],
      ],
    );
  }

  Widget _buildModeOption({
    required String value,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final isSelected = _item.publishFrequencyType == value;
    return GestureDetector(
      onTap: () {
        _item.publishFrequencyType = value;
        if (value == 'once') {
          _item.publishFrequency = null;
          _item.publishDuration = null;
        } else {
          _item.publishFrequency ??= 1.0;
        }
        _notify();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              isSelected ? widget.modeColor.withOpacity(0.2) : Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? widget.modeColor : Colors.grey[700]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected ? widget.modeColor : Colors.grey[400],
                size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[300],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: widget.modeColor, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildFrequencyControls() {
    return Container(
      margin: const EdgeInsets.only(left: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.modeColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hz control
          Row(
            children: [
              const Text('Rate (Hz):', style: TextStyle(color: Colors.grey)),
              const SizedBox(width: 16),
              IconButton(
                onPressed: () {
                  final current = (_item.publishFrequency ?? 1).toInt();
                  _item.publishFrequency =
                      (current - 1).clamp(1, 30).toDouble();
                  _notify();
                },
                icon: Icon(Icons.remove, color: widget.modeColor),
                style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    minimumSize: const Size(32, 32)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextFormField(
                  controller: _hzController,
                  focusNode: _hzFocus,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    NumericalRangeFormatter(min: 1, max: 30),
                  ],
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[800],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (value) {
                    if (value.isEmpty) return;
                    final v = int.tryParse(value) ?? 1;
                    _item.publishFrequency = v.clamp(1, 30).toDouble();
                    _notify();
                  },
                  onEditingComplete: () {
                    if (_hzController.text.trim().isEmpty) {
                      _item.publishFrequency = 1.0;
                      _hzController.text = '1';
                    }
                    _hzFocus.unfocus();
                    _notify();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  final current = (_item.publishFrequency ?? 1).toInt();
                  _item.publishFrequency =
                      (current + 1).clamp(1, 30).toDouble();
                  _notify();
                },
                icon: Icon(Icons.add, color: widget.modeColor),
                style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    minimumSize: const Size(32, 32)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Duration',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          _buildDurationOption('duration', 'For specific duration'),
          _buildDurationOption('until_next_goal', 'Until next waypoint'),
          _buildDurationOption('mission_end', 'Until mission completion'),
        ],
      ),
    );
  }

  Widget _buildDurationOption(String value, String label) {
    final group = (_item.publishDuration == null)
        ? 'until_next_goal'
        : (_item.publishDuration! > 0
            ? 'duration'
            : (_item.publishDuration == -1
                ? 'mission_end'
                : 'until_next_goal'));

    return Row(
      children: [
        Radio<String>(
          value: value,
          groupValue: group,
          onChanged: (_) {
            switch (value) {
              case 'duration':
                _item.publishDuration = 5.0;
                break;
              case 'mission_end':
                _item.publishDuration = -1;
                break;
              case 'until_next_goal':
                _item.publishDuration = null;
                break;
            }
            _notify();
          },
          activeColor: widget.modeColor,
        ),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
        if (value == 'duration' &&
            _item.publishDuration != null &&
            _item.publishDuration! > 0) ...[
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: TextFormField(
              controller: _durationController,
              focusNode: _durationFocus,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                NumericalRangeFormatter(min: 1, max: 3600),
              ],
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              ),
              onChanged: (v) {
                if (v.isEmpty) return;
                final d = int.tryParse(v) ?? 5;
                _item.publishDuration = d.clamp(1, 3600).toDouble();
                _notify();
              },
              onEditingComplete: () {
                if (_durationController.text.trim().isEmpty) {
                  _item.publishDuration = 5.0;
                  _durationController.text = '5';
                }
                _durationFocus.unfocus();
                _notify();
              },
            ),
          ),
          const SizedBox(width: 8),
          const Text('seconds',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ],
    );
  }
}
