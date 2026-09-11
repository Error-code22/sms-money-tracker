import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import '../services/sms_service.dart';

/// CSV-style transaction list with sorting and note editing.
class CsvScreen extends StatefulWidget {
  const CsvScreen({super.key});

  @override
  State<CsvScreen> createState() => _CsvScreenState();
}

class _CsvScreenState extends State<CsvScreen> {
  List<MoneyTransaction> _allTxs = [];
  bool _loading = true;
  bool _sortAsc = false; // descending by default (highest first)
  String _sortBy = 'date'; // date, amount, counterparty
  final Map<int, TextEditingController> _noteControllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final maps = await SmsService.getTransactions();
      _allTxs = maps.map((m) => MoneyTransaction.fromJson(m)).toList();
      _sort();
      // Create note controllers
      for (final t in _allTxs) {
        _noteControllers[t.id] = TextEditingController(text: t.note);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _sort() {
    _allTxs.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'amount':
          cmp = a.amount.compareTo(b.amount);
          break;
        case 'counterparty':
          cmp = a.counterparty.compareTo(b.counterparty);
          break;
        default: // date
          cmp = a.date.compareTo(b.date);
      }
      return _sortAsc ? cmp : -cmp;
    });
  }

  void _toggleSort(String field) {
    setState(() {
      if (_sortBy == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortBy = field;
        _sortAsc = field == 'counterparty'; // alpha ascending, numeric descending
      }
      _sort();
    });
  }

  Future<void> _saveAll() async {
    int saved = 0;
    for (final t in _allTxs) {
      final ctrl = _noteControllers[t.id];
      if (ctrl == null) continue;
      final note = ctrl.text.trim();
      if (note != t.note) {
        await SmsService.setNote(t.id, note, category: t.category);
        saved++;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $saved notes')),
      );
    }
  }

  Widget _sortHeader(String label, String field) {
    final active = _sortBy == field;
    return GestureDetector(
      onTap: () => _toggleSort(field),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).hintColor,
            ),
          ),
          if (active)
            Icon(
              _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12,
              color: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          TextButton(
            onPressed: _saveAll,
            child: const Text('Save notes'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Sort headers
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _sortHeader('Date', 'date'),
                      ),
                      Expanded(
                        flex: 3,
                        child: _sortHeader('Counterparty', 'counterparty'),
                      ),
                      Expanded(
                        flex: 2,
                        child: _sortHeader('Amount', 'amount'),
                      ),
                    ],
                  ),
                ),
                // Transaction list
                Expanded(
                  child: _allTxs.isEmpty
                      ? const Center(child: Text('No transactions'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _allTxs.length,
                          itemBuilder: (context, index) {
                            final t = _allTxs[index];
                            final ctrl = _noteControllers[t.id];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 4),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Row 1: Date | Counterparty | Amount
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            DateFormat('d MMM yy').format(t.date),
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            t.counterparty.isNotEmpty ? t.counterparty : t.sender,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            '${t.type == 'debit' ? '-' : '+'}Ksh ${t.amount.round()}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: t.type == 'debit' ? Colors.red : Colors.green,
                                            ),
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Row 2: Note input
                                    if (ctrl != null)
                                      TextField(
                                        controller: ctrl,
                                        decoration: InputDecoration(
                                          hintText: 'Add note...',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(6),
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          isDense: true,
                                        ),
                                        maxLines: null,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    for (final c in _noteControllers.values) { c.dispose(); }
    super.dispose();
  }
}
