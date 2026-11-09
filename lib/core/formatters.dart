import 'dart:math' as math;

/// Human readable formatters used across the UI, analytics and exports.
class Formatters {
  Formatters._();

  static const List<String> _byteUnits = ['B', 'KB', 'MB', 'GB', 'TB'];

  /// Formats a byte count using binary-ish decimal steps (1024).
  static String bytes(int value, {int decimals = 1}) {
    if (value <= 0) return '0 B';
    final int i = (math.log(value) / math.log(1024)).floor().clamp(0, 4);
    final double scaled = value / math.pow(1024, i);
    final String text = scaled >= 100 || i == 0
        ? scaled.toStringAsFixed(0)
        : scaled.toStringAsFixed(decimals);
    return '$text ${_byteUnits[i]}';
  }

  /// Formats a transfer rate.
  static String speed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '—';
    return '${bytes(bytesPerSecond.round())}/s';
  }

  /// Formats a duration expressed in seconds as `1h 02m 03s`.
  static String duration(int? seconds) {
    if (seconds == null || seconds < 0) return '—';
    if (seconds < 60) return '${seconds}s';
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    final int s = seconds % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    }
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  /// Formats a percentage with a single decimal.
  static String percent(double? value) {
    if (value == null) return '—';
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}%';
  }

  /// Formats a transfer rate.
  static String rate(double? value) {
    if (value == null) return '—';
    if (value >= 100) return '${value.toStringAsFixed(0)}/s';
    return '${value.toStringAsFixed(1)}/s';
  }

  /// Truncates a file name in the middle so both extension and stem stay visible.
  static String fileName(String name, {int max = 34}) {
    if (name.length <= max) return name;
    final int dot = name.lastIndexOf('.');
    final String ext = dot > 0 && name.length - dot <= 8
        ? name.substring(dot)
        : '';
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    final int keep = math.max(4, max - ext.length);
    if (stem.length <= keep) return name;
    return '${stem.substring(0, keep - 3)}...$ext';
  }

  /// Masks a secret so it can be displayed without leaking it.
  static String maskSecret(String? value, {int visible = 4}) {
    if (value == null || value.isEmpty) return 'Not set';
    if (value.length <= visible * 2) return '•' * value.length;
    return '${value.substring(0, visible)}${'•' * 8}${value.substring(value.length - visible)}';
  }

  /// Masks a webhook URL, keeping only the numeric id and the host.
  static String maskWebhook(String? url) {
    if (url == null || url.isEmpty) return 'Not set';
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return '•' * 12;
    final List<String> segments = uri.pathSegments;
    final String id = segments.isNotEmpty ? segments[segments.length - 2] : '';
    return '${uri.host}/webhooks/$id/••••••';
  }

  /// Number formatting with thousands separators.
  static String count(num value) {
    final bool isInt = value is int || value == value.roundToDouble();
    final String raw = isInt
        ? value.round().toString()
        : value.toStringAsFixed(1);
    final List<String> parts = raw.split('.');
    final String intPart = parts.first;
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return parts.length > 1
        ? '${buffer.toString()}.${parts[1]}'
        : buffer.toString();
  }
}
