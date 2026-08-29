import 'dart:math';
import 'package:flutter/material.dart';
import '../models/transaction.dart';

/// A real-time burn rate indicator showing spending velocity.
/// Differentiator: not just "what you spent" but "how fast you're spending it".
class SpendingSpeedCard extends StatefulWidget {
  final List<MoneyTransaction> transactions;
  final int months;

  const SpendingSpeedCard({
    super.key,
    required this.transactions,
    this.months = 3,
  });

  @override
  State<SpendingSpeedCard> createState() => _SpendingSpeedCardState();
}

class _SpendingSpeedCardState extends State<SpendingSpeedCard> {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysPassed = now.difference(currentMonthStart).inDays + 1;

    // Current month spending
    final currentMonthSpend = widget.transactions
        .where((t) =>
            t.date.isAfter(currentMonthStart.subtract(const Duration(days: 1))) &&
            t.date.isBefore(now.add(const Duration(days: 1))) &&
            t.type == 'debit' &&
            t.isConfident)
        .fold<double>(0, (sum, t) => sum + t.amount);

    // Daily burn rate (current month)
    final dailyBurn = daysPassed > 0 ? currentMonthSpend / daysPassed : 0.0;

    // Historical average daily spend (previous months)
    final prevMonthsSpend = widget.transactions
        .where((t) =>
            t.date.isAfter(currentMonthStart.subtract(const Duration(days: 90))) &&
            t.date.isBefore(currentMonthStart) &&
            t.type == 'debit' &&
            t.isConfident)
        .fold<double>(0, (sum, t) => sum + t.amount);

    final prevMonthsDays = min(90, now.difference(
      DateTime(currentMonthStart.year, currentMonthStart.month - widget.months, 1)
    ).inDays);
    final avgDaily = prevMonthsDays > 0 ? prevMonthsSpend / prevMonthsDays : dailyBurn;

    // Projection
    final projectedTotal = dailyBurn * daysInMonth;
    final projectedVsAvg = avgDaily > 0 ? ((dailyBurn - avgDaily) / avgDaily * 100) : 0;

    // Speed ratio (1.0 = average, >1.0 = faster than average)
    final speedRatio = avgDaily > 0 ? (dailyBurn / avgDaily) : 1.0;

    // Speed level
    String speedLabel;
    Color speedColor;
    if (speedRatio < 0.7) {
      speedLabel = 'Slow';
      speedColor = Colors.green;
    } else if (speedRatio < 1.0) {
      speedLabel = 'Normal';
      speedColor = Colors.blue;
    } else if (speedRatio < 1.3) {
      speedLabel = 'Fast';
      speedColor = Colors.orange;
    } else {
      speedLabel = 'Danger';
      speedColor = Colors.red;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Spending speed',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: speedColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    speedLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: speedColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Burn rate gauge
            Row(
              children: [
                // Speedometer
                SizedBox(
                  width: 100,
                  height: 60,
                  child: CustomPaint(
                    painter: _SpeedometerPainter(
                      ratio: speedRatio.clamp(0, 2),
                      color: speedColor,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ksh ${dailyBurn.round()}/day',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        avgDaily > 0
                            ? 'Your avg: Ksh ${avgDaily.round()}/day'
                            : 'No history yet',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Projection
            Row(
              children: [
                Icon(
                  projectedVsAvg > 0 ? Icons.trending_up : Icons.trending_down,
                  size: 16,
                  color: projectedVsAvg > 0 ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    avgDaily > 0
                        ? 'At this rate: Ksh ${projectedTotal.round()} by month end (${projectedVsAvg > 0 ? '+' : ''}${projectedVsAvg.round()}% vs avg)'
                        : 'Projecting Ksh ${projectedTotal.round()} for the month',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Days indicator
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Theme.of(context).hintColor),
                const SizedBox(width: 4),
                Text(
                  'Day $daysPassed of $daysInMonth',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                ),
                const Spacer(),
                Text(
                  '${daysInMonth - daysPassed} days left',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double ratio;
  final Color color;

  _SpeedometerPainter({required this.ratio, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.8);
    final radius = size.width * 0.4;

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      pi,
      false,
      bgPaint,
    );

    // Colored arc (speed)
    final speedPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final sweepAngle = pi * (ratio / 2).clamp(0, 1);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      sweepAngle,
      false,
      speedPaint,
    );

    // Needle
    final needleAngle = pi + sweepAngle;
    final needlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final needleEnd = Offset(
      center.dx + cos(needleAngle) * radius * 0.8,
      center.dy + sin(needleAngle) * radius * 0.8,
    );
    canvas.drawLine(center, needleEnd, needlePaint);

    // Center dot
    canvas.drawCircle(center, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SpeedometerPainter oldDelegate) =>
      ratio != oldDelegate.ratio || color != oldDelegate.color;
}
