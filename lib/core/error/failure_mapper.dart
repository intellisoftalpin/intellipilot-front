import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/problem.dart';

/// Map a [DioException] (raised by the HTTP layer) to an [AppFailure].
///
/// The [ProblemJsonInterceptor] is expected to put a parsed [Problem] into
/// `error.error` for non-2xx responses. If it isn't present, we still do
/// best-effort classification based on the HTTP status or connection error.
AppFailure mapDioExceptionToFailure(DioException error) {
  final cause = error;
  final response = error.response;
  final inner = error.error;
  final problem = inner is Problem ? inner : null;

  // Transport-level / connection errors — no HTTP status.
  if (response == null) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return NetworkFailure(cause: cause);
      case DioExceptionType.cancel:
        return NetworkFailure(cause: cause);
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
        return ServerFailure(cause: cause);
    }
  }

  final status = response.statusCode ?? 0;
  switch (status) {
    case 401:
      return UnauthorizedFailure(problem: problem, cause: cause);
    case 403:
      return ForbiddenFailure(problem: problem, cause: cause);
    case 404:
      return NotFoundFailure(problem: problem, cause: cause);
    case 409 || 412:
      return ConflictFailure(problem: problem, cause: cause);
    case 422:
      return ValidationFailure(
        fieldErrors: problem?.errors ?? const <FieldError>[],
        problem: problem,
        cause: cause,
      );
    case 429:
      return RateLimitedFailure(
        retryAfter: problem?.retryAfter,
        problem: problem,
        cause: cause,
      );
    default:
      if (status >= 500) {
        return ServerFailure(problem: problem, cause: cause);
      }
      if (status >= 400) {
        return UnknownFailure(problem: problem, cause: cause);
      }
      return UnknownFailure(problem: problem, cause: cause);
  }
}
