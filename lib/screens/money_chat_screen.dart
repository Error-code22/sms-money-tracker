import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction.dart';
import '../services/sms_service.dart';

/// A WhatsApp-style chat where a blunt AI friend comments on your spending.
/// Privacy: AI only sees sender, date, type, amount, note — never the full SMS.
class MoneyChatScreen extends StatefulWidget {
  const MoneyChatScreen({super.key});

  @override
  State<MoneyChatScreen> createState() => _MoneyChatScreenState();
}

class _MoneyChatScreenState extends State<MoneyChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loading = false;
  bool _initialized = false;
  List<MoneyTransaction> _recentTxs = [];

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    try {
      final maps = await SmsService.getTransactions();
      _recentTxs = maps.map((m) => MoneyTransaction.fromJson(m)).toList();
      _messages.add(ChatMessage(
        text: _greeting(),
        isUser: false,
        time: DateTime.now(),
      ));
    } catch (_) {
      _messages.add(ChatMessage(
        text: "I can't see your transactions right now. Tell me about your spending!",
        isUser: false,
        time: DateTime.now(),
      ));
    }
    setState(() => _initialized = true);
  }

  String _greeting() {
    if (_recentTxs.isEmpty) return "Hey! I can't see any transactions yet. Tell me about your spending!";
    final debits = _recentTxs.where((t) => t.type == 'debit').toList();
    final credits = _recentTxs.where((t) => t.type == 'credit').toList();
    final totalSpent = debits.fold<double>(0, (s, t) => s + t.amount);
    final totalReceived = credits.fold<double>(0, (s, t) => s + t.amount);

    if (totalSpent > totalReceived * 2) {
      return "Yo! I see you've spent Ksh ${totalSpent.round()} recently but only received Ksh ${totalReceived.round()}. Want me to roast you?";
    } else if (totalSpent > 0) {
      return "Hey! I see ${debits.length} transactions — Ksh ${totalSpent.round()} out, Ksh ${totalReceived.round()} in. What's on your mind?";
    }
    return "Hey! I can see your recent transactions. Ask me anything about your spending habits!";
  }

  String _buildContext() {
    final buf = StringBuffer();
    buf.writeln('You are a blunt, funny friend commenting on someone\'s M-Pesa spending.');
    buf.writeln('IMPORTANT: You ONLY see sanitized data — sender, date, type, amount, and user\'s note.');
    buf.writeln('You NEVER see the full SMS message. Never ask for more details.');
    buf.writeln('Be direct, use Kenyan slang (sheng), roast bad spending, celebrate good saving.');
    buf.writeln('Keep responses short (2-3 sentences max). Be specific with numbers.');
    buf.writeln('Never give financial advice. Just comment and roast.');
    buf.writeln('');
    buf.writeln('Recent transactions (sender, date, type, amount, note):');
    for (final t in _recentTxs.take(5)) {
      final note = t.note.isNotEmpty ? ' [${t.note}]' : '';
      buf.writeln('- ${t.sender} | ${DateFormat('d MMM').format(t.date)} | ${t.type} | Ksh ${t.amount.round()}$note');
    }
    return buf.toString();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, time: DateTime.now()));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final response = await _getAiResponse(text);
      setState(() {
        _messages.add(ChatMessage(text: response, isUser: false, time: DateTime.now()));
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: "My brain froze. Try again, sawa?",
          isUser: false,
          time: DateTime.now(),
        ));
      });
    }

    setState(() => _loading = false);
    _scrollToBottom();
  }

  Future<String> _getAiResponse(String userMessage) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('groq_api_key') ?? '';
    if (apiKey.isEmpty) throw Exception('No API key');

    final model = prefs.getString('ai_model') ?? 'llama-3.1-8b-instant';
    final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': _buildContext()},
          {'role': 'user', 'content': userMessage},
        ],
        'temperature': 0.8,
        'max_tokens': 150,
      }),
    );

    if (response.statusCode != 200) throw Exception('API error');
    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Money Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              final maps = await SmsService.getTransactions();
              setState(() => _recentTxs = maps.map((m) => MoneyTransaction.fromJson(m)).toList());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Privacy notice
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(Icons.shield, size: 14, color: Theme.of(context).hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'AI only sees sender, date, type, amount — never full SMS',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                  ),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: _initialized
                ? ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const _TypingIndicator();
                      }
                      return _MessageBubble(message: _messages[index]);
                    },
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          // Input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Roast my spending...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.send, color: Theme.of(context).colorScheme.primary),
                    onPressed: _loading ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;

  const ChatMessage({required this.text, required this.isUser, required this.time});
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(message.time),
              style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(context, 0),
            const SizedBox(width: 4),
            _buildDot(context, 1),
            const SizedBox(width: 4),
            _buildDot(context, 2),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(BuildContext context, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (_, _, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Theme.of(context).hintColor.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
