# Where Ma Money?

[![Download APK](https://img.shields.io/badge/Download-APK-brightgreen)](https://github.com/Error-code22/sms-money-tracker/releases/latest)

A local, offline Android app that reads transaction SMS (M-Pesa, mobile money, bank alerts) directly from your phone, parses them, and shows where your money goes. **No backend, no cloud — everything stays on your device.**

## Why this exists

Popular apps (like Truecaller) can't read SMS anymore because Google Play bans SMS access for apps where SMS isn't the core function, and phone makers like Tecno/HiOS aggressively kill background apps. This app is built to be **sideloaded**, so Play Store rules don't apply: you grant SMS permission directly and it just works.

## Features

- Reads SMS on-device via Android `ContentResolver` (no permissions leave the phone)
- **M-Pesa:** gated on sender `MPESA` + the `ABCD1234XY Confirmed.` header, then parsed with one dedicated template per transaction type (send, receive, paybill, till, withdraw, airtime, Fuliza, reversal) — amounts are anchored before `New M-PESA balance`/`Transaction cost,` so the wrong Ksh figure is never grabbed
- **Everything else (banks, Airtel):** generic keyword fallback with a currency whitelist, marked unconfirmed
- **Review queue:** unconfirmed transactions get one-tap *confirm* / *not money*; confirming teaches the app the sender + message shape, so identical messages are auto-confident from then on
- **Quick notes:** when new transactions arrive, a prompt (or a notification if the app is closed) nudges you to write what the money was for — before you forget
- **Categories & rules:** one-tap preset categories in the note prompt, plus keyword → category rules that auto-tag your notes
- **Where it goes:** top-10 breakdown by merchant or category (this month / 3 months / all time), each tappable down to individual transactions
- **Monthly chart:** money in/out bars with a net line, 3M/6M/12M ranges
- **Weekly digest:** a recap notification (~once a week) with this month's spend, received and top merchants
- **Manual entries:** add cash spending the SMS never sees; edit any transaction's parsed details (the raw SMS itself is never modified)
- **App lock:** PIN (salted hash) and/or biometrics, full-screen lock on open and after a background grace period (instant / 30 sec / 2 min), duress PIN that opens a decoy empty dashboard, and the window is `FLAG_SECURE` so recents and screenshots stay blank
- **CSV export & restore** — export to Downloads or import back to rebuild history
- **AI advisor (optional, off by default):** paste your own Groq API key; only your notes, amounts and transaction types are sent, and only when you tap "Get advice". A deprecated model can't break it — it picks an active model automatically
- **GitHub update check:** the About screen checks for newer releases (just a version number, nothing else)
- Android cloud backup (database rides along with your Google account backup)
- Battery-optimization exemption request so Tecno/HiOS can't kill it
- 100% offline, SQLite storage

## Build

```powershell
flutter pub get
flutter build apk --release
```

The APK lands in `build/app/outputs/flutter-apk/app-release.apk`. Copy it to your phone and install (you'll need to allow "install unknown apps" for your file manager/browser). Release builds are signed with a dedicated keystore (see `android/key.properties`, which is gitignored — back up that keystore, it cannot be regenerated).

Requires Android 7.0 (API 24) or newer.

## Troubleshooting: "App not installed"

- **You previously installed an older build signed with a different key.** Uninstall the existing "Where Ma Money?" app first, then install. This is the most common cause — early builds used a debug key.
- **The file transfer corrupted the APK.** Verify the file size matches the release asset (the `.apk` should be exactly 54,885,894 bytes for v1.2.0), then re-download directly from the release page.
- **"Install unknown apps" isn't granted** to the app doing the installing (Files/browser). Grant it under Settings → Apps → Special access → Install unknown apps.
- Still failing? From a PC with USB debugging: `adb install where-ma-money-1.2.0.apk` prints the exact reason.

## First run

1. Open the app
2. Tap **Allow SMS access** and grant the SMS permission (if the dialog is blocked, the "?" next to the button explains the restricted-settings path)
3. Tap **Disable battery optimization** (important on Tecno/HiOS phones)
4. The app backfills the last 90 days of SMS and keeps syncing
5. Check the **Review** tab — confirm or remove anything the parser got wrong, and the app learns your senders

## How it works

- **Native (Kotlin):** `SmsSync` queries `content://sms/inbox`; `SmsParser` gates M-Pesa messages on the `MPESA` sender + transaction-code header and parses them with per-type templates, falling back to a whitelist-keyword parser for banks; `SmsDb` stores everything in SQLite (plus `learned_shapes`/`rejected_shapes` tables that make review decisions stick); `SmsReceiver` catches `SMS_RECEIVED` broadcasts for real-time capture; `DigestWorker` posts the weekly recap.
- **Dart/Flutter:** UI only — talks to native via a single MethodChannel (`sms_money_tracker/channel`).

## Privacy

Your SMS never leaves your phone. The only network calls ever made are:

1. A GitHub release check when you open About (a version number, nothing personal).
2. The optional AI advisor, which you enable yourself with your own Groq key — it sends only your notes, amounts and transaction types, never your SMS, and only when you explicitly tap "Get advice".
