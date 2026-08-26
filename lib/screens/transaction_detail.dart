import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import 'transaction_form.dart';

/// Full-message detail dialog. Also the single entry point for editing.
Future<void> showTransactionDetail(
  BuildContext context,
  MoneyTransaction tx, {
  required Future<void> Function() onChanged,
}) {
  final color = tx.isDebit ? const Color(0xFFE53935) : const Color(0xFF43A047);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tx.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(
            tx.formatAmount(),
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 18),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tx.sender.isNotEmpty) _field(context, 'Sender', tx.sender),
            _field(
              context,
              'Date',
              DateFormat('EEEE, d MMMM yyyy · h:mm a').format(tx.date),
            ),
            _field(context, 'Type', tx.isDebit ? 'Money out' : 'Money in'),
            if (tx.currency.isNotEmpty) _field(context, 'Currency', tx.currency),
            if (tx.category.isNotEmpty) _field(context, 'Category', tx.category),
            if (tx.interest != null && tx.interest! > 0)
              _field(
                context,
                'Interest',
                '${tx.interest!.toStringAsFixed(2)} ${tx.currency}',
              ),
            _field(context, 'Status', tx.isConfident ? 'Confirmed' : 'Needs review'),
            if (tx.isManual) _field(context, 'Source', 'Manual entry'),
            const SizedBox(height: 8),
            Text(
              tx.isManual ? 'Note' : 'Message',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            SelectableText(tx.body.isEmpty ? (tx.note.isEmpty ? '—' : tx.note) : tx.body),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final saved = await TransactionFormDialog.show(dialogContext, initial: tx);
            if (saved == true && dialogContext.mounted) {
              Navigator.pop(dialogContext);
              await onChanged();
            }
          },
          icon: const Icon(Icons.edit),
          label: const Text('Edit'),
        ),
      ],
    ),
  );
}

Widget _field(BuildContext context, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
