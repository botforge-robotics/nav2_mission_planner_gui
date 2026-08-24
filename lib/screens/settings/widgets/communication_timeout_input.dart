import 'package:flutter/material.dart';

class CommunicationTimeoutInput extends StatefulWidget {
  final int initialValue;
  final ValueChanged<int> onChanged;
  final Size screenSize;
  final Color modeColor;

  const CommunicationTimeoutInput({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.screenSize,
    required this.modeColor,
  });

  @override
  State<CommunicationTimeoutInput> createState() =>
      _CommunicationTimeoutInputState();
}

class _CommunicationTimeoutInputState extends State<CommunicationTimeoutInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue.toString());
  }

  @override
  void didUpdateWidget(covariant CommunicationTimeoutInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSubmitted(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) {
      widget.onChanged(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            style: theme.textTheme.bodySmall,
            decoration: InputDecoration(
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: widget.modeColor.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.modeColor, width: 1.5),
              ),
              contentPadding: EdgeInsets.symmetric(
                vertical: widget.screenSize.height * 0.015,
                horizontal: 12,
              ),
              hintText: 'Enter seconds',
              hintStyle: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            onFieldSubmitted: _onSubmitted,
            onChanged: (value) {
              // Live update if needed
              final parsed = int.tryParse(value.trim());
              if (parsed != null) {
                widget.onChanged(parsed);
              }
            },
          ),
        ),
        SizedBox(width: widget.screenSize.width * 0.015),
        Text(
          'seconds',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
