import 'dart:convert';

import 'package:flutter/services.dart';

class SmsService {
  static const MethodChannel _channel = MethodChannel('sms_money_tracker/channel');

  static Future<int> sync() async {
    return await _channel.invokeMethod<int>('sync') ?? 0;
  }

  static Future<List<Map<String, dynamic>>> getTransactions({
    String filter = 'all',
    String query = '',
  }) async {
    final raw = await _channel.invokeMethod<String>('getTransactions', {
      'filter': filter,
      'query': query,
    });
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> getSummary() async {
    final raw = await _channel.invokeMethod<String>('getSummary');
    if (raw == null || raw.isEmpty) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getMonthlyTotals({int months = 6}) async {
    final raw = await _channel.invokeMethod<String>('getMonthlyTotals', {'months': months});
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getTopCounterparties({int months = 1}) async {
    final raw = await _channel.invokeMethod<String>('getTopCounterparties', {'months': months});
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> insertManual({
    required String type,
    required double amount,
    required String currency,
    String? category,
    required String counterparty,
    required int ts,
    required String note,
  }) async {
    await _channel.invokeMethod('insertManual', {
      'type': type,
      'amount': amount,
      'currency': currency,
      'category': category,
      'counterparty': counterparty,
      'ts': ts,
      'note': note,
    });
  }

  static Future<void> updateTransaction({
    required int id,
    required String type,
    required double amount,
    required String currency,
    String? category,
    required String counterparty,
    required int ts,
    String? note,
  }) async {
    await _channel.invokeMethod('updateTransaction', {
      'id': id,
      'type': type,
      'amount': amount,
      'currency': currency,
      'category': category,
      'counterparty': counterparty,
      'ts': ts,
      'note': note,
    });
  }

  static Future<bool> isBatteryExempt() async {
    return await _channel.invokeMethod<bool>('isBatteryExempt') ?? false;
  }

  static Future<int> confirmTransaction(int id) async {
    return await _channel.invokeMethod<int>('confirmTransaction', {'id': id}) ?? 0;
  }

  static Future<int> markNotMoney(int id) async {
    return await _channel.invokeMethod<int>('markNotMoney', {'id': id}) ?? 0;
  }

  static Future<String> exportCsv() async {
    return await _channel.invokeMethod<String>('exportCsv') ?? '';
  }

  static Future<int> resetSyncState() async {
    return await _channel.invokeMethod<int>('resetSyncState') ?? 0;
  }

  static Future<void> requestBatteryExemption() async {
    await _channel.invokeMethod('requestBatteryExemption');
  }
}
