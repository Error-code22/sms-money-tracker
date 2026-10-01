import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'sms_service.dart';

enum CloudSyncStatus { ok, skipped, failed }

class CloudSyncResult {
  final CloudSyncStatus status;
  final int upserted;
  final String message;

  const CloudSyncResult(this.status, this.upserted, this.message);
}

/// Pushes transactions to the Pixel Spot logbook endpoint.
/// The app stays the source of truth; the server just displays them.
class CloudSync {
  static const _enabledKey = 'cloud_sync_enabled';
  static const _lastSyncKey = 'last_cloud_sync_ms';
  static const _throttle = Duration(minutes: 15);
  static const _batchSize = 500;
  static const _timeout = Duration(seconds: 15);

  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_enabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (_) {}
  }

  /// Uploads all transactions. [force] bypasses the 15-minute throttle.
  static Future<CloudSyncResult> sync({bool force = false}) async {
    if (!await isEnabled()) {
      return const CloudSyncResult(CloudSyncStatus.skipped, 0, 'Upload disabled');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!force) {
        final last = prefs.getInt(_lastSyncKey) ?? 0;
        final elapsed = DateTime.now().millisecondsSinceEpoch - last;
        if (elapsed < _throttle.inMilliseconds) {
          return const CloudSyncResult(
              CloudSyncStatus.skipped, 0, 'Synced recently');
        }
      }

      final rows = await SmsService.getAllTransactions();
      if (rows.isEmpty) {
        return const CloudSyncResult(CloudSyncStatus.ok, 0, 'No transactions');
      }

      final batch = rows.map(_toPayload).toList();
      final version = await _appVersion();
      var totalUpserted = 0;

      for (var i = 0; i < batch.length; i += _batchSize) {
        final chunk = batch.sublist(
            i, i + _batchSize > batch.length ? batch.length : i + _batchSize);
        final body = jsonEncode({
          'transactions': chunk,
          'synced_at': DateTime.now().toIso8601String(),
          'app_version': version,
        });
        final resp = await http
            .post(
              Uri.parse(AppConfig.syncEndpoint),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${AppConfig.syncSecret}',
              },
              body: body,
            )
            .timeout(_timeout);
        if (resp.statusCode != 200) {
          return CloudSyncResult(CloudSyncStatus.failed, 0,
              'Server returned ${resp.statusCode}');
        }
        try {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map && decoded['upserted'] is int) {
            totalUpserted += decoded['upserted'] as int;
          }
        } catch (_) {}
      }

      await prefs.setInt(
          _lastSyncKey, DateTime.now().millisecondsSinceEpoch);
      return CloudSyncResult(CloudSyncStatus.ok, totalUpserted,
          'Synced $totalUpserted transactions');
    } on TimeoutException {
      return const CloudSyncResult(
          CloudSyncStatus.failed, 0, 'Timed out — check your connection');
    } catch (e) {
      return CloudSyncResult(CloudSyncStatus.failed, 0, 'Failed: $e');
    }
  }

  /// Fire-and-forget auto sync: never throws, never blocks the UI.
  static Future<void> autoSync() async {
    try {
      await sync();
    } catch (_) {}
  }

  static Map<String, dynamic> _toPayload(Map<String, dynamic> row) {
    final note = (row['note'] as String?) ?? '';
    var description = note.isNotEmpty ? note : ((row['body'] as String?) ?? '');
    description = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (description.length > 500) description = description.substring(0, 500);
    final ts = (row['ts'] as num?)?.toInt() ?? 0;
    return {
      'id': 'sms_${row['sms_id'] ?? row['id']}',
      'date': DateTime.fromMillisecondsSinceEpoch(ts).toIso8601String(),
      'amount': (row['amount'] as num?)?.toDouble() ?? 0,
      'type': row['type'] ?? 'debit',
      'counterparty': row['counterparty'] ?? '',
      'description': description,
      'category': row['category'] ?? '',
      'currency': row['currency'] ?? '',
      'source': row['source'] ?? 'sms',
    };
  }

  static Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return 'unknown';
    }
  }
}
