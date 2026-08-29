import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/sms_service.dart';

class Budget {
  final String target; // "category:Food" or "merchant:NAIVAS"
  final String label;
  final double limit;
  final String currency;

  const Budget({
    required this.target,
    required this.label,
    required this.limit,
    required this.currency,
  });

  Map<String, dynamic> toJson() => {
        'target': target,
        'label': label,
        'limit': limit,
        'currency': currency,
      };

  static Budget fromJson(Map<String, dynamic> json) => Budget(
        target: json['target'] as String? ?? '',
        label: json['label'] as String? ?? '',
        limit: (json['limit'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? '',
      );
}

class Budgets {
  static const _key = 'budgets';

  static Future<List<Budget>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((b) => Budget.fromJson(Map<String, dynamic>.from(b as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Budget> budgets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(budgets.map((b) => b.toJson()).toList()));
  }
}

/// Settings entry to add/remove monthly budget caps.
Future<void> showBudgetsDialog(BuildContext context, {required VoidCallback onChanged}) async {
  final budgets = await Budgets.load();
  if (!context.mounted) return;
  String kind = 'category';
  final nameController = TextEditingController();
  final limitController = TextEditingController();
  final currencyController = TextEditingController(text: 'KES');

  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Budgets'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Monthly caps on spending. You get a notification at 80% and the home screen shows a progress bar.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 8),
              if (budgets.isEmpty)
                Text(
                  'No budgets yet.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                ),
              for (var i = 0; i < budgets.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${budgets[i].label} — ${budgets[i].currency} ${budgets[i].limit.toStringAsFixed(0)}/month',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      budgets.removeAt(i);
                      await Budgets.save(budgets);
                      setState(() {});
                      onChanged();
                    },
                  ),
                ),
              const Divider(),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'category', label: Text('Category')),
                  ButtonSegment(value: 'merchant', label: Text('Merchant')),
                ],
                selected: {kind},
                onSelectionChanged: (s) => setState(() => kind = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: kind == 'category' ? 'Category (e.g. Food)' : 'Merchant (e.g. NAIVAS)',
                  isDense: true,
                ),
              ),
              TextField(
                controller: limitController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monthly limit', isDense: true),
              ),
              TextField(
                controller: currencyController,
                decoration: const InputDecoration(labelText: 'Currency (e.g. KES)', isDense: true),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final limit = double.tryParse(limitController.text.trim());
                    if (name.isEmpty || limit == null || limit <= 0) return;
                    budgets.add(
                      Budget(
                        target: '$kind:$name',
                        label: name,
                        limit: limit,
                        currency: currencyController.text.trim().toUpperCase(),
                      ),
                    );
                    await Budgets.save(budgets);
                    nameController.clear();
                    limitController.clear();
                    setState(() {});
                    onChanged();
                  },
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}

/// Progress card on the home screen.
class BudgetsCard extends StatefulWidget {
  const BudgetsCard({super.key});

  @override
  State<BudgetsCard> createState() => _BudgetsCardState();
}

class _BudgetsCardState extends State<BudgetsCard> {
  List<Budget> _budgets = [];
  Map<String, double> _spends = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final budgets = await Budgets.load();
      final spends = <String, double>{};
      for (final b in budgets) {
        spends[b.target] = await SmsService.getBudgetSpend(target: b.target, months: 1);
      }
      if (mounted) {
        setState(() {
          _budgets = budgets;
          _spends = spends;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_budgets.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Budgets', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final b in _budgets) ...[
              _BudgetRow(budget: b, spend: _spends[b.target] ?? 0),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.budget, required this.spend});

  final Budget budget;
  final double spend;

  @override
  Widget build(BuildContext context) {
    final ratio = budget.limit <= 0 ? 0.0 : spend / budget.limit;
    final color = ratio >= 1
        ? const Color(0xFFE53935)
        : ratio >= 0.8
            ? const Color(0xFFFB8C00)
            : const Color(0xFF43A047);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                budget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            Text(
              '${budget.currency} ${_fmt(spend)} / ${_fmt(budget.limit)}',
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: ratio.clamp(0.0, 1.0),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
          backgroundColor: color.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ],
    );
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
