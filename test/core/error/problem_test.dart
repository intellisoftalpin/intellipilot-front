import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/problem.dart';

void main() {
  group('Problem', () {
    test('parses a fully-populated RFC 9457 document', () {
      final p = Problem.fromJson(<String, dynamic>{
        'type': 'https://example.com/probs/validation',
        'title': 'Validation failed',
        'status': 422,
        'detail': 'See errors[]',
        'instance': '/api/v1/users',
        'request_id': 'req-abc',
        'errors': [
          {'field': 'email', 'code': 'email', 'message': 'invalid'},
          {'field': 'password', 'code': 'length'},
        ],
        'retry_after': 30,
      });

      expect(p.type, 'https://example.com/probs/validation');
      expect(p.status, 422);
      expect(p.detail, 'See errors[]');
      expect(p.requestId, 'req-abc');
      expect(p.errors, hasLength(2));
      expect(p.errors.first.field, 'email');
      expect(p.errors.first.code, 'email');
      expect(p.errors.last.message, isNull);
      expect(p.retryAfter, const Duration(seconds: 30));
    });

    test('fills in defaults when fields are missing', () {
      final p = Problem.fromJson(const <String, dynamic>{});
      expect(p.type, 'about:blank');
      expect(p.title, 'Error');
      expect(p.status, 0);
      expect(p.errors, isEmpty);
      expect(p.retryAfter, isNull);
    });

    test('fallback() captures status and raw body', () {
      final p = Problem.fallback(status: 500, body: 'oops');
      expect(p.status, 500);
      expect(p.title, 'oops');
    });

    test('parses retry_after when supplied as a numeric string', () {
      final p = Problem.fromJson(const <String, dynamic>{
        'status': 429,
        'retry_after': '15',
      });
      expect(p.retryAfter, const Duration(seconds: 15));
    });

    test('ignores malformed entries in errors[]', () {
      final p = Problem.fromJson(<String, dynamic>{
        'status': 422,
        'errors': ['nonsense', 42, null],
      });
      expect(p.errors, isEmpty);
    });
  });
}
