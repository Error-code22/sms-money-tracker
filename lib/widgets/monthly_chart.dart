import 'dart:math' as math;

import 'package:flutter/material.dart';

class MonthlyChart extends StatelessWidget {
  final List<Map<String, dynamic>> totals;
  final Color netColor;

  const MonthlyChart({super.key, required this.totals, required this.netColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: CustomPaint(
        size: Size.infinite,
        painter: _ChartPainter(totals, Theme.of(context).hintColor, netColor),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> totals;
  final Color labelColor;
  final Color netColor;

  _ChartPainter(this.totals, this.labelColor, this.netColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (totals.isEmpty) return;

    final maxVal = totals
        .expand((t) => [(t['spent'] as num).toDouble(), (t['received'] as num).toDouble()])
        .reduce(math.max);
    final effectiveMax = maxVal == 0 ? 1.0 : maxVal;

    const bottomPad = 22.0;
    const topPad = 8.0;
    final chartHeight = size.height - bottomPad - topPad;
    final groupWidth = size.width / totals.length;
    final barWidth = math.min(groupWidth * 0.28, 18.0);

    final gridPaint = Paint()
      ..color = labelColor.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + chartHeight * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final spentPaint = Paint()..color = const Color(0xFFE53935);
    final receivedPaint = Paint()..color = const Color(0xFF43A047);
    final labelStyle = TextStyle(fontSize: 10, color: labelColor);

    for (var i = 0; i < totals.length; i++) {
      final t = totals[i];
      final spent = (t['spent'] as num).toDouble();
      final received = (t['received'] as num).toDouble();
      final spentH = (spent / effectiveMax) * chartHeight;
      final receivedH = (received / effectiveMax) * chartHeight;

      final centerX = groupWidth * i + groupWidth / 2;

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

      final month = t['month'] as String;
      final label = month.substring(5);
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(centerX - tp.width / 2, size.height - bottomPad + 4),
      );
    }

    // Net line (received - spent) per month, drawn over the bars.
    final netValues = totals
        .map((t) => (t['received'] as num).toDouble() - (t['spent'] as num).toDouble())
        .toList();
    final foldedNet =
        netValues.fold(0.0, (m, v) => math.max(m, v.abs()));
    final maxAbsNet = foldedNet == 0 ? 1.0 : foldedNet;
    final netPaint = Paint()
      ..color = netColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..color = netColor;
    final points = <Offset>[];
    for (var i = 0; i < netValues.length; i++) {
      final x = groupWidth * i + groupWidth / 2;
      final y = topPad + chartHeight / 2 - (netValues[i] / maxAbsNet) * (chartHeight / 2);
      points.add(Offset(x, y));
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
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.totals != totals ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.netColor != netColor;
}
