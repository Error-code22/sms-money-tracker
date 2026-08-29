import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/sms_service.dart';

class MonthReportScreen extends StatefulWidget {
  const MonthReportScreen({super.key, this.year, this.month});

  final int? year;
  final int? month;

  @override
  State<MonthReportScreen> createState() => _MonthReportScreenState();
}

class _MonthReportScreenState extends State<MonthReportScreen> {
  late int _year;
  late int _month;
  Map<String, dynamic> _report = {};
  Map<String, dynamic> _prev = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = widget.year ?? now.year;
    _month = widget.month ?? now.month;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final report = await SmsService.getMonthReport(year: _year, month: _month);
      final prevYear = _month == 1 ? _year - 1 : _year;
      final prevMonth = _month == 1 ? 12 : _month - 1;
      final prev = await SmsService.getMonthReport(year: prevYear, month: prevMonth);
      if (mounted) {
        setState(() {
          _report = report;
          _prev = prev;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _report = {});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int delta) {
    var m = _month + delta;
    var y = _year;
    if (m < 1) {
      m = 12;
      y -= 1;
    } else if (m > 12) {
      m = 1;
      y += 1;
    }
    setState(() {
      _month = m;
      _year = y;
    });
    _load();
  }

  double _get(Map<String, dynamic> map, String key) =>
      (map[key] as num?)?.toDouble() ?? 0;

  String _fmt(double v) => NumberFormat('#,##0.00').format(v);

  @override
  Widget build(BuildContext context) {
    final title = DateFormat('MMMM yyyy').format(DateTime(_year, _month));
    final currency = (_report['currency'] as String?) ?? '';
    final spent = _get(_report, 'spent');
    final received = _get(_report, 'received');
    final prevSpent = _get(_prev, 'spent');
    final count = (_report['count'] as num?)?.toInt() ?? 0;
    final merchants = (_report['merchants'] as List?) ?? const [];
    final categories = (_report['categories'] as List?) ?? const [];

    String? deltaText;
    if (prevSpent > 0 && spent > 0) {
      final delta = (spent - prevSpent) / prevSpent * 100;
      deltaText = '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)}% vs last month';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Month report')),
      body: SafeArea(
        bottom: true,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => _shift(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _shift(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Spent: $currency ${_fmt(spent)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Color(0xFFE53935),
                                  ),
                                ),
                              ),
                              Text(
                                'Received: $currency ${_fmt(received)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF43A047),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$count transactions'
                            '${deltaText != null ? ' · $deltaText' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (merchants.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Top merchants', style: TextStyle(fontWeight: FontWeight.bold)),
                    for (final m in merchants.cast<Map>()) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(m['name'] as String? ?? ''),
                        subtitle: Text('${m['count']} transactions'),
                        trailing: Text(
                          '$currency ${_fmt((m['total'] as num?)?.toDouble() ?? 0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                  if (categories.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Top categories', style: TextStyle(fontWeight: FontWeight.bold)),
                    for (final c in categories.cast<Map>()) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(c['name'] as String? ?? ''),
                        subtitle: Text('${c['count']} transactions'),
                        trailing: Text(
                          '$currency ${_fmt((c['total'] as num?)?.toDouble() ?? 0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}
