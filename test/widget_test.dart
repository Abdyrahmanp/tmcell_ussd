// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmcell_ussd/main.dart';

void main() {
  testWidgets('TM Utility onboarding smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const TMUtilityApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Hoş geldiňiz!'), findsOneWidget);
    expect(find.textContaining('Dowam et'), findsOneWidget);
  });
}
