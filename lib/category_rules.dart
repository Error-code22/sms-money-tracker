import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> kPresetCategories = [
  'Food',
  'Transport',
  'Shopping',
  'Bills',
  'Airtime',
  'Family',
  'Income',
];

class CategoryRules {
  static const _rulesKey = 'tag_rules';

  static Future<List<Map<String, String>>> loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_rulesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((r) => Map<String, String>.from(r as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRules(List<Map<String, String>> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rulesKey, jsonEncode(rules));
  }

  /// Returns the category if any rule keyword appears in [note].
  static String? apply(String note, List<Map<String, String>> rules) {
    if (note.trim().isEmpty) return null;
    final lower = note.toLowerCase();
    for (final rule in rules) {
      final keyword = (rule['keyword'] ?? '').toLowerCase();
      if (keyword.isNotEmpty && lower.contains(keyword)) {
        return rule['category'];
      }
    }
    return null;
  }
}

/// Manage auto-tagging rules: "if the note contains X, tag it Y".
Future<void> showCategoryRulesDialog(BuildContext context) async {
  final rules = await CategoryRules.loadRules();
  if (!context.mounted) return;
  final keywordController = TextEditingController();
  final categoryController = TextEditingController();

  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Category rules'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'When you save a note, if it contains the keyword, the transaction '
                'gets the category automatically. Empty note never matches.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 8),
              if (rules.isEmpty)
                Text(
                  'No rules yet.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                ),
              for (var i = 0; i < rules.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('"${rules[i]['keyword']}" → ${rules[i]['category']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      rules.removeAt(i);
                      await CategoryRules.saveRules(rules);
                      setState(() {});
                    },
                  ),
                ),
              const Divider(),
              TextField(
                controller: keywordController,
                decoration: const InputDecoration(
                  labelText: 'Keyword (e.g. fare)',
                  isDense: true,
                ),
              ),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(
                  labelText: 'Category (e.g. Transport)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    final keyword = keywordController.text.trim();
                    final category = categoryController.text.trim();
                    if (keyword.isEmpty || category.isEmpty) return;
                    rules.add({'keyword': keyword, 'category': category});
                    await CategoryRules.saveRules(rules);
                    keywordController.clear();
                    categoryController.clear();
                    setState(() {});
                  },
                  child: const Text('Add rule'),
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
