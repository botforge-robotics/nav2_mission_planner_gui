import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/sdk_api_service.dart';
import '../../../theme/app_theme.dart';
import 'mission_graph_models.dart';

/// Modal dialog presented to users/operators when an executing mission
/// triggers a `ui_interaction` node (Form, Choices, Alert, Kiosk Picker).
class UiInteractionDialog extends StatefulWidget {
  const UiInteractionDialog({
    super.key,
    required this.api,
    required this.interaction,
    this.onDismissed,
  });

  final SdkApiService api;
  final Map<String, dynamic> interaction;
  final VoidCallback? onDismissed;

  /// Convenience method to show this dialog over the current context.
  static Future<void> show(
    BuildContext context, {
    required SdkApiService api,
    required Map<String, dynamic> interaction,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UiInteractionDialog(
        api: api,
        interaction: interaction,
      ),
    );
  }

  @override
  State<UiInteractionDialog> createState() => _UiInteractionDialogState();
}

class _UiInteractionDialogState extends State<UiInteractionDialog> {
  late final String _interactionId;
  late final String _subtype;
  late final String _title;
  late final String _message;
  late final double _timeoutSec;
  late final List<dynamic> _choices;
  late final List<FormFieldDef> _fields;
  late final String? _imageUrl;

  final Map<String, dynamic> _formData = {};
  final _formKey = GlobalKey<FormState>();

  Timer? _countdownTimer;
  double _remainingSec = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _interactionId = widget.interaction['interaction_id']?.toString() ??
        widget.interaction['node_id']?.toString() ??
        '';
    final p = widget.interaction['params'] as Map<String, dynamic>? ?? {};
    _subtype = p['subtype']?.toString() ?? 'modal';
    _title = p['title']?.toString() ?? 'Operator Action Required';
    _message = p['message']?.toString() ?? '';
    _timeoutSec = (p['timeout_sec'] as num?)?.toDouble() ?? 60.0;
    _choices = (p['choices'] as List<dynamic>?) ?? ['confirm'];
    _imageUrl = p['image_url']?.toString();

    // Parse form fields if any
    final rawFields = p['fields'] as List<dynamic>? ?? [];
    _fields = rawFields.map((f) => FormFieldDef.fromJson(f as Map<String, dynamic>)).toList();
    for (final f in _fields) {
      if (f.type == 'checkbox' || f.type == 'switch') {
        _formData[f.key] = false;
      } else {
        _formData[f.key] = '';
      }
    }

    _remainingSec = _timeoutSec;
    if (_timeoutSec > 0) {
      _countdownTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
        setState(() {
          _remainingSec = (_remainingSec - 0.2).clamp(0.0, _timeoutSec);
          if (_remainingSec <= 0) {
            _countdownTimer?.cancel();
            if (mounted) {
              Navigator.of(context).pop();
              widget.onDismissed?.call();
            }
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendResponse({
    required String action,
    String? selected,
    Map<String, dynamic>? formData,
  }) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    _countdownTimer?.cancel();

    try {
      await widget.api.submitUiResponse(
        _interactionId,
        action: action,
        selected: selected,
        formData: formData,
      );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onDismissed?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit interaction response: $e')),
        );
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _timeoutSec > 0 ? (_remainingSec / _timeoutSec).clamp(0.0, 1.0) : 1.0;

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        side: const BorderSide(color: AppColors.border, width: 1.2),
      ),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.cardRadius)),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.touch_app, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_timeoutSec > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _remainingSec < 10
                            ? AppColors.danger.withValues(alpha: 0.1)
                            : AppColors.surfaceSunken,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _remainingSec < 10
                              ? AppColors.danger.withValues(alpha: 0.3)
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: _remainingSec < 10 ? AppColors.danger : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_remainingSec.toStringAsFixed(1)}s',
                            style: TextStyle(
                              color: _remainingSec < 10 ? AppColors.danger : AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Progress bar for countdown
            if (_timeoutSec > 0)
              LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: AppColors.surfaceSunken,
                color: _remainingSec < 10 ? AppColors.danger : AppColors.primary,
              ),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_message.isNotEmpty) ...[
                      Text(
                        _message,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_imageUrl != null && _imageUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          _imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 120,
                            color: AppColors.surfaceSunken,
                            child: const Center(
                              child: Icon(Icons.broken_image, color: AppColors.textTertiary),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Subtype specific body
                    if (_subtype == 'form' || _fields.isNotEmpty)
                      _buildFormBody()
                    else if (_subtype == 'choices')
                      _buildChoicesBody()
                    else if (_subtype == 'kiosk_destination_picker')
                      _buildKioskPickerBody()
                    else
                      _buildModalBody(),
                  ],
                ),
              ),
            ),

            // Bottom Actions (for form or modal)
            if (_subtype == 'form' || _subtype == 'modal')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppSpacing.cardRadius)),
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => _sendResponse(action: 'cancel'),
                      child: const Text('Cancel / Skip', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textOnPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
                      ),
                      onPressed: _submitting ? null : _handleFormSubmit,
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_subtype == 'form' ? 'Submit Form' : 'Acknowledge'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleFormSubmit() {
    final formState = _formKey.currentState;
    if (_fields.isNotEmpty && formState != null && !formState.validate()) {
      return;
    }
    formState?.save();
    _sendResponse(
      action: 'submit',
      formData: _formData,
    );
  }

  Widget _buildFormBody() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final field in _fields) ...[
            Text(
              '${field.label}${field.required ? ' *' : ''}',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            if (field.type == 'text' || field.type == 'number')
              TextFormField(
                initialValue: field.defaultValue?.toString() ?? '',
                keyboardType: field.type == 'number' ? TextInputType.number : TextInputType.text,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter ${field.label}',
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surfaceSunken,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                validator: (v) {
                  if (field.required && (v == null || v.trim().isEmpty)) {
                    return 'This field is required';
                  }
                  return null;
                },
                onSaved: (v) => _formData[field.key] = v?.trim(),
              )
            else if (field.type == 'select')
              DropdownButtonFormField<String>(
                key: ValueKey('field_${field.key}_${_formData[field.key]}'),
                isExpanded: true,
                initialValue: field.options.contains(_formData[field.key])
                    ? _formData[field.key]
                    : (field.options.isNotEmpty ? field.options.first : null),
                dropdownColor: AppColors.surfaceElevated,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceSunken,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                items: [
                  for (final opt in field.options)
                    DropdownMenuItem(
                      value: opt,
                      child: Text(opt, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => _formData[field.key] = v,
                onSaved: (v) => _formData[field.key] = v,
              )
            else if (field.type == 'checkbox' || field.type == 'switch')
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.primary,
                title: Text(field.label,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                value: _formData[field.key] == true,
                onChanged: (v) => setState(() => _formData[field.key] = v ?? false),
              ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildChoicesBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final choice in _choices) ...[
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5), width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
              backgroundColor: AppColors.surfaceSunken,
            ),
            onPressed: _submitting ? null : () => _sendResponse(action: choice.toString(), selected: choice.toString()),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.arrow_right_alt, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  choice.toString().toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildKioskPickerBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Select your destination station:',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final choice in _choices)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.surfaceSunken,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                  ),
                  side: const BorderSide(color: AppColors.border),
                ),
                icon: const Icon(Icons.place, color: AppColors.primary, size: 18),
                label: Text(choice.toString(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                onPressed: _submitting
                    ? null
                    : () => _sendResponse(action: 'destination_selected', selected: choice.toString()),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildModalBody() {
    return const SizedBox.shrink();
  }
}
