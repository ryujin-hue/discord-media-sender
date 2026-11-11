import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common.dart';

/// A labelled value that is allowed to wrap over several lines.
///
/// The shared [MetricRow] truncates its value, which is the right behaviour
/// for a number or a date but not for a file path or a SHA-256 digest. This
/// row keeps the full value readable and can copy it to the clipboard.
class DetailValueRow extends StatelessWidget {
  const DetailValueRow({
    super.key,
    required this.label,
    required this.value,
    this.monospace = false,
    this.copyable = false,
  });

  /// The name of the value.
  final String label;

  /// The value itself.
  final String value;

  /// Renders the value in a monospace font.
  final bool monospace;

  /// Adds a button that copies the value to the clipboard.
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? valueStyle = monospace
        ? theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')
        : theme.textTheme.bodyMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: SelectableText(value, style: valueStyle)),
            if (copyable) ...<Widget>[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Copy $label',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  showAppSnack(
                    context,
                    '$label copied to clipboard',
                    isSuccess: true,
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
