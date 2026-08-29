import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../budgets.dart';
import '../services/sms_service.dart';
import '../widgets/daily_chart.dart';
import '../widgets/monthly_chart.dart';
import 'month_report.dart';

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  int _months = 6;
  late final int _year = DateTime.now().year;
  late final int _month = DateTime.now().month;
  List<Map<String, dynamic>> _totals = [];
  double _budgetLimit = 0;
  String _budgetLabel = '';
  List<double> _dailySpent = [];
  List<double> _cumCurrent = [];
  List<double> _cumPrevious = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final totals = await SmsService.getMonthlyTotals(months: _months);

      double budgetLimit = 0;
      String budgetLabel = '';
      final budgets = await Budgets.load();
      for (final b in budgets) {
        if (b.target.startsWith('total:')) {
          budgetLimit = b.limit;
          budgetLabel = '${b.currency} ${_fmt0(b.limit)}';
          break;
        }
      }

      final daily = await SmsService.getDailyTotals(year: _year, month: _month);
      final prevYear = _month == 1 ? _year - 1 : _year;
      final prevMonth = _month == 1 ? 12 : _month - 1;
      final prevDaily = await SmsService.getDailyTotals(year: prevYear, month: prevMonth);

      final daysInMonth = DateTime(_year, _month + 1, 0).day;
      final dailySpent = List<double>.filled(daysInMonth, 0);
      for (final row in daily) {
        final day = (row['day'] as num?)?.toInt() ?? 0;
        if (day >= 1 && day <= daysInMonth) {
          dailySpent[day - 1] = (row['spent'] as num?)?.toDouble() ?? 0;
        }
      }
      final cumCurrent = _cumulative(dailySpent);

      final prevDaysInMonth = DateTime(prevYear, prevMonth + 1, 0).day;
      final prevSpent = List<double>.filled(prevDaysInMonth, 0);
      for (final row in prevDaily) {
        final day = (row['day'] as num?)?.toInt() ?? 0;
        if (day >= 1 && day <= prevDaysInMonth) {
          prevSpent[day - 1] = (row['spent'] as num?)?.toDouble() ?? 0;
        }
      }
      final cumPrevious = _cumulative(prevSpent);

      if (mounted) {
        setState(() {
          _totals = totals;
          _budgetLimit = budgetLimit;
          _budgetLabel = budgetLabel;
          _dailySpent = dailySpent;
          _cumCurrent = cumCurrent;
          _cumPrevious = cumPrevious;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _totals = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<double> _cumulative(List<double> values) {
    final out = <double>[];
    var acc = 0.0;
    for (final v in values) {
      acc += v;
      out.add(acc);
    }
    return out;
  }

  String _fmt0(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  String _fmt2(double v) => NumberFormat('#,##0.00').format(v);

  void _showMonthPopup(int index) {
    if (index < 0 || index >= _totals.length) return;
    final t = _totals[index];
    final key = t['month'] as String;
    final year = int.parse(key.substring(0, 4));
    final month = int.parse(key.substring(5));
    final spent = (t['spent'] as num).toDouble();
    final received = (t['received'] as num).toDouble();
    final net = received - spent;
    final name = DateFormat('MMMM yyyy').format(DateTime(year, month));

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            _popupRow('Spent', _fmt2(spent), const Color(0xFFE53935)),
            _popupRow('Received', _fmt2(received), const Color(0xFF43A047)),
            _popupRow(
              'Net',
              '${net >= 0 ? '+' : ''}${_fmt2(net)}',
              net >= 0 ? const Color(0xFF43A047) : const Color(0xFFE53935),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MonthReportScreen(year: year, month: month),
                    ),
                  );
                },
                child: const Text('View month report'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _popupRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
            ),
          ),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final monthName = DateFormat('MMMM yyyy').format(DateTime(_year, _month));

    return Scaffold(
      appBar: AppBar(title: const Text('Charts')),
      body: SafeArea(
        bottom: true,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Monthly',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              SegmentedButton<int>(
                                segments: const [
                                  ButtonSegment(value: 3, label: Text('3M')),
                                  ButtonSegment(value: 6, label: Text('6M')),
                                  ButtonSegment(value: 12, label: Text('12M')),
                                ],
                                selected: {_months},
                                showSelectedIcon: false,
                                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                                onSelectionChanged: (selection) {
                                  setState(() => _months = selection.first);
                                  _load();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const _Dot(color: Color(0xFFE53935), label: 'Out'),
                              const SizedBox(width: 12),
                              const _Dot(color: Color(0xFF43A047), label: 'In'),
                              const SizedBox(width: 12),
                              _Dot(color: primary, label: 'Net'),
                              const Spacer(),
                              Text(
                                'Tap a bar',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).hintColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          MonthlyChart(
                            totals: _totals,
                            netColor: primary,
                            budgetLimit: _budgetLimit > 0 ? _budgetLimit : null,
                            budgetLabel: _budgetLabel,
                            onMonthTap: _showMonthPopup,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$monthName · daily spending',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const _Dot(color: Color(0xFFE53935), label: 'Spent'),
                              const SizedBox(width: 12),
                              _Dot(color: primary, label: 'This month'),
                              const SizedBox(width: 12),
                              _Dot(color: Theme.of(context).hintColor, label: 'Last month'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DailyChart(
                            dailySpent: _dailySpent,
                            cumCurrent: _cumCurrent,
                            cumPrevious: _cumPrevious,
                            primaryColor: primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.label});

  final Color color;
  final String label;

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
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
      ],
    );
  }
}
