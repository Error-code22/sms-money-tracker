# SMS Money Tracker

A local, offline Android app that reads transaction SMS (mobile money, bank alerts) directly from your phone, parses them, and shows where your money goes. **No backend, no cloud — everything stays on your device.**

## Why this exists

Popular apps (like Truecaller) can't read SMS anymore because Google Play bans SMS access for apps where SMS isn't the core function, and phone makers like Tecno/HiOS aggressively kill background apps. This app is built to be **sideloaded**, so Play Store rules don't apply: you grant SMS permission directly and it just works.

## Features

- Reads SMS on-device via Android `ContentResolver` (no permissions leave the phone)
- Parses mobile-money and bank SMS: M-Pesa style (`Ksh500.00 sent to JOHN DOE`), `NGN 5,000.00`, `UGX 50000`, etc.
- Detects money in / money out, amount, currency, counterparty
- Monthly summary (spent, received, net) + last-6-months chart
- Search and filter (all / money out / money in)
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

- **Native (Kotlin):** `SmsSync` queries `content://sms/inbox`; `SmsParser` extracts amounts/currency/direction with regex heuristics; `SmsDb` stores everything in SQLite; `SmsReceiver` catches `SMS_RECEIVED` broadcasts for real-time capture.
- **Dart/Flutter:** UI only — talks to native via a single MethodChannel (`sms_money_tracker/channel`).

## Privacy

Your SMS never leaves your phone. There is no network code at all.
