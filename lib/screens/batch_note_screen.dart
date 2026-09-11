import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import '../services/sms_service.dart';

/// Batch note editor: pick a month, see all transactions, type notes for each.
class BatchNoteScreen extends StatefulWidget {
  const BatchNoteScreen({super.key});

  @override
  State<BatchNoteScreen> createState() => _BatchNoteScreenState();
}

class _BatchNoteScreenState extends State<BatchNoteScreen> {
  List<MoneyTransaction> _allTxs = [];
  List<MoneyTransaction> _filtered = [];
  bool _loading = true;
  DateTime _selectedMonth = DateTime.now();
  final Map<int, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final maps = await SmsService.getTransactions();
      _allTxs = maps.map((m) => MoneyTransaction.fromJson(m)).toList();
      if (_availableMonths.isNotEmpty) {
        _selectedMonth = _availableMonths.first;
      }
      _filter();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _filter() {
    _filtered = _allTxs.where((t) =>
        t.date.year == _selectedMonth.year &&
        t.date.month == _selectedMonth.month).toList();
    _filtered.sort((a, b) => b.date.compareTo(a.date));
    // Dispose old controllers
    for (final c in _controllers.values) { c.dispose(); }
    _controllers.clear();
    // Create controllers for transactions without notes
    for (final t in _filtered) {
      _controllers[t.id] = TextEditingController(text: t.note);
    }
  }

  List<DateTime> get _availableMonths {
    final months = <DateTime>{};
    for (final t in _allTxs) {
      months.add(DateTime(t.date.year, t.date.month));
    }
    final list = months.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  Future<void> _saveAll() async {
    int saved = 0;
    for (final t in _filtered) {
      final ctrl = _controllers[t.id];
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
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit notes by month'),
        actions: [
          TextButton(
            onPressed: _saveAll,
            child: const Text('Save all'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Month selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<DateTime>(
                            value: _selectedMonth,
                            isDense: true,
                            items: _availableMonths.map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(DateFormat('MMMM yyyy').format(m)),
                            )).toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _selectedMonth = v;
                                _filter();
                              });
                            },
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          '${_filtered.length} tx',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Transaction list
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(child: Text('No transactions this month'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final t = _filtered[index];
                            final ctrl = _controllers[t.id]!;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          t.type == 'debit' ? Icons.arrow_upward : Icons.arrow_downward,
                                          size: 16,
                                          color: t.type == 'debit' ? Colors.red : Colors.green,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            t.counterparty.isNotEmpty ? t.counterparty : t.sender,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            'Ksh ${t.amount.round()}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: t.type == 'debit' ? Colors.red : Colors.green,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('EEE, d MMM yyyy • HH:mm').format(t.date),
                                      style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: ctrl,
                                      decoration: InputDecoration(
                                        hintText: 'Add note...',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide.none,
                                        ),
                                        filled: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        isDense: true,
                                        suffixIcon: ctrl.text.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(Icons.clear, size: 16),
                                                onPressed: () => setState(() => ctrl.clear()),
                                              )
                                            : null,
                                      ),
                                      maxLines: null,
                                      onChanged: (_) => setState(() {}),
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
    for (final c in _controllers.values) { c.dispose(); }
    super.dispose();
  }
}
