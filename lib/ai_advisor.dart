import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'services/sms_service.dart';

class AiAdvisor {
  static const _keyPref = 'groq_api_key';

  static Future<String> getKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPref) ?? '';
  }

  static Future<void> saveKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPref, key.trim());
  }

  static Future<void> clearKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPref);
  }

  /// Sends only notes/amounts/types of the last 30 days to Groq. Returns the
  /// advice text, or null when the request fails (bad key, offline, etc).
  static Future<String?> ask({required String key}) async {
    try {
      final all = await SmsService.getTransactions();
      final cutoff =
          DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      final data = all
          .where((t) =>
              (t['is_confident'] as num? ?? 0) == 1 &&
              (t['ts'] as num) > cutoff)
          .map((t) => {
                'date': DateTime.fromMillisecondsSinceEpoch((t['ts'] as num).toInt())
                    .toIso8601String()
                    .substring(0, 10),
                'type': t['type'],
                'amount': t['amount'],
                'currency': t['currency'] ?? '',
                'note': t['note'] ?? '',
              })
          .toList();
      if (data.isEmpty) return 'Not enough transaction data yet.';

      final res = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'llama-3.3-70b-versatile',
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'You are a kind but blunt personal finance coach. The user sends you '
                      'a JSON list of their last 30 days of spending (note, amount, currency, type). '
                      'Give honest, specific advice: where the money is going, what to cut, what '
                      'to change. Be direct but not preachy. Keep it under 200 words. No emojis.',
                },
                {
                  'role': 'user',
                  'content':
                      'Here is my spending for the last 30 days (JSON): ${jsonEncode(data)}. '
                      'Tell me honestly where my money is going and what I should change.',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final message = (choices.first as Map)['message'] as Map?;
      return message?['content'] as String?;
    } catch (_) {
      return null;
    }
  }
}

/// Settings entry for the optional AI advisor.
Future<void> showAiAdvisorDialog(BuildContext context) async {
  final savedKey = await AiAdvisor.getKey();
  if (!context.mounted) return;
  final controller = TextEditingController(text: savedKey);
  String? response;
  String? error;
  bool busy = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> runAdvice() async {
          setState(() {
            busy = true;
            error = null;
            response = null;
          });
          final result = await AiAdvisor.ask(key: controller.text.trim());
          if (!dialogContext.mounted) return;
          setState(() {
            busy = false;
            if (result == null) {
              error = "Couldn't reach Groq — check your API key and connection.";
            } else {
              response = result;
            }
          });
        }

        return AlertDialog(
          title: const Text('AI advisor'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Optional and off by default. If you paste your own Groq API key, '
                  'only your notes, amounts and transaction types are sent to Groq — '
                  'never your SMS. You only send data when you tap "Get advice".',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Groq API key',
                    hintText: 'gsk_...',
                  ),
                ),
                const SizedBox(height: 12),
                if (busy)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  if (error != null)
                    Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  if (response != null) ...[
                    const SizedBox(height: 4),
                    SelectableText(response!),
                  ],
                  const SizedBox(height: 12),
                  if (controller.text.trim().isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: runAdvice,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Get advice'),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                await AiAdvisor.clearKey();
                controller.clear();
                setState(() {});
              },
              child: const Text('Clear key'),
            ),
            FilledButton(
              onPressed: () async {
                if (controller.text.trim().isEmpty) {
                  await AiAdvisor.clearKey();
                } else {
                  await AiAdvisor.saveKey(controller.text.trim());
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}
