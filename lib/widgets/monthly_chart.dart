import 'dart:math' as math;

import 'package:flutter/material.dart';

class MonthlyChart extends StatelessWidget {
  final List<Map<String, dynamic>> totals;
  final Color netColor;
  final double? budgetLimit;
  final String budgetLabel;
  final void Function(int index)? onMonthTap;

  const MonthlyChart({
    super.key,
    required this.totals,
    required this.netColor,
    this.budgetLimit,
    this.budgetLabel = '',
    this.onMonthTap,
  });

  static const double leftPad = 38;
  static const double bottomPad = 22;
  static const double topPad = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final n = totals.length;
        return GestureDetector(
          onTapUp: onMonthTap == null || n == 0
              ? null
              : (details) {
                  final plotWidth = width - leftPad;
                  final index = ((details.localPosition.dx - leftPad) / (plotWidth / n)).floor();
                  if (index >= 0 && index < n) onMonthTap!(index);
                },
          child: SizedBox(
            height: 180,
            width: width,
            child: CustomPaint(
              size: Size(width, 180),
              painter: _ChartPainter(
                totals,
                Theme.of(context).hintColor,
                netColor,
                budgetLimit,
                budgetLabel,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> totals;
  final Color labelColor;
  final Color netColor;
  final double? budgetLimit;
  final String budgetLabel;

  _ChartPainter(this.totals, this.labelColor, this.netColor, this.budgetLimit, this.budgetLabel);

  static String fmtK(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}m';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    return v.round().toString();
  }

  double _centerX(int i, double plotWidth, int n) =>
      MonthlyChart.leftPad + plotWidth * (i + 0.5) / n;

  @override
  void paint(Canvas canvas, Size size) {
    if (totals.isEmpty) return;

    final leftPad = MonthlyChart.leftPad;
    final topPad = MonthlyChart.topPad;
    final bottomPad = MonthlyChart.bottomPad;
    final plotWidth = size.width - leftPad;
    final chartHeight = size.height - bottomPad - topPad;
    final n = totals.length;

    final maxVal = totals
        .expand((t) => [(t['spent'] as num).toDouble(), (t['received'] as num).toDouble()])
        .reduce(math.max);
    final effectiveMax = maxVal == 0 ? 1.0 : maxVal;

    final gridPaint = Paint()
      ..color = labelColor.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final labelStyle = TextStyle(fontSize: 9, color: labelColor);
    for (var i = 0; i <= 3; i++) {
      final y = topPad + chartHeight * i / 3;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      final value = effectiveMax * (3 - i) / 3;
      final tp = TextPainter(
        text: TextSpan(text: fmtK(value), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    final barWidth = math.min(plotWidth / n * 0.28, 18.0);
    final spentPaint = Paint()..color = const Color(0xFFE53935);
    final receivedPaint = Paint()..color = const Color(0xFF43A047);
    final monthLabelStyle = TextStyle(fontSize: 10, color: labelColor);

    for (var i = 0; i < n; i++) {
      final t = totals[i];
      final spent = (t['spent'] as num).toDouble();
      final received = (t['received'] as num).toDouble();
      final spentH = (spent / effectiveMax) * chartHeight;
      final receivedH = (received / effectiveMax) * chartHeight;
      final centerX = _centerX(i, plotWidth, n);

      final spentRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(centerX - barWidth - 2, topPad + chartHeight - spentH, barWidth, spentH),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      final receivedRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(centerX + 2, topPad + chartHeight - receivedH, barWidth, receivedH),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      if (spentH > 0) canvas.drawRRect(spentRect, spentPaint);
      if (receivedH > 0) canvas.drawRRect(receivedRect, receivedPaint);

      final label = (t['month'] as String).substring(5);
      final tp = TextPainter(
        text: TextSpan(text: label, style: monthLabelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(centerX - tp.width / 2, size.height - bottomPad + 4),
      );
    }

    // Net line (received - spent) per month.
    final netValues = totals
        .map((t) => (t['received'] as num).toDouble() - (t['spent'] as num).toDouble())
        .toList();
    final foldedNet = netValues.fold(0.0, (m, v) => math.max(m, v.abs()));
    final maxAbsNet = foldedNet == 0 ? 1.0 : foldedNet;
    final netPaint = Paint()
      ..color = netColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..color = netColor;
    final points = <Offset>[];
    for (var i = 0; i < netValues.length; i++) {
      points.add(Offset(
        _centerX(i, plotWidth, n),
        topPad + chartHeight / 2 - (netValues[i] / maxAbsNet) * (chartHeight / 2),
      ));
    }
    if (points.length > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, netPaint);
    }
    for (final p in points) {
      canvas.drawCircle(p, 3, dotPaint);
    }

    // Budget cap line.
    final limit = budgetLimit;
    if (limit != null && limit > 0) {
      var y = topPad + chartHeight * (1 - limit / effectiveMax);
      y = y.clamp(topPad, topPad + chartHeight);
      final capPaint = Paint()
        ..color = const Color(0xFFFB8C00)
        ..strokeWidth = 1.5;
      var x = leftPad;
      const dash = 6.0;
      const gap = 4.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + dash, size.width), y),
          capPaint,
        );
        x += dash + gap;
      }
      if (budgetLabel.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'Cap $budgetLabel',
            style: TextStyle(fontSize: 9, color: const Color(0xFFFB8C00)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - tp.width - 2, y - tp.height - 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.totals != totals ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.netColor != netColor ||
      oldDelegate.budgetLimit != budgetLimit ||
      oldDelegate.budgetLabel != budgetLabel;
}
