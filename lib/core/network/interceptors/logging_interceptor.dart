import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

/// Lightweight request/response logger. Scrubs sensitive headers and bodies.
class HttpLoggingInterceptor extends Interceptor {
  HttpLoggingInterceptor(this._logger);
  final Logger _logger;

  static const _sensitiveHeaders = {
    'authorization',
    'cookie',
    'set-cookie',
    'x-csrf-token',
  };

  static const _sensitiveBodyKeys = {
    'password',
    'new_password',
    'token',
    'refresh_token',
    'access_token',
    'mfa_token',
    'code',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.d(
      '→ ${options.method} ${options.uri}\n'
      '  headers: ${_scrubHeaders(options.headers)}\n'
      '  body: ${_scrubBody(options.data)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _logger.d('← ${response.statusCode} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.w(
      '✗ ${err.requestOptions.method} ${err.requestOptions.uri} → '
      '${err.response?.statusCode ?? err.type.name}',
    );
    handler.next(err);
  }

  Map<String, Object?> _scrubHeaders(Map<String, dynamic> headers) {
    return {
      for (final entry in headers.entries)
        entry.key: _sensitiveHeaders.contains(entry.key.toLowerCase())
            ? '<redacted>'
            : entry.value,
    };
  }

  Object? _scrubBody(Object? body) {
    if (body is Map<String, dynamic>) {
      return {
        for (final entry in body.entries)
          entry.key: _sensitiveBodyKeys.contains(entry.key.toLowerCase())
              ? '<redacted>'
              : entry.value,
      };
    }
    return body;
  }
}
