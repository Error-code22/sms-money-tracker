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
  bool _byCategory = false;
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
      final rows = _byCategory
          ? await SmsService.getTopCategories(months: _months)
          : await SmsService.getTopCounterparties(months: _months);
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
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Merchants')),
                      ButtonSegment(value: true, label: Text('Categories')),
                    ],
                    selected: {_byCategory},
                    onSelectionChanged: (selection) {
                      setState(() => _byCategory = selection.first);
                      _load();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(
                          child: Text(
                            _byCategory
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
                            final name = _byCategory
                                ? (row['category'] as String? ?? '')
                                : (row['counterparty'] as String? ?? '');
                            final currency = row['currency'] as String? ?? '';
                            final total = (row['total'] as num?)?.toDouble() ?? 0;
                            final count = (row['count'] as num?)?.toInt() ?? 0;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CounterpartyScreen(
                                      counterparty: _byCategory ? '' : name,
                                      category: _byCategory ? name : '',
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
                                subtitle: Text('$count transactions'),
                                trailing: Text(
                                  '$currency ${_fmt(total)}',
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
