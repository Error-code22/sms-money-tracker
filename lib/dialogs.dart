import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/update_check.dart';

const String kRepoUrl = 'https://github.com/Error-code22/sms-money-tracker';
const String kWhatsAppUrl = 'https://wa.me/254703300084';
const String kOnboardingSeenKey = 'has_seen_onboarding';

Future<void> _openExternal(String url) async {
  final uri = Uri.parse(url);
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

TextStyle _linkStyle(BuildContext context) => TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );

// ---------------------------------------------------------------
// Restricted-settings explanation (reachable anytime, not only on
// permanentlyDenied)
// ---------------------------------------------------------------
Future<void> showRestrictedSettingsHelp(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('SMS access is blocked'),
      content: const Text(
        'Android may be suppressing the permission prompt, so it sometimes has to be enabled manually.\n\n'
        'Open app settings and turn on SMS. If the options are greyed out, tap the '
        '⋮ menu on the app-info screen and choose "Allow restricted settings" — '
        'that is required for sideloaded apps on modern Android.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            openAppSettings();
          },
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------
// Privacy
// ---------------------------------------------------------------
Future<void> showPrivacyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Privacy'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your data stays on your phone. Full stop.\n\n'
              'Where Ma Money? reads your SMS on your device, figures out which ones are M-Pesa/bank transactions, and stores everything in a local database — nothing gets uploaded, backed up to a server, or sent anywhere.\n\n'
              'The only thing that ever leaves your phone is a single check against GitHub to see if a newer version of the app exists — that\'s just a version number, no SMS content, no amounts, no names, nothing personal.\n\n'
              'Your database can ride along with your regular Android backup (Settings → Backup) — that\'s Google\'s standard phone backup, not something this app sends anywhere on its own.\n\n'
              'This app is open source. If you don\'t believe any of this, the code\'s right there.',
            ),
            TextButton(
              onPressed: () => _openExternal(kRepoUrl),
              child: const Text('View the source on GitHub'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------
// Terms
// ---------------------------------------------------------------
Future<void> showTermsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Terms'),
      content: SingleChildScrollView(
        child: Text(
          'This is a personal project, not a company. There\'s no formal legal agreement here — just the honest version:\n\n'
          'This app is provided as-is, no warranty. It might misparse a transaction, miss one, or have a bug — check the numbers against your actual bank/M-Pesa statement before relying on them for anything important.\n\n'
          'It\'s free and open source — use it, modify it, break it, fix it.\n\n'
          'Not affiliated with Safaricom, M-Pesa, Airtel Money, or any bank. It just reads the SMS they send you.\n\n'
          'Something wrong? Message on WhatsApp or open an issue on GitHub.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _openExternal(kWhatsAppUrl),
          child: const Text('WhatsApp'),
        ),
        TextButton(
          onPressed: () => _openExternal('$kRepoUrl/issues'),
          child: const Text('GitHub issues'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------
// About (with GitHub update check)
// ---------------------------------------------------------------
Future<void> showAppAboutDialog(BuildContext context) async {
  String version = '';
  try {
    final info = await PackageInfo.fromPlatform();
    version = info.version;
  } catch (_) {}
  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    builder: (context) => _AboutDialog(version: version),
  );
}

class _AboutDialog extends StatefulWidget {
  const _AboutDialog({required this.version});

  final String version;

  @override
  State<_AboutDialog> createState() => _AboutDialogState();
}

class _AboutDialogState extends State<_AboutDialog> {
  bool _checking = true;
  String? _updateTag;
  String? _updateUrl;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final release = await UpdateCheck.latestRelease();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (release != null) {
        final normalized = release.tag.replaceFirst(RegExp(r'^v'), '');
        final current = widget.version.split('+').first;
        if (normalized.isNotEmpty && normalized != current) {
          _updateTag = release.tag;
          _updateUrl = release.url;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Where Ma Money?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reads your M-Pesa/bank SMS on-device and shows you where your money actually goes. No backend, no cloud, no accounts.',
          ),
          const SizedBox(height: 12),
          if (_checking)
            Text('Version: ${widget.version} — checking GitHub for updates…')
          else if (_updateTag != null)
            RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(text: 'Version: ${widget.version} — '),
                  TextSpan(
                    text: 'Update available → $_updateTag',
                    style: _linkStyle(context),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _openExternal(_updateUrl ?? kRepoUrl),
                  ),
                ],
              ),
            )
          else
            Text('Version: ${widget.version}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => showPrivacyDialog(context),
          child: const Text('Privacy'),
        ),
        TextButton(
          onPressed: () => showTermsDialog(context),
          child: const Text('Terms'),
        ),
        TextButton(
          onPressed: () => _openExternal(kRepoUrl),
          child: const Text('GitHub'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Support
// ---------------------------------------------------------------
Future<void> showSupportDialog(BuildContext context) {
  final linkStyle = _linkStyle(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Support'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Something broken, or an idea for the app?'),
            const SizedBox(height: 8),
            const Text('WhatsApp: +254 703 300 084 → tap to open chat'),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  const TextSpan(text: 'GitHub: '),
                  TextSpan(
                    text: kRepoUrl,
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _openExternal(kRepoUrl),
                  ),
                  const TextSpan(text: ' → open an issue or check existing ones'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'One-person side project, so response times vary — but I read everything.',
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => _openExternal(kWhatsAppUrl),
          icon: const Icon(Icons.chat),
          label: const Text('WhatsApp'),
        ),
        OutlinedButton.icon(
          onPressed: () => _openExternal(kRepoUrl),
          icon: const Icon(Icons.code),
          label: const Text('GitHub'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------
// Onboarding (first launch only)
// ---------------------------------------------------------------
Future<void> showOnboardingDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Welcome to Where Ma Money?'),
      content: SingleChildScrollView(
        child: Text(
          'This app reads your M-Pesa and bank SMS right here on your phone — nothing is uploaded anywhere.\n\n'
          'First-time setup: grant SMS access and turn off battery optimization so Tecno/HiOS doesn\'t kill it in the background.\n\n'
          'New here? Some messages might get parsed wrong at first — check the Review tab and tap ✓ or ✗. The app learns your bank\'s format after that.\n\n'
          'That\'s it. Pull down to sync, and check back whenever you want to see where your money\'s been going.',
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () async {
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(kOnboardingSeenKey, true);
            } catch (_) {}
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Got it, let\'s go'),
        ),
      ],
    ),
  );
}
