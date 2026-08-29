import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/sms_service.dart';
import 'counterparty_screen.dart';

class BreakdownScreen extends StatefulWidget {
  const BreakdownScreen({super.key});

  @override
  State<BreakdownScreen> createState() => _BreakdownScreenState();
}

class _BreakdownScreenState extends State<BreakdownScreen> {
  int _months = 1;
  String _mode = 'merchants';
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = switch (_mode) {
        'categories' => await SmsService.getTopCategories(months: _months),
        'recurring' => await SmsService.getRecurring(),
        _ => await SmsService.getTopCounterparties(months: _months),
      };
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(double value) => NumberFormat('#,##0.00').format(value);

  @override
  Widget build(BuildContext context) {
    final isRecurring = _mode == 'recurring';
    return Scaffold(
      appBar: AppBar(title: const Text('Where it goes')),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'merchants', label: Text('Merchants')),
                      ButtonSegment(value: 'categories', label: Text('Categories')),
                      ButtonSegment(value: 'recurring', label: Text('Recurring')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (selection) {
                      setState(() => _mode = selection.first);
                      _load();
                    },
                  ),
                  if (!isRecurring) ...[
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('This month')),
                        ButtonSegment(value: 3, label: Text('3 months')),
                        ButtonSegment(value: 0, label: Text('All time')),
                      ],
                      selected: {_months},
                      onSelectionChanged: (selection) {
                        setState(() => _months = selection.first);
                        _load();
                      },
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(
                          child: Text(
                            isRecurring
                                ? 'No repeating merchants found yet.\nNeeds at least 3 visits across 2 months.'
                                : _mode == 'categories'
                                    ? 'No categorized spending yet.\nTag categories from the note prompt or edit details.'
                                    : 'No confident spending found for this period.\nConfirm transactions in the Review tab first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).hintColor),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _rows.length,
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            final name = isRecurring
                                ? (row['counterparty'] as String? ?? '')
                                : _mode == 'categories'
                                    ? (row['category'] as String? ?? '')
                                    : (row['counterparty'] as String? ?? '');
                            final currency = row['currency'] as String? ?? '';
                            final total = (row['total'] as num?)?.toDouble() ?? 0;
                            final count = (row['count'] as num?)?.toInt() ?? 0;
                            final subtitle = isRecurring
                                ? '~$currency ${_fmt((row['average'] as num?)?.toDouble() ?? 0)} avg · $count times · ${row['months']} months'
                                : '$count transactions';
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CounterpartyScreen(
                                      counterparty: name,
                                      category: _mode == 'categories' ? name : '',
                                      months: _months,
                                    ),
                                  ),
                                ),
                                leading: CircleAvatar(
                                  child: Text('${index + 1}'),
                                ),
                                title: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(subtitle),
                                trailing: Text(
                                  isRecurring
                                      ? ''
                                      : '$currency ${_fmt(total)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
