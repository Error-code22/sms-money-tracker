class MoneyTransaction {
  final int id;
  final String sender;
  final String body;
  final double amount;
  final String currency;
  final String type;
  final String counterparty;
  final DateTime date;

  MoneyTransaction.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int,
        sender = json['sender'] as String? ?? '',
        body = json['body'] as String? ?? '',
        amount = (json['amount'] as num).toDouble(),
        currency = json['currency'] as String? ?? '',
        type = json['type'] as String,
        counterparty = json['counterparty'] as String? ?? '',
        date = DateTime.fromMillisecondsSinceEpoch((json['ts'] as num).toInt());

  bool get isDebit => type == 'debit';

  String get title {
    if (counterparty.isNotEmpty) return counterparty;
    if (sender.isNotEmpty) return sender;
    return isDebit ? 'Money out' : 'Money in';
  }

  String get subtitle => body;

  String formatAmount() {
    final sign = isDebit ? '-' : '+';
    final value = amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2);
    return currency.isEmpty ? '$sign$value' : '$sign$value $currency';
  }
}
