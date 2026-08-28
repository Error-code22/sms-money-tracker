import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_lock.dart';
import '../dialogs.dart';
import '../models/transaction.dart';
import '../services/sms_service.dart';
import '../widgets/monthly_chart.dart';
import 'breakdown_screen.dart';
import 'note_prompt.dart';
import 'transaction_detail.dart';
import 'transaction_form.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  PermissionStatus _smsStatus = PermissionStatus.denied;
  bool _batteryExempt = false;
  bool _syncing = false;
  String _filter = 'all';
  String _query = '';
  List<MoneyTransaction> _transactions = [];
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _monthlyTotals = [];
  int _reviewCount = 0;
  int _chartMonths = 6;
  bool _lockEnabled = false;
  bool _locked = false;
  bool _duress = false;
  int _lockGrace = 30;
  DateTime? _backgroundedAt;
  Timer? _timer;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    _maybeShowOnboarding().then((_) => _initLockState());
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_smsStatus.isGranted && !_locked) _sync();
    });
  }

  Future<void> _maybeShowOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(kOnboardingSeenKey) ?? false) return;
      if (!mounted) return;
      await showOnboardingDialog(context);
    } catch (_) {}
  }

  Future<void> _initLockState() async {
    try {
      final enabled = await AppLock.isEnabled();
      final grace = await AppLock.lockGraceSeconds();
      if (!mounted) return;
      setState(() {
        _lockEnabled = enabled;
        _lockGrace = grace;
        _locked = enabled;
      });
      if (enabled) _promptUnlock();
    } catch (_) {}
  }

  Future<void> _promptUnlock() async {
    if (!_locked) return;
    final result = await showLockScreen(context);
    if (!mounted) return;
    if (result == LockResult.unlocked) {
      setState(() {
        _locked = false;
        _duress = false;
      });
    } else if (result == LockResult.duress) {
      setState(() {
        _locked = false;
        _duress = true;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_lockEnabled) _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _init();
      if (_lockEnabled) {
        final now = DateTime.now();
        final elapsed = _backgroundedAt == null
            ? const Duration(days: 1)
            : now.difference(_backgroundedAt!);
        final grace = Duration(seconds: _lockGrace);
        if (_locked || elapsed > grace) {
          _locked = true;
          _promptUnlock();
        }
        _backgroundedAt = null;
      }
    }
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
    _askNotificationPermissionOnce();
    setState(() {
      _smsStatus = status;
      _batteryExempt = exempt;
    });
    if (status.isGranted) await _sync();
  }

  Future<void> _askNotificationPermissionOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('asked_notif_perm') == true) return;
      await prefs.setBool('asked_notif_perm', true);
      await Permission.notification.request();
    } catch (_) {}
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await SmsService.sync();
      await _load();
      await _maybePromptNotes();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// After a sync, nudge the user to note fresh transactions before they
  /// forget. Skips the initial 90-day backfill (first run) and stays silent
  /// while locked or in duress mode.
  Future<void> _maybePromptNotes() async {
    if (_locked || _duress) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('last_note_prompt_ts');
      if (last == null) {
        await prefs.setInt('last_note_prompt_ts', DateTime.now().millisecondsSinceEpoch);
        return;
      }
      final all = await SmsService.getTransactions();
      final fresh = all
          .where((t) => (t['ts'] as num) > last && (t['source'] as String? ?? 'sms') == 'sms')
          .map(MoneyTransaction.fromJson)
          .toList();
      if (fresh.isEmpty) return;
      await prefs.setInt('last_note_prompt_ts', DateTime.now().millisecondsSinceEpoch);
      if (!mounted) return;
      HapticFeedback.vibrate();
      await showNotesPrompt(context, fresh);
      await _load();
    } catch (_) {}
  }

  Future<void> _load() async {
    final txs = await SmsService.getTransactions(filter: _filter, query: _query);
    final summary = await SmsService.getSummary();
    final totals = await SmsService.getMonthlyTotals(months: _chartMonths);
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
    if (status.isGranted) {
      await _sync();
    } else if (status.isPermanentlyDenied && mounted) {
      await showRestrictedSettingsHelp(context);
    }
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
    switch (value) {
      case 'about':
        await showAppAboutDialog(context);
      case 'support':
        await showSupportDialog(context);
      case 'settings':
        await showSettingsDialog(
          context,
          onChanged: () async {
            try {
              final enabled = await AppLock.isEnabled();
              final grace = await AppLock.lockGraceSeconds();
              if (mounted) {
                setState(() {
                  _lockEnabled = enabled;
                  _lockGrace = grace;
                });
              }
            } catch (_) {}
            await _load();
          },
        );
      case 'export':
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
      case 'resync':
        if (_syncing) return;
        setState(() => _syncing = true);
        try {
          await SmsService.resetSyncState();
          await _load();
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Resync failed')),
          );
        } finally {
          if (mounted) setState(() => _syncing = false);
        }
    }
  }

  Future<void> _addManual() async {
    final currency = _summary['currency'] as String?;
    final saved = await TransactionFormDialog.show(
      context,
      defaultCurrency: currency != null && currency.isNotEmpty ? currency : 'KES',
    );
    if (saved == true) await _load();
  }

  /// Decoy dashboard shown after unlocking with the duress PIN. Shows no real
  /// data. Long-pressing the title re-locks the app (normal PIN exits).
  Widget _buildDecoy() {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () {
            setState(() {
              _duress = false;
              _locked = true;
            });
            _promptUnlock();
          },
          child: const Text('Where Ma Money?'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: Theme.of(context).hintColor,
              ),
              const SizedBox(height: 16),
              Text(
                'No transactions yet.\nPull down to sync.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_duress) return _buildDecoy();
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
          IconButton(
            tooltip: 'Where it goes',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BreakdownScreen()),
            ),
            icon: const Icon(Icons.bar_chart),
          ),
          PopupMenuButton<String>(
            onSelected: _onMenuSelected,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'about', child: Text('About')),
              const PopupMenuItem(value: 'support', child: Text('Support')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
              const PopupMenuItem(value: 'export', child: Text('Export CSV')),
              PopupMenuItem(
                value: 'resync',
                enabled: !_syncing,
                child: const Text('Force full resync'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add manual transaction',
        onPressed: _addManual,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        bottom: true,
        child: RefreshIndicator(
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
      ),
    );
  }

  Widget _buildReviewBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.fact_check_outlined, color: scheme.primary),
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
      color: Theme.of(context).colorScheme.tertiaryContainer,
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
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _requestSmsPermission,
                      icon: const Icon(Icons.sms),
                      label: const Text('Allow SMS access'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Why can\'t I grant SMS access?',
                    onPressed: () => showRestrictedSettingsHelp(context),
                    icon: const Icon(Icons.help_outline),
                  ),
                ],
              ),
            if (_smsStatus.isPermanentlyDenied) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Open app settings'),
              ),
              const SizedBox(height: 4),
              const Text(
                'If SMS is greyed out there, tap the ⋮ menu on the app-info screen and choose "Allow restricted settings".',
                style: TextStyle(fontSize: 12),
              ),
            ],
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
        Builder(builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final positive = net >= 0;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: positive
                  ? (isDark ? const Color(0xFF1B3B24) : const Color(0xFFE8F5E9))
                  : (isDark ? const Color(0xFF4A1E1E) : const Color(0xFFFFEBEE)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Net this month ($currency): ${positive ? '+' : ''}${_fmtAmount(net)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: positive
                    ? (isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32))
                    : (isDark ? const Color(0xFFE57373) : const Color(0xFFC62828)),
              ),
            ),
          );
        }),
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF3E2A14) : const Color(0xFFFFF3E0);
    final border = isDark ? const Color(0xFFB26A00) : const Color(0xFFFFB74D);
    final titleColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
    final bodyColor = isDark ? const Color(0xFFFFE0B2) : Colors.black87;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, size: 16, color: titleColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Other currencies excluded from totals above',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: titleColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(lines, style: TextStyle(fontSize: 12, color: bodyColor)),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Monthly ($currency)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 3, label: Text('3M')),
                    ButtonSegment(value: 6, label: Text('6M')),
                    ButtonSegment(value: 12, label: Text('12M')),
                  ],
                  selected: {_chartMonths},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (selection) async {
                    setState(() => _chartMonths = selection.first);
                    try {
                      final totals = await SmsService.getMonthlyTotals(months: _chartMonths);
                      if (mounted) setState(() => _monthlyTotals = totals);
                    } catch (_) {}
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const _LegendDot(color: Color(0xFFE53935), label: 'Out'),
                const SizedBox(width: 12),
                const _LegendDot(color: Color(0xFF43A047), label: 'In'),
                const SizedBox(width: 12),
                _LegendDot(
                  color: Theme.of(context).colorScheme.primary,
                  label: 'Net',
                ),
              ],
            ),
            const SizedBox(height: 12),
            MonthlyChart(
              totals: _monthlyTotals,
              netColor: Theme.of(context).colorScheme.primary,
            ),
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
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      );
    }

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
            reviewMode: _filter == 'review',
            onTap: () => showTransactionDetail(context, tx, onChanged: _load),
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
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
        ),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final MoneyTransaction tx;
  final bool reviewMode;
  final VoidCallback onTap;
  final VoidCallback onConfirm;
  final VoidCallback onNotMoney;

  const _TransactionTile({
    required this.tx,
    required this.reviewMode,
    required this.onTap,
    required this.onConfirm,
    required this.onNotMoney,
  });

  @override
  Widget build(BuildContext context) {
    final color = tx.isDebit ? const Color(0xFFE53935) : const Color(0xFF43A047);
    final time = DateFormat('d MMM, h:mm a').format(tx.date);
    final extra = tx.extraInfo;
    final typeLabel = tx.isDebit ? 'Money out' : 'Money in';
    final senderInfo = [
      if (tx.sender.isNotEmpty) tx.sender,
      if (tx.currency.isNotEmpty) tx.currency,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                  if (reviewMode)
                    Row(
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
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    tx.isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                    color: color,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tx.formatAmount(),
                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                senderInfo.isNotEmpty ? '$senderInfo · $time' : time,
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
              if (tx.note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Note: ${tx.note}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              if (extra.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  extra,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
