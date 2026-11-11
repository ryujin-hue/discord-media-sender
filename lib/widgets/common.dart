import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../services/widget_bridge.dart';

/// A rounded card used for every grouped block of content.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (title != null) ...<Widget>[
              Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title!, style: theme.textTheme.titleMedium),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// A compact metric tile showing an icon, a value and a label.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = color ?? theme.colorScheme.primary;
    return Material(
      color: accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: accent),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 19),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small coloured pill that describes a status.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps a job / library status to a colour and a label.
class StatusStyle {
  StatusStyle(this.color, this.label, this.icon);

  final Color color;
  final String label;
  final IconData icon;

  static StatusStyle forUploadStatus(String status) {
    switch (status) {
      case UploadStatus.completedKey:
        return StatusStyle(
          AppConstants.colorSuccess,
          'Uploaded',
          Icons.check_circle_rounded,
        );
      case UploadStatus.uploadingKey:
        return StatusStyle(
          AppConstants.colorPrimary,
          'Uploading',
          Icons.cloud_upload_rounded,
        );
      case UploadStatus.failedKey:
        return StatusStyle(
          AppConstants.colorError,
          'Failed',
          Icons.error_rounded,
        );
      case UploadStatus.pausedKey:
        return StatusStyle(
          AppConstants.colorWarning,
          'Paused',
          Icons.pause_rounded,
        );
      case UploadStatus.cancelledKey:
        return StatusStyle(
          AppConstants.colorTextSecondary,
          'Cancelled',
          Icons.cancel_rounded,
        );
      default:
        return StatusStyle(
          AppConstants.colorTextSecondary,
          'Pending',
          Icons.schedule_rounded,
        );
    }
  }

  static StatusStyle forMediaStatus(String status) {
    switch (status) {
      case MediaStatus.uploadedKey:
        return StatusStyle(
          AppConstants.colorSuccess,
          'Uploaded',
          Icons.check_circle_rounded,
        );
      case MediaStatus.duplicateDetectedKey:
        return StatusStyle(
          AppConstants.colorWarning,
          'Duplicate',
          Icons.copy_all_rounded,
        );
      case MediaStatus.pendingReviewKey:
        return StatusStyle(
          AppConstants.colorWarning,
          'Review',
          Icons.rate_review_rounded,
        );
      case MediaStatus.uploadingKey:
        return StatusStyle(
          AppConstants.colorPrimary,
          'Uploading',
          Icons.cloud_upload_rounded,
        );
      case MediaStatus.archivedKey:
        return StatusStyle(
          AppConstants.colorTextSecondary,
          'Archived',
          Icons.inventory_2_rounded,
        );
      case MediaStatus.failedKey:
        return StatusStyle(
          AppConstants.colorError,
          'Failed',
          Icons.error_rounded,
        );
      default:
        return StatusStyle(
          AppConstants.colorTextSecondary,
          'New',
          Icons.fiber_new_rounded,
        );
    }
  }
}

/// The empty state placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                message!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A shimmering placeholder shown while data loads.
class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 8,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(
                    alpha: 0.05 + 0.04 * _controller.value,
                  )
                : Colors.black.withValues(
                    alpha: 0.05 + 0.03 * _controller.value,
                  ),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// A label / value row with a fixed label column.
///
/// The label gets a fixed width so that a long label can never squeeze the
/// value into a one-character-per-line column on a narrow screen.
class MetricRow extends StatelessWidget {
  const MetricRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
    this.valueTrailing,
  });

  /// The width of the label column.
  static const double labelWidth = 112;

  final String label;
  final String value;
  final Color? valueColor;

  /// Makes the row tappable, for example to open a link.
  final VoidCallback? onTap;

  /// An optional widget placed after the value, such as a copy button.
  final Widget? valueTrailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: MetricRow.labelWidth,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (valueTrailing != null) ...<Widget>[
            const SizedBox(width: 6),
            valueTrailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}

/// Opens a URL in the browser.
///
/// The platform side handles the intent, so no extra plugin is needed.
Future<void> openUrl(BuildContext context, String url) async {
  final bool opened = await WidgetBridge.instance.openUrl(url);
  if (!opened && context.mounted) {
    showAppSnack(context, 'Could not open $url', isError: true);
  }
}

/// Shows a themed snack bar.
void showAppSnack(
  BuildContext context,
  String message, {
  bool isError = false,
  bool isSuccess = false,
}) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: <Widget>[
          Icon(
            isError
                ? Icons.error_rounded
                : isSuccess
                ? Icons.check_circle_rounded
                : Icons.info_rounded,
            color: isError
                ? AppConstants.colorError
                : isSuccess
                ? AppConstants.colorSuccess
                : Colors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      duration: const Duration(seconds: 4),
    ),
  );
}

/// Shows a confirmation dialog and returns the user's decision.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: AppConstants.colorError,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// A file type icon for a given path / category.
IconData iconForCategory(String category) {
  switch (category) {
    case 'image':
      return Icons.image_rounded;
    case 'video':
      return Icons.movie_rounded;
    case 'audio':
      return Icons.audiotrack_rounded;
    case 'document':
      return Icons.description_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}

/// Formats a size using [Formatters].
String formatBytes(int bytes) => Formatters.bytes(bytes);
