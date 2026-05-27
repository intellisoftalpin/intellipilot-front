import 'dart:async';

import 'package:dio/dio.dart';

/// Outcome of a refresh attempt run by [RefreshInterceptor]'s host.
enum RefreshOutcome { refreshed, failed }

/// Refresh callback the interceptor invokes on 401. Implemented by the
/// [SessionBloc] glue layer — when it returns [RefreshOutcome.refreshed], the
/// interceptor retries the original request once with the (now-current) access
/// token; when it returns [RefreshOutcome.failed], the 401 propagates.
typedef RefreshHook = Future<RefreshOutcome> Function();

/// Intercepts 401 responses, calls [_refresh], and retries the original
/// request once. Concurrent in-flight requests share the same refresh attempt
/// rather than firing N parallel refresh calls (token-rotation contract on
/// the backend would otherwise revoke our family on the first retry).
///
/// Endpoints listed in [_skipPaths] never trigger a refresh — a 401 there is
/// a genuine credential failure, not an expired-token race.
class RefreshInterceptor extends Interceptor {
  // Underscore on the field is preferred over `this.dio` in the public ctor.
  // ignore: prefer_initializing_formals
  RefreshInterceptor(this._refresh, {required Dio dio}) : _dio = dio;

  final RefreshHook _refresh;
  final Dio _dio;

  Future<RefreshOutcome>? _inflight;

  static const _skipPaths = <String>[
    '/api/v1/auth/login',
    '/api/v1/auth/register',
    '/api/v1/auth/refresh',
    '/api/v1/auth/logout',
    '/api/v1/auth/password/reset/request',
    '/api/v1/auth/password/reset/confirm',
    '/api/v1/auth/2fa/verify',
  ];

  static const _retryFlag = '__refresh_retried';

  bool _shouldSkip(RequestOptions options) {
    if (options.extra[_retryFlag] == true) return true;
    final path = options.path;
    for (final skip in _skipPaths) {
      if (path == skip || path.endsWith(skip)) return true;
    }
    return false;
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    if (status != 401 || _shouldSkip(err.requestOptions)) {
      handler.next(err);
      return;
    }

    final outcome = await (_inflight ??= _runRefresh());

    if (outcome != RefreshOutcome.refreshed) {
      handler.next(err);
      return;
    }

    try {
      final original = err.requestOptions;
      final retried = await _dio.fetch<dynamic>(
        original.copyWith(extra: {...original.extra, _retryFlag: true}),
      );
      handler.resolve(retried);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<RefreshOutcome> _runRefresh() async {
    try {
      return await _refresh();
    } on Object {
      return RefreshOutcome.failed;
    } finally {
      _inflight = null;
    }
  }
}
