import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/features/timesheet/presentation/widgets/timesheet_format.dart';

void main() {
  group('parseDurationInput', () {
    test('decimal hours with dot or comma', () {
      expect(parseDurationInput('1'), 60);
      expect(parseDurationInput('1.5'), 90);
      expect(parseDurationInput('1,5'), 90);
      expect(parseDurationInput('3.58'), 215);
      expect(parseDurationInput('0.25'), 15);
    });

    test('hour/minute notation', () {
      expect(parseDurationInput('3h 35m'), 215);
      expect(parseDurationInput('3h35m'), 215);
      expect(parseDurationInput('2h'), 120);
      expect(parseDurationInput('45m'), 45);
      expect(parseDurationInput('2H 5M'), 125);
      expect(parseDurationInput(' 1h 05m '), 65);
    });

    test('clamps to a single day', () {
      expect(parseDurationInput('30h'), 1440);
      expect(parseDurationInput('48'), 1440);
    });

    test('rejects garbage and non-positive values', () {
      expect(parseDurationInput(''), isNull);
      expect(parseDurationInput('   '), isNull);
      expect(parseDurationInput('abc'), isNull);
      expect(parseDurationInput('0'), isNull);
      expect(parseDurationInput('-1'), isNull);
      expect(parseDurationInput('0h 0m'), isNull);
      expect(parseDurationInput('h m'), isNull);
      expect(parseDurationInput('1h 2x'), isNull);
    });
  });
}
