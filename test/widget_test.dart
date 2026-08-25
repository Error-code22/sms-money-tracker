import 'package:flutter_test/flutter_test.dart';

import 'package:sms_money_tracker/main.dart';

void main() {
  testWidgets('App builds and shows title', (WidgetTester tester) async {
    await tester.pumpWidget(const MoneyTrackerApp());
    expect(find.text('Money Tracker'), findsOneWidget);
    expect(find.text('Setup needed'), findsOneWidget);
  });
}
