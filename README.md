# SMS Money Tracker

A local, offline Android app that reads transaction SMS (mobile money, bank alerts) directly from your phone, parses them, and shows where your money goes. **No backend, no cloud — everything stays on your device.**

## Why this exists

Popular apps (like Truecaller) can't read SMS anymore because Google Play bans SMS access for apps where SMS isn't the core function, and phone makers like Tecno/HiOS aggressively kill background apps. This app is built to be **sideloaded**, so Play Store rules don't apply: you grant SMS permission directly and it just works.

## Features

- Reads SMS on-device via Android `ContentResolver` (no permissions leave the phone)
- **M-Pesa:** gated on sender `MPESA` + the `ABCD1234XY Confirmed.` header, then parsed with one dedicated template per transaction type (send, receive, paybill, till, withdraw, airtime, Fuliza, reversal) — amounts are anchored before `New M-PESA balance`/`Transaction cost,` so the wrong Ksh figure is never grabbed
- **Everything else (banks, Airtel):** generic keyword fallback with a currency whitelist, marked unconfirmed
- **Review queue:** unconfirmed transactions get one-tap *confirm* / *not money*; confirming teaches the app the sender + message shape, so identical messages are auto-confident from then on
- Monthly summary (spent, received, net) + last-6-months chart
- Search and filter (all / money out / money in / review)
- Background receiver: new SMS are captured in real time even when the app is closed
- Battery-optimization exemption request so Tecno/HiOS can't kill it
- 100% offline, SQLite storage

## Build

```powershell
flutter pub get
flutter build apk --release
```

APK lands in `build/app/outputs/flutter-apk/app-release.apk`. Copy it to your phone and install (you'll need to allow "install unknown apps" for your file manager/browser).

## First run

1. Open the app
2. Tap **Allow SMS access** and grant the SMS permission
3. Tap **Disable battery optimization** (important on Tecno/HiOS phones)
4. The app backfills the last 90 days of SMS and keeps syncing

## How it works

- **Native (Kotlin):** `SmsSync` queries `content://sms/inbox`; `SmsParser` gates M-Pesa messages on the `MPESA` sender + transaction-code header and parses them with per-type templates, falling back to a whitelist-keyword parser for banks; `SmsDb` stores everything in SQLite (plus `learned_shapes`/`rejected_shapes` tables that make review decisions stick); `SmsReceiver` catches `SMS_RECEIVED` broadcasts for real-time capture.
- **Dart/Flutter:** UI only — talks to native via a single MethodChannel (`sms_money_tracker/channel`).

## Privacy

Your SMS never leaves your phone. There is no network code at all.
