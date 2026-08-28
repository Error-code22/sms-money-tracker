import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../services/sms_service.dart';

/// Bottom sheet shown when new transactions arrive while the app is open:
/// write the reason before you forget.
Future<void> showNotesPrompt(BuildContext context, List<MoneyTransaction> fresh) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: NotesPromptSheet(fresh: fresh),
    ),
  );
}

class NotesPromptSheet extends StatefulWidget {
  const NotesPromptSheet({super.key, required this.fresh});

  final List<MoneyTransaction> fresh;

  @override
  State<NotesPromptSheet> createState() => _NotesPromptSheetState();
}

class _NotesPromptSheetState extends State<NotesPromptSheet> {
  final Map<int, TextEditingController> _controllers = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final tx in widget.fresh) {
      _controllers[tx.id] = TextEditingController(text: tx.note);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _done() async {
    setState(() => _saving = true);
    try {
      for (final tx in widget.fresh) {
        final note = _controllers[tx.id]?.text.trim() ?? '';
        if (note != tx.note) {
          await SmsService.setNote(tx.id, note);
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save notes')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'New transaction${widget.fresh.length > 1 ? 's' : ''} — what was it for?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Optional. Tap outside to skip — you can add notes later from any transaction.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final tx in widget.fresh)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                tx.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Text(
                              tx.formatAmount(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: tx.isDebit
                                    ? const Color(0xFFE53935)
                                    : const Color(0xFF43A047),
                              ),
                            ),
                          ],
                        ),
                        TextField(
                          controller: _controllers[tx.id],
                          decoration: const InputDecoration(
                            hintText: 'e.g. Jumia order, pocket money, fare...',
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _done,
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
