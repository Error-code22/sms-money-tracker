import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import '../services/sms_service.dart';
import 'transaction_detail.dart';

class CounterpartyScreen extends StatefulWidget {
  const CounterpartyScreen({
    super.key,
    required this.counterparty,
    this.category = '',
    required this.months,
  });

  final String counterparty;
  final String category;
  final int months;

  @override
  State<CounterpartyScreen> createState() => _CounterpartyScreenState();
}

class _CounterpartyScreenState extends State<CounterpartyScreen> {
  List<MoneyTransaction> _transactions = [];
  bool _loading = true;

  String get _title => widget.category.isNotEmpty ? widget.category : widget.counterparty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = widget.category.isNotEmpty
          ? await SmsService.getCategoryTransactions(
              category: widget.category,
              months: widget.months,
            )
          : await SmsService.getCounterpartyTransactions(
              counterparty: widget.counterparty,
              months: widget.months,
            );
      if (mounted) {
        setState(() => _transactions = rows.map(MoneyTransaction.fromJson).toList());
      }
    } catch (_) {
      if (mounted) setState(() => _transactions = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE, d MMM yyyy · h:mm a');
    return Scaffold(
      appBar: AppBar(
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        bottom: true,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _transactions.isEmpty
                ? Center(
                    child: Text(
                      'No confident spending found for this period.',
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => showTransactionDetail(
                            context,
                            tx,
                            onChanged: _load,
                          ),
                          title: Text(
                            tx.note.isNotEmpty ? tx.note : tx.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(dateFmt.format(tx.date)),
                          trailing: Text(
                            tx.formatAmount(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: tx.isDebit
                                  ? const Color(0xFFE53935)
                                  : const Color(0xFF43A047),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
