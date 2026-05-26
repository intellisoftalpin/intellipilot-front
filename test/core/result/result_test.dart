import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/result/result.dart';

void main() {
  group('Result', () {
    test('Ok carries a value and reports isOk', () {
      const r = Ok<int, String>(42);
      expect(r.isOk, isTrue);
      expect(r.isErr, isFalse);
      expect(r.valueOrNull, 42);
      expect(r.failureOrNull, isNull);
    });

    test('Err carries a failure and reports isErr', () {
      const r = Err<int, String>('boom');
      expect(r.isErr, isTrue);
      expect(r.isOk, isFalse);
      expect(r.failureOrNull, 'boom');
      expect(r.valueOrNull, isNull);
    });

    test('when() dispatches to the right branch', () {
      const ok = Ok<int, String>(1);
      const err = Err<int, String>('x');

      final okMapped = ok.when(ok: (v) => v + 1, err: (f) => -1);
      final errMapped = err.when(ok: (v) => v + 1, err: (f) => -1);

      expect(okMapped, 2);
      expect(errMapped, -1);
    });

    test('equality compares the inner value', () {
      expect(const Ok<int, String>(1), const Ok<int, String>(1));
      expect(const Err<int, String>('a'), const Err<int, String>('a'));
      expect(const Ok<int, String>(1) == const Ok<int, String>(2), isFalse);
    });

    test('Unit is a single instance', () {
      expect(identical(Unit.instance, Unit.instance), isTrue);
    });
  });
}
