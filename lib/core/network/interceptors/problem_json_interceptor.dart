import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/problem.dart';

/// Parses RFC 9457 Problem+JSON bodies on non-2xx responses and stashes the
/// resulting [Problem] in `DioException.error` so downstream layers can
/// produce typed [AppFailure]s without re-parsing.
class ProblemJsonInterceptor extends Interceptor {
  const ProblemJsonInterceptor();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response == null) {
      handler.next(err);
      return;
    }

    Problem problem;
    final data = response.data;
    if (data is Map<String, dynamic>) {
      problem = Problem.fromJson(data);
    } else if (data is String) {
      problem = Problem.fallback(status: response.statusCode ?? 0, body: data);
    } else {
      problem = Problem.fallback(status: response.statusCode ?? 0);
    }

    // Pull request-id from the response header if the body didn't surface it.
    final requestId =
        response.headers.value('x-request-id') ??
        response.headers.value('X-Request-Id');
    final enriched = problem.requestId == null && requestId != null
        ? Problem(
            type: problem.type,
            title: problem.title,
            status: problem.status,
            detail: problem.detail,
            instance: problem.instance,
            requestId: requestId,
            errors: problem.errors,
            retryAfter: problem.retryAfter,
          )
        : problem;

    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: response,
        type: err.type,
        error: enriched,
        stackTrace: err.stackTrace,
        message: err.message,
      ),
    );
  }
}
