import 'dart:convert';

/// Shared JSON helpers for the Tools screen's three panels (topics/
/// services/actions) — all of them read a request/goal body as free-form
/// JSON text and render a response/message as pretty JSON, so this is the
/// one place that logic lives instead of being copy-pasted three times.
class JsonUtils {
  JsonUtils._();

  static const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

  /// Pretty-prints any JSON-compatible value. Falls back to `toString()`
  /// for anything `jsonEncode` can't handle rather than throwing — this is
  /// a read-only debug view, it should never crash the screen.
  static String pretty(dynamic value) {
    try {
      return _pretty.convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  /// Parses [text] as a JSON object (`{...}`), which is what every rosapi
  /// call in this app expects for request/goal args. Returns null with an
  /// error message on anything else — empty input is treated as `{}`
  /// rather than an error, since most calls here take no arguments.
  static (Map<String, dynamic>?, String?) parseArgs(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return (<String, dynamic>{}, null);
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return (decoded, null);
      return (null, 'Must be a JSON object, e.g. {"key": "value"}');
    } on FormatException catch (e) {
      return (null, 'Invalid JSON: ${e.message}');
    }
  }
}
