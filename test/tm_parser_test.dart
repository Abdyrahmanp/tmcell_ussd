import 'package:flutter_test/flutter_test.dart';
import 'package:tmcell_ussd/tm_parser.dart';

void main() {
  group('TMParser Unit Tests - Totals & Remainings', () {
    test('Parse Balance USSD text', () {
      const text = 'Sizin balansynyz: 45.70 TMT.';
      final balance = TMParser.parseBalance(text);
      expect(balance, equals(45.70));
    });

    test('Parse Minutes SMS text (Total & Remaining)', () {
      const text = 'Sowgat 500 min pakedyn gutarmagyna 465 min ya-da 29 galdy';
      final parsed = TMParser.parseMessage(text);
      expect(parsed.totalMinutes, equals(500));
      expect(parsed.minutes, equals(465));
    });

    test('Parse SMS count text (Total & Remaining)', () {
      const text = 'Sowgat 200 sms pakedyn gutarmagyna 187 sany ya-da 29 galdy';
      final parsed = TMParser.parseMessage(text);
      expect(parsed.totalSMS, equals(200));
      expect(parsed.sms, equals(187));
    });

    test('Parse Internet MB text (Total & Remaining)', () {
      const text = 'sow 1000 mb pakedyn gutarmagyna 150 MB ya-da 29 galdy';
      final parsed = TMParser.parseMessage(text);
      expect(parsed.totalInternetMB, equals(1000.0));
      expect(parsed.internetMB, equals(150.0));
    });

    test('Parse Internet GB text (Total & Remaining)', () {
      const text = 'Sowgat 5 GB pakedyn gutarmagyna 2.1 GB ya-da 29 galdy';
      final parsed = TMParser.parseMessage(text);
      expect(parsed.totalInternetGB, equals(5.0));
      expect(parsed.internetGB, closeTo(2.1, 0.01));
    });
  });
}
