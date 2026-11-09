import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/formatters.dart';

/// A bar chart that shows the uploads per day.
class ActivityBarChart extends StatelessWidget {
  const ActivityBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.height = 180,
  });

  /// The number of successful and failed uploads per bucket.
  final List<BarChartValue> values;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No activity in this range',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: Column(
        children: <Widget>[
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _BarChartPainter(
                values: values,
                barColor: theme.colorScheme.primary,
                failColor: AppConstants.colorError,
                gridColor: theme.colorScheme.outline.withValues(alpha: 0.18),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 18,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < values.length; i++)
                  Expanded(
                    child: Text(
                      i < labels.length ? labels[i] : '',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One bar of the activity chart.
class BarChartValue {
  const BarChartValue({required this.succeeded, required this.failed});

  final int succeeded;
  final int failed;

  int get total => succeeded + failed;
}

/// Paints the activity bars.
class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.values,
    required this.barColor,
    required this.failColor,
    required this.gridColor,
  });

  final List<BarChartValue> values;
  final Color barColor;
  final Color failColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final int maxValue = values.fold<int>(
      1,
      (int max, BarChartValue v) => math.max(max, v.total),
    );

    final Paint grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (int i = 0; i <= 3; i++) {
      final double y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final double slot = size.width / values.length;
    final double barWidth = math.min(slot * 0.55, 26);

    for (int i = 0; i < values.length; i++) {
      final BarChartValue value = values[i];
      final double totalRatio = value.total / maxValue;
      final double barHeight = totalRatio * (size.height - 8);
      final double x = slot * i + (slot - barWidth) / 2;

      final double successHeight = value.total == 0
          ? 0
          : barHeight * (value.succeeded / value.total);
      final double failHeight = barHeight - successHeight;

      final Paint successPaint = Paint()..color = barColor;
      final Paint failPaint = Paint()..color = failColor;

      if (successHeight > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x,
              size.height - successHeight,
              barWidth,
              successHeight,
            ),
            const Radius.circular(4),
          ),
          successPaint,
        );
      }
      if (failHeight > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - barHeight, barWidth, failHeight),
            const Radius.circular(4),
          ),
          failPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

/// A donut chart showing the success / failure ratio.
class SuccessFailureDonut extends StatelessWidget {
  const SuccessFailureDonut({
    super.key,
    required this.succeeded,
    required this.failed,
    this.size = 150,
  });

  final int succeeded;
  final int failed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = succeeded + failed;
    final double rate = total == 0 ? 0 : (succeeded / total) * 100;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(
              succeeded: succeeded,
              failed: failed,
              successColor: AppConstants.colorSuccess,
              failColor: AppConstants.colorError,
              trackColor: theme.colorScheme.outline.withValues(alpha: 0.16),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                total == 0 ? '—' : Formatters.percent(rate),
                style: theme.textTheme.headlineSmall,
              ),
              Text('success rate', style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.succeeded,
    required this.failed,
    required this.successColor,
    required this.failColor,
    required this.trackColor,
  });

  final int succeeded;
  final int failed;
  final Color successColor;
  final Color failColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.width / 2 - 12;
    final double stroke = 16;

    final Paint track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);

    final int total = succeeded + failed;
    if (total == 0) return;

    final Paint success = Paint()
      ..color = successColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final Paint fail = Paint()
      ..color = failColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final double sweepSuccess = 2 * math.pi * (succeeded / total);
    final double sweepFail = 2 * math.pi * (failed / total);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepSuccess,
      false,
      success,
    );
    if (failed > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2 + sweepSuccess,
        sweepFail,
        false,
        fail,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.succeeded != succeeded || oldDelegate.failed != failed;
}

/// A horizontal bar that visualises a single value against a maximum.
class ProportionBar extends StatelessWidget {
  const ProportionBar({
    super.key,
    required this.value,
    required this.max,
    this.color = AppConstants.colorPrimary,
    this.height = 8,
  });

  final double value;
  final double max;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final double ratio = max <= 0 ? 0 : (value / max).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: ratio,
        minHeight: height,
        backgroundColor: Theme.of(context).colorScheme.outline
            .withValues(alpha: 0.18),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
