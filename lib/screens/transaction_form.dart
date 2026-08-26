import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import '../services/sms_service.dart';

/// Shared form for adding manual transactions and editing existing ones.
/// Returns true if something was saved.
class TransactionFormDialog extends StatefulWidget {
  final MoneyTransaction? initial;
  final String defaultCurrency;

  const TransactionFormDialog({super.key, this.initial, required this.defaultCurrency});

  static Future<bool?> show(
    BuildContext context, {
    MoneyTransaction? initial,
    String defaultCurrency = 'KES',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => TransactionFormDialog(initial: initial, defaultCurrency: defaultCurrency),
    );
  }

  @override
  State<TransactionFormDialog> createState() => _TransactionFormDialogState();
}

class _TransactionFormDialogState extends State<TransactionFormDialog> {
  late String _type;
  late DateTime _dateTime;
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _category;
  late final TextEditingController _counterparty;
  late final TextEditingController _note;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _type = initial?.type ?? 'debit';
    _dateTime = initial?.date ?? DateTime.now();
    _amount = TextEditingController(
      text: initial != null
          ? (initial.amount == initial.amount.roundToDouble()
              ? initial.amount.toStringAsFixed(0)
              : initial.amount.toString())
          : '',
    );
    _currency = TextEditingController(
      text: initial != null && initial.currency.isNotEmpty
          ? initial.currency
          : widget.defaultCurrency,
    );
    _category = TextEditingController(text: initial?.category ?? '');
    _counterparty = TextEditingController(text: initial?.counterparty ?? '');
    _note = TextEditingController(text: initial?.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _category.dispose();
    _counterparty.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _showNote => widget.initial == null || widget.initial!.isManual;

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (!mounted) return;
    setState(() {
      _dateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _dateTime.hour,
        time?.minute ?? _dateTime.minute,
      );
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    final currency = _currency.text.trim().toUpperCase();
    setState(() => _saving = true);
    try {
      if (widget.initial == null) {
        await SmsService.insertManual(
          type: _type,
          amount: amount,
          currency: currency.isEmpty ? widget.defaultCurrency : currency,
          category: _category.text.trim().isEmpty ? null : _category.text.trim(),
          counterparty: _counterparty.text.trim(),
          ts: _dateTime.millisecondsSinceEpoch,
          note: _note.text.trim(),
        );
      } else {
        await SmsService.updateTransaction(
          id: widget.initial!.id,
          type: _type,
          amount: amount,
          currency: currency.isEmpty ? widget.initial!.currency : currency,
          category: _category.text.trim().isEmpty ? null : _category.text.trim(),
          counterparty: _counterparty.text.trim(),
          ts: _dateTime.millisecondsSinceEpoch,
          note: _showNote ? _note.text.trim() : null,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save failed')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit transaction' : 'Add transaction'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'debit', label: Text('Money out'), icon: Icon(Icons.arrow_upward)),
                ButtonSegment(value: 'credit', label: Text('Money in'), icon: Icon(Icons.arrow_downward)),
              ],
              selected: {_type},
              onSelectionChanged: (selection) => setState(() => _type = selection.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            TextField(
              controller: _currency,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Currency (e.g. KES)'),
            ),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Category (optional)'),
            ),
            TextField(
              controller: _counterparty,
              decoration: const InputDecoration(labelText: 'Counterparty'),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(DateFormat('EEE, d MMM yyyy · h:mm a').format(_dateTime)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: _pickDate,
            ),
            if (_showNote)
              TextField(
                controller: _note,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
