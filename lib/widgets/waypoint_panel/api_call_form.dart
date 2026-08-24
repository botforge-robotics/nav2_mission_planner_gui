import 'dart:convert';
import 'package:flutter/material.dart';
import '../../modals/mission.dart';
import 'section_card.dart';

/// Editor for an HTTP API-call mission item (method/URL, headers, body,
/// wait-for-response). Extracted verbatim from waypoint_panel.dart's
/// private `_ApiCallFormContent`/`_ApiCallFormContentState` — already a
/// fully self-contained widget with no coupling to `WaypointPanelState`
/// beyond `item`/`modeColor`/`onChanged`, so this is a pure move with the
/// two classes made public (`_ApiCallFormContent` -> `ApiCallForm`).
class ApiCallForm extends StatefulWidget {
  final MissionItem item;
  final Color modeColor;
  final VoidCallback onChanged;

  const ApiCallForm({
    super.key,
    required this.item,
    required this.modeColor,
    required this.onChanged,
  });

  @override
  State<ApiCallForm> createState() => _ApiCallFormState();
}

class _ApiCallFormState extends State<ApiCallForm> {
  static const _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

  late final TextEditingController _urlController;
  late final TextEditingController _headersController;
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.item.apiUrl ?? '');
    _headersController = TextEditingController(
      text: _formatApiHeadersForEdit(widget.item.apiHeaders),
    );
    _bodyController = TextEditingController(text: widget.item.apiBody ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    _headersController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  String _formatApiHeadersForEdit(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return '';
    return headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }

  Map<String, String>? _parseApiHeaders(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return decoded.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          );
        }
      } catch (_) {
        // Fall through to key:value parsing
      }
    }

    final result = <String, String>{};
    for (final line in trimmed.split('\n')) {
      final lineTrimmed = line.trim();
      if (lineTrimmed.isEmpty) continue;
      final colonIndex = lineTrimmed.indexOf(':');
      if (colonIndex <= 0) continue;
      final key = lineTrimmed.substring(0, colonIndex).trim();
      final value = lineTrimmed.substring(colonIndex + 1).trim();
      if (key.isNotEmpty) {
        result[key] = value;
      }
    }
    return result.isEmpty ? null : result;
  }

  InputDecoration _fieldDecoration({required String hint, String? label}) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[400]),
      hintStyle: TextStyle(color: Colors.grey[600]),
      filled: true,
      fillColor: Colors.grey[850],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[600]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[600]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: widget.modeColor, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final modeColor = widget.modeColor;
    final selectedMethod =
        _methods.contains((item.apiMethod ?? 'POST').toUpperCase())
            ? (item.apiMethod ?? 'POST').toUpperCase()
            : 'POST';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          title: 'Request',
          icon: Icons.http,
          color: modeColor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: modeColor.withOpacity(0.5)),
                  ),
                  child: DropdownButtonFormField<String>(
                    value: selectedMethod,
                    dropdownColor: Colors.grey[800],
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                    items: _methods
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        item.apiMethod = val;
                      });
                      widget.onChanged();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _urlController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration(
                    hint: 'https://api.example.com/endpoint',
                    label: 'URL',
                  ),
                  onChanged: (val) {
                    item.apiUrl = val;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionCard(
          title: 'Headers',
          icon: Icons.list_alt,
          color: modeColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'One header per line as key: value, or a JSON object',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _headersController,
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                maxLines: 4,
                decoration: _fieldDecoration(
                  hint:
                      'Authorization: Bearer token\nContent-Type: application/json',
                ),
                onChanged: (val) {
                  item.apiHeaders = _parseApiHeaders(val);
                  widget.onChanged();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionCard(
          title: 'Body',
          icon: Icons.data_object,
          color: modeColor,
          child: TextFormField(
            controller: _bodyController,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'monospace', fontSize: 13),
            maxLines: 8,
            decoration: _fieldDecoration(
              hint: '{\n  "key": "value"\n}',
              label: 'JSON Body',
            ),
            onChanged: (val) {
              item.apiBody = val;
              widget.onChanged();
            },
          ),
        ),
        const SizedBox(height: 24),
        SectionCard(
          title: 'Response Options',
          icon: Icons.timer,
          color: modeColor,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Wait for Response',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Switch(
                value: item.apiWaitForResponse ?? true,
                onChanged: (v) {
                  setState(() {
                    item.apiWaitForResponse = v;
                  });
                  widget.onChanged();
                },
                activeColor: modeColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
