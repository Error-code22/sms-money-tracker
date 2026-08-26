import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sms_money_tracker/dialogs.dart';
import 'package:sms_money_tracker/main.dart';
import 'package:sms_money_tracker/models/transaction.dart';
import 'package:sms_money_tracker/screens/breakdown_screen.dart';
import 'package:sms_money_tracker/screens/transaction_detail.dart';
import 'package:sms_money_tracker/screens/transaction_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'has_seen_onboarding': true});
  });

  testWidgets('App builds and shows title', (WidgetTester tester) async {
    await tester.pumpWidget(const MoneyTrackerApp());
    expect(find.text('Money Tracker'), findsOneWidget);
    expect(find.text('Setup needed'), findsOneWidget);
  });

  testWidgets('Onboarding dialog shows on first launch only', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MoneyTrackerApp());
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Where Ma Money?'), findsOneWidget);

    await tester.tap(find.text('Got it, let\'s go'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Where Ma Money?'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('has_seen_onboarding'), isTrue);
  });

  testWidgets('About dialog renders in dark mode with version and links', (WidgetTester tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Where Ma Money?',
      packageName: 'com.droner.sms_money_tracker',
      version: '1.0.0+2',
      buildNumber: '2',
      buildSignature: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAppAboutDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Where Ma Money?'), findsOneWidget);
    expect(find.textContaining('Version: 1.0.0+2'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
  });

  testWidgets('Support dialog renders in dark mode with WhatsApp and GitHub', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showSupportDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Support'), findsOneWidget);
    expect(find.textContaining('+254 703 300 084'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
  });

  testWidgets('Privacy dialog renders in dark mode', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showPrivacyDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.textContaining('Your data stays on your phone'), findsOneWidget);
  });

  testWidgets('Transaction detail dialog renders in dark mode', (WidgetTester tester) async {
    final tx = MoneyTransaction.fromJson({
      'id': 1,
      'sender': 'MPESA',
      'body': 'QGH7K3MNOP Confirmed. Ksh500.00 sent to JOHN DOE 0712345678 on 12/6/25 at 7:45 PM.',
      'amount': 500.0,
      'currency': 'KES',
      'type': 'debit',
      'counterparty': 'JOHN DOE',
      'ts': DateTime(2026, 6, 12, 19, 45).millisecondsSinceEpoch,
      'is_confident': 1,
      'category': '',
      'interest': null,
      'source': 'sms',
      'note': '',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showTransactionDetail(context, tx, onChanged: () async {}),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('JOHN DOE'), findsOneWidget);
    expect(find.text('-500 KES'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.textContaining('QGH7K3MNOP Confirmed'), findsOneWidget);
  });

  testWidgets('Add-transaction form renders in dark mode', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => TransactionFormDialog.show(context, defaultCurrency: 'KES'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add transaction'), findsOneWidget);
    expect(find.text('Money out'), findsOneWidget);
    expect(find.text('Money in'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
  });

  testWidgets('Breakdown screen renders in dark mode', (WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('sms_money_tracker/channel'),
      (call) async => '[]',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: const BreakdownScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Where it goes'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('3 months'), findsOneWidget);
    expect(find.text('All time'), findsOneWidget);
  });
}
