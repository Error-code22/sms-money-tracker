import 'dart:math' as math;

import 'package:flutter/material.dart';

class DailyChart extends StatelessWidget {
  final List<double> dailySpent;
  final List<double> cumCurrent;
  final List<double> cumPrevious;
  final Color primaryColor;

  const DailyChart({
    super.key,
    required this.dailySpent,
    required this.cumCurrent,
    required this.cumPrevious,
    required this.primaryColor,
  });

  static const double leftPad = 38;
  static const double topPad = 8;
  static const double bottomPad = 20;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: CustomPaint(
        size: Size.infinite,
        painter: _DailyPainter(
          dailySpent,
          cumCurrent,
          cumPrevious,
          Theme.of(context).hintColor,
          primaryColor,
        ),
      ),
    );
  }
}

class _DailyPainter extends CustomPainter {
  final List<double> dailySpent;
  final List<double> cumCurrent;
  final List<double> cumPrevious;
  final Color labelColor;
  final Color primaryColor;

  _DailyPainter(
    this.dailySpent,
    this.cumCurrent,
    this.cumPrevious,
    this.labelColor,
    this.primaryColor,
  );

  double _centerX(int i, double plotWidth, int n) =>
      DailyChart.leftPad + plotWidth * (i + 0.5) / n;

  @override
  void paint(Canvas canvas, Size size) {
    final n = dailySpent.length;
    if (n == 0) return;

    final leftPad = DailyChart.leftPad;
    final topPad = DailyChart.topPad;
    final bottomPad = DailyChart.bottomPad;
    final plotWidth = size.width - leftPad;
    final chartHeight = size.height - bottomPad - topPad;

    final maxVal = [
      ...dailySpent,
      ...cumCurrent,
      ...cumPrevious,
    ].fold(0.0, math.max);
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
        text: TextSpan(text: _fmtK(value), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    // Daily spent bars.
    final barW = math.min(plotWidth / n * 0.6, 10.0);
    final barPaint = Paint()..color = const Color(0xFFE53935);
    for (var i = 0; i < n; i++) {
      final v = dailySpent[i];
      if (v <= 0) continue;
      final h = (v / effectiveMax) * chartHeight;
      final x = _centerX(i, plotWidth, n) - barW / 2;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, topPad + chartHeight - h, barW, h),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        barPaint,
      );
    }

    // Cumulative lines.
    _drawCumLine(canvas, cumCurrent, n, plotWidth, topPad, chartHeight, effectiveMax,
        primaryColor, dashed: false);
    _drawCumLine(canvas, cumPrevious, n, plotWidth, topPad, chartHeight, effectiveMax,
        labelColor, dashed: true);

    // X labels: 1, 8, 15, 22, last day.
    final dayLabelStyle = TextStyle(fontSize: 9, color: labelColor);
    for (final i in {0, 7, 14, 21, n - 1}) {
      if (i >= n) continue;
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: dayLabelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(_centerX(i, plotWidth, n) - tp.width / 2, size.height - bottomPad + 3),
      );
    }
  }

  void _drawCumLine(
    Canvas canvas,
    List<double> values,
    int n,
    double plotWidth,
    double topPad,
    double chartHeight,
    double effectiveMax,
    Color color, {
    required bool dashed,
  }) {
    if (values.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      points.add(Offset(
        _centerX(i, plotWidth, n),
        topPad + chartHeight - (values[i] / effectiveMax) * chartHeight,
      ));
    }
    if (!dashed) {
      if (points.length > 1) {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final p in points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
      if (points.isNotEmpty) {
        canvas.drawCircle(points.last, 3, Paint()..color = color);
      }
      return;
    }
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      var t = 0.0;
      const dash = 6.0;
      const gap = 4.0;
      final length = (b - a).distance;
      while (t < length) {
        final end = math.min(t + dash, length);
        canvas.drawLine(
          Offset(
            a.dx + (b.dx - a.dx) * (t / length),
            a.dy + (b.dy - a.dy) * (t / length),
          ),
          Offset(
            a.dx + (b.dx - a.dx) * (end / length),
            a.dy + (b.dy - a.dy) * (end / length),
          ),
          paint,
        );
        t += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DailyPainter oldDelegate) =>
      oldDelegate.dailySpent != dailySpent ||
      oldDelegate.cumCurrent != cumCurrent ||
      oldDelegate.cumPrevious != cumPrevious ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.primaryColor != primaryColor;
}

String _fmtK(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}m';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
  return v.round().toString();
}
