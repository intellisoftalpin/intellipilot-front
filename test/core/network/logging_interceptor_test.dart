import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/interceptors/logging_interceptor.dart';
import 'package:logger/logger.dart';

class _CapturingOutput extends LogOutput {
  final List<String> lines = [];
  @override
  void output(OutputEvent event) {
    lines.addAll(event.lines);
  }
}

/// Test stub: dio's default ErrorInterceptorHandler.next() completes the
/// internal completer with an error, which surfaces as an async crash in
/// tests. This subclass swallows the call.
class _SilentErrorHandler extends ErrorInterceptorHandler {
  @override
  void next(DioException err) {}
}

class _SilentRequestHandler extends RequestInterceptorHandler {
  @override
  void next(RequestOptions options) {}
}

class _SilentResponseHandler extends ResponseInterceptorHandler {
  @override
  void next(Response<dynamic> response) {}
}

void main() {
  late _CapturingOutput out;
  late Logger logger;
  late HttpLoggingInterceptor interceptor;

  setUp(() {
    out = _CapturingOutput();
    logger = Logger(
      output: out,
      printer: SimplePrinter(printTime: false, colors: false),
      level: Level.debug,
    );
    interceptor = HttpLoggingInterceptor(logger);
  });

  RequestOptions buildOpts({
    Map<String, dynamic>? headers,
    Object? body,
    String method = 'POST',
  }) {
    return RequestOptions(
      path: '/x',
      method: method,
      headers: headers ?? <String, dynamic>{},
      data: body,
    );
  }

  test('redacts Authorization header', () {
    interceptor.onRequest(
      buildOpts(headers: {'Authorization': 'Bearer secret'}),
      _SilentRequestHandler(),
    );
    final blob = out.lines.join('\n');
    expect(blob, contains('<redacted>'));
    expect(blob, isNot(contains('Bearer secret')));
  });

  test('redacts password field in body', () {
    interceptor.onRequest(
      buildOpts(body: {'email': 'a@b.c', 'password': 'hunter2'}),
      _SilentRequestHandler(),
    );
    final blob = out.lines.join('\n');
    expect(blob, contains('<redacted>'));
    expect(blob, isNot(contains('hunter2')));
  });

  test('logs response status', () {
    final opts = buildOpts(method: 'GET');
    interceptor.onResponse(
      Response<dynamic>(requestOptions: opts, statusCode: 204),
      _SilentResponseHandler(),
    );
    expect(out.lines.join('\n'), contains('204'));
  });

  test('logs errors with status code', () {
    final opts = buildOpts(method: 'GET');
    interceptor.onError(
      DioException(
        requestOptions: opts,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: opts, statusCode: 503),
      ),
      _SilentErrorHandler(),
    );
    expect(out.lines.join('\n'), contains('503'));
  });
}
