// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:tmcell_ussd/main.dart';

void main() {
  testWidgets('TM Utility dashboard smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TMUtilityApp());
    expect(find.text('TM Utility'), findsOneWidget);
    expect(find.text('Hoş geldiňiz!'), findsOneWidget);
  });
}
