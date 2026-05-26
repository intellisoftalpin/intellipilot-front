import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/failure_mapper.dart';
import 'package:intellipilot/core/error/problem.dart';

DioException _exc({
  required int status,
  Problem? problem,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final options = RequestOptions(path: '/test');
  return DioException(
    requestOptions: options,
    type: type,
    response: Response<dynamic>(requestOptions: options, statusCode: status),
    error: problem,
  );
}

void main() {
  group('mapDioExceptionToFailure', () {
    test('connection errors become NetworkFailure', () {
      final options = RequestOptions(path: '/x');
      final e = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
      expect(mapDioExceptionToFailure(e), isA<NetworkFailure>());
    });

    test('401 → UnauthorizedFailure', () {
      expect(
        mapDioExceptionToFailure(_exc(status: 401)),
        isA<UnauthorizedFailure>(),
      );
    });

    test('403 → ForbiddenFailure', () {
      expect(
        mapDioExceptionToFailure(_exc(status: 403)),
        isA<ForbiddenFailure>(),
      );
    });

    test('404 → NotFoundFailure', () {
      expect(
        mapDioExceptionToFailure(_exc(status: 404)),
        isA<NotFoundFailure>(),
      );
    });

    test('409 → ConflictFailure', () {
      expect(
        mapDioExceptionToFailure(_exc(status: 409)),
        isA<ConflictFailure>(),
      );
    });

    test('412 → ConflictFailure (ETag mismatch)', () {
      expect(
        mapDioExceptionToFailure(_exc(status: 412)),
        isA<ConflictFailure>(),
      );
    });

    test('422 carries the Problem.errors into ValidationFailure', () {
      const problem = Problem(
        type: 'about:blank',
        title: 'Validation',
        status: 422,
        errors: [FieldError(field: 'email', code: 'email')],
      );
      final f = mapDioExceptionToFailure(_exc(status: 422, problem: problem));
      expect(f, isA<ValidationFailure>());
      expect((f as ValidationFailure).fieldErrors, hasLength(1));
    });

    test('429 carries retryAfter from Problem', () {
      const problem = Problem(
        type: 'about:blank',
        title: 't',
        status: 429,
        retryAfter: Duration(seconds: 12),
      );
      final f = mapDioExceptionToFailure(_exc(status: 429, problem: problem));
      expect(f, isA<RateLimitedFailure>());
      expect((f as RateLimitedFailure).retryAfter, const Duration(seconds: 12));
    });

    test('5xx → ServerFailure', () {
      expect(mapDioExceptionToFailure(_exc(status: 503)), isA<ServerFailure>());
    });

    test('unrecognised 4xx → UnknownFailure', () {
      expect(
        mapDioExceptionToFailure(_exc(status: 418)),
        isA<UnknownFailure>(),
      );
    });
  });
}
