import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/counterparty_screen.dart';
import '../services/sms_service.dart';

class UpcomingPayment {
  final String name;
  final DateTime date;
  final double amount;
  final String currency;

  const UpcomingPayment({
    required this.name,
    required this.date,
    required this.amount,
    required this.currency,
  });
}

/// Predicts likely upcoming payments from the user's own recurring habits.
/// Everything is computed locally from transactions already on the phone.
class UpcomingCard extends StatefulWidget {
  const UpcomingCard({super.key});

  @override
  State<UpcomingCard> createState() => _UpcomingCardState();
}

class _UpcomingCardState extends State<UpcomingCard> {
  List<UpcomingPayment> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final recurring = await SmsService.getRecurring();
      final txs = await SmsService.getTransactions();
      final now = DateTime.now();
      final horizon = now.add(const Duration(days: 14));
      final items = <UpcomingPayment>[];

      for (final r in recurring) {
        final name = r['counterparty'] as String? ?? '';
        final avg = (r['average'] as num?)?.toDouble() ?? 0;
        final currency = r['currency'] as String? ?? '';
        final dates = txs
            .where((t) =>
                t['counterparty'] == name &&
                (t['type'] as String?) == 'debit' &&
                (t['is_confident'] as num? ?? 0) == 1)
            .map((t) => DateTime.fromMillisecondsSinceEpoch((t['ts'] as num).toInt()))
            .toList()
          ..sort();
        if (dates.length < 2) continue;

        final gaps = <int>[];
        for (var i = 1; i < dates.length; i++) {
          gaps.add(dates[i].difference(dates[i - 1]).inDays);
        }
        gaps.sort();
        final medianGap = gaps[gaps.length ~/ 2];
        if (medianGap < 1) continue;

        final next = dates.last.add(Duration(days: medianGap));
        if (next.isBefore(now) || next.isAfter(horizon)) continue;

        items.add(UpcomingPayment(
          name: name,
          date: next,
          amount: avg,
          currency: currency,
        ));
      }

      items.sort((a, b) => a.date.compareTo(b.date));
      if (mounted) setState(() => _items = items.take(5).toList());
    } catch (_) {
      if (mounted) setState(() => _items = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();
    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);

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
                    'Coming up',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  'Predicted from your habits',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in _items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    DateFormat('d').format(item.date),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                title: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  item.date.isBefore(tomorrow)
                      ? 'Tomorrow'
                      : DateFormat('EEE, d MMM').format(item.date),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                ),
                trailing: Text(
                  '~${item.currency} ${_fmt(item.amount)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CounterpartyScreen(
                      counterparty: item.name,
                      months: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
