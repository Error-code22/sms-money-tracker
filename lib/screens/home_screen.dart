import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/transaction.dart';
import '../services/sms_service.dart';
import '../widgets/monthly_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PermissionStatus _smsStatus = PermissionStatus.denied;
  bool _batteryExempt = false;
  bool _syncing = false;
  String _filter = 'all';
  String _query = '';
  List<MoneyTransaction> _transactions = [];
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _monthlyTotals = [];
  int _reviewCount = 0;
  Timer? _timer;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_smsStatus.isGranted) _sync();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    PermissionStatus status = PermissionStatus.denied;
    bool exempt = false;
    try {
      status = await Permission.sms.status;
    } catch (_) {}
    try {
      exempt = await SmsService.isBatteryExempt();
    } catch (_) {}
    setState(() {
      _smsStatus = status;
      _batteryExempt = exempt;
    });
    if (status.isGranted) await _sync();
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await SmsService.sync();
      await _load();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _load() async {
    final txs = await SmsService.getTransactions(filter: _filter, query: _query);
    final summary = await SmsService.getSummary();
    final totals = await SmsService.getMonthlyTotals(months: 6);
    final review = await SmsService.getTransactions(filter: 'review');
    if (!mounted) return;
    setState(() {
      _transactions = txs.map(MoneyTransaction.fromJson).toList();
      _summary = summary;
      _monthlyTotals = totals;
      _reviewCount = review.length;
    });
  }

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();
    setState(() => _smsStatus = status);
    if (status.isGranted) await _sync();
  }

  Future<void> _requestBatteryExemption() async {
    await SmsService.requestBatteryExemption();
    final exempt = await SmsService.isBatteryExempt();
    if (mounted) setState(() => _batteryExempt = exempt);
  }

  double _get(String key) => (_summary[key] as num?)?.toDouble() ?? 0;

  String _fmtAmount(double value) {
    return NumberFormat('#,##0.00').format(value);
  }

  Future<void> _onMenuSelected(String value) async {
    if (value != 'export') return;
    try {
      final path = await SmsService.exportCsv();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(path.isEmpty ? 'Export failed' : 'CSV saved to $path'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final needSetup = !_smsStatus.isGranted || !_batteryExempt;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Money Tracker'),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: _onMenuSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export', child: Text('Export CSV')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (needSetup) _buildSetupCard(),
            if (_reviewCount > 0 && _filter != 'review') ...[
              const SizedBox(height: 8),
              _buildReviewBanner(),
            ],
            const SizedBox(height: 8),
            _buildSummary(),
            const SizedBox(height: 16),
            _buildChartCard(),
            const SizedBox(height: 16),
            _buildFilters(),
            const SizedBox(height: 8),
            _buildTransactionList(),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewBanner() {
    return Card(
      color: const Color(0xFFE3F2FD),
      child: ListTile(
        leading: const Icon(Icons.fact_check_outlined, color: Color(0xFF1565C0)),
        title: Text('$_reviewCount messages need review'),
        subtitle: const Text('Confirm they are money (or remove them) so the app learns your senders.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          setState(() => _filter = 'review');
          _load();
        },
      ),
    );
  }

  Widget _buildSetupCard() {
    final smsGranted = _smsStatus.isGranted;
    return Card(
      color: const Color(0xFFFFF8E1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Setup needed',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Grant SMS access and disable battery optimization so Tecno/HiOS does not kill the app. Your data never leaves this phone.',
            ),
            const SizedBox(height: 12),
            if (!smsGranted)
              FilledButton.icon(
                onPressed: _requestSmsPermission,
                icon: const Icon(Icons.sms),
                label: const Text('Allow SMS access'),
              ),
            if (!smsGranted && !_batteryExempt) const SizedBox(height: 8),
            if (!_batteryExempt)
              OutlinedButton.icon(
                onPressed: _requestBatteryExemption,
                icon: const Icon(Icons.battery_saver),
                label: const Text('Disable battery optimization'),
              ),
            if (smsGranted && _batteryExempt)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('All set', style: TextStyle(color: Colors.green)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final spent = _get('spentThisMonth');
    final received = _get('receivedThisMonth');
    final net = received - spent;
    final currency = (_summary['currency'] as String?) ?? '';
    final others = (_summary['others'] as List?) ?? const [];

    return Column(
      children: [
        Row(
          children: [
            _SummaryCard(
              label: 'Spent this month',
              value: _fmtAmount(spent),
              color: const Color(0xFFE53935),
              icon: Icons.arrow_upward,
            ),
            const SizedBox(width: 12),
            _SummaryCard(
              label: 'Received this month',
              value: _fmtAmount(received),
              color: const Color(0xFF43A047),
              icon: Icons.arrow_downward,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: net >= 0 ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Net this month ($currency): ${net >= 0 ? '+' : ''}${_fmtAmount(net)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: net >= 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
            ),
          ),
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildOtherCurrenciesCard(others),
        ],
      ],
    );
  }

  Widget _buildOtherCurrenciesCard(List others) {
    final lines = others.map((o) {
      final map = o as Map;
      final cur = map['currency'] ?? '';
      final count = map['count'] ?? 0;
      final debit = (map['debit'] as num?)?.toDouble() ?? 0;
      final credit = (map['credit'] as num?)?.toDouble() ?? 0;
      return '$cur: $count tx · out ${_fmtAmount(debit)} · in ${_fmtAmount(credit)}';
    }).join('\n');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber, size: 16, color: Color(0xFFE65100)),
              SizedBox(width: 6),
              Text(
                'Other currencies excluded from totals above',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFFE65100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(lines, style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    final currency = (_summary['currency'] as String?) ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last 6 months ($currency)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: const [
                _LegendDot(color: Color(0xFFE53935), label: 'Out'),
                SizedBox(width: 12),
                _LegendDot(color: Color(0xFF43A047), label: 'In'),
              ],
            ),
            const SizedBox(height: 12),
            MonthlyChart(totals: _monthlyTotals),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    Widget chip(String value, String label) {
      final selected = _filter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) {
            setState(() => _filter = value);
            _load();
          },
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            chip('all', 'All'),
            chip('debit', 'Money out'),
            chip('credit', 'Money in'),
            chip('review', _reviewCount > 0 ? 'Review ($_reviewCount)' : 'Review'),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search counterparty, sender or message...',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) {
            _query = value.trim();
            _load();
          },
        ),
      ],
    );
  }

  Widget _buildTransactionList() {
    if (_transactions.isEmpty) {
      final inReview = _filter == 'review';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            inReview
                ? 'Nothing to review. You are all caught up.'
                : 'No transactions found yet.\nPull down to sync, or wait for the next SMS.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    final formatter = DateFormat('MMM d, yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_transactions.length} transactions',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ..._transactions.map(
          (tx) => _TransactionTile(
            tx: tx,
            formatter: formatter,
            reviewMode: _filter == 'review',
            onConfirm: () => _reviewAction(tx, confirm: true),
            onNotMoney: () => _reviewAction(tx, confirm: false),
          ),
        ),
      ],
    );
  }

  Future<void> _reviewAction(MoneyTransaction tx, {required bool confirm}) async {
    final result = confirm
        ? await SmsService.confirmTransaction(tx.id)
        : await SmsService.markNotMoney(tx.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(confirm ? 'Confirmed ($result similar messages updated)' : 'Removed as not money'),
        duration: const Duration(seconds: 2),
      ),
    );
    await _load();
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final MoneyTransaction tx;
  final DateFormat formatter;
  final bool reviewMode;
  final VoidCallback onConfirm;
  final VoidCallback onNotMoney;

  const _TransactionTile({
    required this.tx,
    required this.formatter,
    required this.reviewMode,
    required this.onConfirm,
    required this.onNotMoney,
  });

  @override
  Widget build(BuildContext context) {
    final color = tx.isDebit ? const Color(0xFFE53935) : const Color(0xFF43A047);
    final time = DateFormat('h:mm a').format(tx.date);
    final extra = tx.extraInfo;
    final subtitleText = '${formatter.format(tx.date)} $time\n${tx.subtitle}'
        '${extra.isNotEmpty ? '\n$extra' : ''}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            tx.isDebit ? Icons.arrow_upward : Icons.arrow_downward,
            color: color,
            size: 18,
          ),
        ),
        title: Text(tx.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          subtitleText,
          maxLines: extra.isNotEmpty ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: reviewMode
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Confirm as money',
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check_circle, color: Color(0xFF43A047)),
                  ),
                  IconButton(
                    tooltip: 'Not money',
                    onPressed: onNotMoney,
                    icon: const Icon(Icons.cancel, color: Color(0xFFE53935)),
                  ),
                ],
              )
            : Text(
                tx.formatAmount(),
                style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
              ),
        isThreeLine: true,
      ),
    );
  }
}
