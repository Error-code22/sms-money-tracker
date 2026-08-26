import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLock {
  static const _enabledKey = 'lock_enabled';
  static const _saltKey = 'pin_salt';
  static const _hashKey = 'pin_hash';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_saltKey);
    final hash = prefs.getString(_hashKey);
    return salt != null && salt.isNotEmpty && hash != null && hash.isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final rng = Random.secure();
    final salt = List.generate(
      16,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final hash = sha256.convert(utf8.encode('$salt:$pin')).toString();
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, hash);
  }

  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_saltKey);
    final hash = prefs.getString(_hashKey);
    if (salt == null || hash == null) return false;
    final computed = sha256.convert(utf8.encode('$salt:$pin')).toString();
    return computed == hash;
  }
}

/// Full-screen-blocking unlock prompt. Cannot be dismissed without a correct
/// PIN or successful biometric auth.
Future<bool> showLockDialog(BuildContext context) async {
  bool canBiometric = false;
  try {
    canBiometric = await LocalAuthentication().canCheckBiometrics;
  } catch (_) {}

  if (!context.mounted) return false;

  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _LockDialog(canBiometric: canBiometric),
      ) ??
      false;
}

class _LockDialog extends StatefulWidget {
  const _LockDialog({required this.canBiometric});

  final bool canBiometric;

  @override
  State<_LockDialog> createState() => _LockDialogState();
}

class _LockDialogState extends State<_LockDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _tryPin() async {
    final valid = await AppLock.verifyPin(_controller.text);
    if (!mounted) return;
    if (valid) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Wrong PIN');
    }
  }

  Future<void> _tryBiometric() async {
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Unlock Where Ma Money?',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (ok && mounted) Navigator.pop(context, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Locked'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your PIN to unlock'),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _tryPin(),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
        actions: [
          if (widget.canBiometric)
            FilledButton.icon(
              onPressed: _tryBiometric,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Biometrics'),
            ),
          FilledButton(
            onPressed: _tryPin,
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }
}

/// Set/change PIN flow. Returns true if a PIN was stored.
Future<bool> showPinSetupDialog(BuildContext context) async {
  final first = TextEditingController();
  final second = TextEditingController();
  String? error;

  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Set PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: first,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(labelText: 'New PIN (4-8 digits)'),
                ),
                TextField(
                  controller: second,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(labelText: 'Repeat PIN'),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final pin = first.text;
                  if (pin.length < 4) {
                    setState(() => error = 'PIN must be at least 4 digits');
                    return;
                  }
                  if (pin != second.text) {
                    setState(() => error = 'PINs do not match');
                    return;
                  }
                  try {
                    await AppLock.setPin(pin);
                  } catch (_) {}
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ) ??
      false;
}

/// Settings entry: app lock toggle + set/change PIN.
Future<void> showSettingsDialog(BuildContext context, {required VoidCallback onChanged}) async {
  bool enabled = await AppLock.isEnabled();
  bool hasPin = await AppLock.hasPin();
  if (!context.mounted) return;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('App lock'),
              subtitle: const Text('Require PIN or biometrics to open the app'),
              value: enabled,
              onChanged: (value) async {
                if (value && !hasPin) {
                  final ok = await showPinSetupDialog(dialogContext);
                  if (ok != true) return;
                  hasPin = true;
                }
                await AppLock.setEnabled(value);
                setState(() => enabled = value);
                onChanged();
              },
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await showPinSetupDialog(dialogContext);
                if (ok == true) setState(() => hasPin = true);
              },
              icon: const Icon(Icons.pin),
              label: Text(enabled ? 'Change PIN' : 'Set PIN'),
            ),
          ],
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
