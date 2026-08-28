import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_advisor.dart';

class AppLock {
  static const _enabledKey = 'lock_enabled';
  static const _saltKey = 'pin_salt';
  static const _hashKey = 'pin_hash';
  static const _duressSaltKey = 'duress_salt';
  static const _duressHashKey = 'duress_hash';

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
    final salt = _randomSalt();
    final hash = sha256.convert(utf8.encode('$salt:$pin')).toString();
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, hash);
  }

  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    return _matches(prefs.getString(_saltKey), prefs.getString(_hashKey), pin);
  }

  static Future<bool> hasDuressPin() async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_duressSaltKey);
    final hash = prefs.getString(_duressHashKey);
    return salt != null && salt.isNotEmpty && hash != null && hash.isNotEmpty;
  }

  static Future<void> setDuressPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _randomSalt();
    final hash = sha256.convert(utf8.encode('$salt:$pin')).toString();
    await prefs.setString(_duressSaltKey, salt);
    await prefs.setString(_duressHashKey, hash);
  }

  static Future<bool> verifyDuressPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    return _matches(prefs.getString(_duressSaltKey), prefs.getString(_duressHashKey), pin);
  }

  static String _randomSalt() {
    final rng = Random.secure();
    return List.generate(
      16,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static bool _matches(String? salt, String? hash, String pin) {
    if (salt == null || hash == null) return false;
    final computed = sha256.convert(utf8.encode('$salt:$pin')).toString();
    return computed == hash;
  }
}

enum LockResult { unlocked, duress }

/// Full-screen opaque lock screen. Nothing is visible behind it, it cannot
/// be dismissed without a correct PIN or successful biometric auth, and the
/// window itself is FLAG_SECURE so recents shows a blank card.
Future<LockResult?> showLockScreen(BuildContext context) async {
  bool canBiometric = false;
  try {
    final auth = LocalAuthentication();
    if (await auth.isDeviceSupported()) {
      final biometrics = await auth.getAvailableBiometrics();
      canBiometric = biometrics.isNotEmpty && await auth.canCheckBiometrics;
    }
  } catch (_) {}

  if (!context.mounted) return null;

  return Navigator.of(context).push<LockResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LockScreen(canBiometric: canBiometric),
    ),
  );
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.canBiometric});

  final bool canBiometric;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _biometricFailed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _tryPin() async {
    final pin = _controller.text;
    final isDuress = await AppLock.hasDuressPin() && await AppLock.verifyDuressPin(pin);
    final isMain = await AppLock.verifyPin(pin);
    if (!mounted) return;
    if (isDuress) {
      Navigator.pop(context, LockResult.duress);
    } else if (isMain) {
      Navigator.pop(context, LockResult.unlocked);
    } else {
      setState(() {
        _error = 'Wrong PIN';
        _controller.clear();
      });
    }
  }

  Future<void> _tryBiometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final auth = LocalAuthentication();
      final ok = await auth.authenticate(
        localizedReason: 'Unlock Where Ma Money?',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, LockResult.unlocked);
      } else {
        setState(() => _biometricFailed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _biometricFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 48, color: scheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Where Ma Money?',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text('Enter your PIN to unlock'),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      onChanged: (_) {
                        if (_error != null || _biometricFailed) {
                          setState(() {
                            _error = null;
                            _biometricFailed = false;
                          });
                        }
                      },
                      onSubmitted: (_) => _tryPin(),
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(color: scheme.error),
                      ),
                    if (_biometricFailed)
                      Text(
                        'Biometrics unavailable — use your PIN',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _tryPin,
                        child: const Text('Unlock'),
                      ),
                    ),
                    if (widget.canBiometric) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _tryBiometric,
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Biometrics'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Set/change PIN flow. Returns true if a PIN was stored.
/// With [duress] it sets the secondary PIN that opens the decoy dashboard.
Future<bool> showPinSetupDialog(BuildContext context, {bool duress = false}) async {
  final first = TextEditingController();
  final second = TextEditingController();
  String? error;

  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(duress ? 'Set duress PIN' : 'Set PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (duress)
                  Text(
                    'This PIN opens a decoy empty dashboard. Keep it different from your real PIN.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
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
                  if (duress) {
                    final hasMain = await AppLock.hasPin();
                    if (!hasMain) {
                      setState(() => error = 'Set your main PIN first');
                      return;
                    }
                    if (await AppLock.verifyPin(pin)) {
                      setState(() => error = 'Duress PIN must differ from your real PIN');
                      return;
                    }
                    try {
                      await AppLock.setDuressPin(pin);
                    } catch (_) {}
                  } else {
                    try {
                      await AppLock.setPin(pin);
                    } catch (_) {}
                  }
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

/// Settings entry: app lock toggle + set/change PIN + duress PIN + AI advisor.
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
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.visibility_off),
              title: const Text('Duress PIN'),
              subtitle: const Text('A second PIN that opens a decoy empty dashboard'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showPinSetupDialog(dialogContext, duress: true),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome),
              title: const Text('AI advisor'),
              subtitle: const Text('Optional — uses your own Groq API key'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showAiAdvisorDialog(dialogContext),
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
