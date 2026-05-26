import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/interceptors/auth_interceptor.dart';
import 'package:intellipilot/core/network/interceptors/etag_interceptor.dart';
import 'package:intellipilot/core/network/interceptors/idempotency_interceptor.dart';
import 'package:intellipilot/core/network/interceptors/problem_json_interceptor.dart';
import 'package:intellipilot/core/network/interceptors/request_id_interceptor.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';

class _FixedUuid implements UuidGen {
  _FixedUuid(this.value);
  final String value;
  @override
  String v4() => value;
}

RequestOptions _opts({String method = 'GET', Map<String, dynamic>? extra}) {
  return RequestOptions(
    path: '/x',
    method: method,
    extra: extra ?? <String, dynamic>{},
  );
}

class _CaptureHandler extends RequestInterceptorHandler {
  RequestOptions? captured;
  @override
  void next(RequestOptions options) {
    captured = options;
  }
}

class _CaptureErrorHandler extends ErrorInterceptorHandler {
  DioException? captured;
  @override
  void next(DioException error) {
    captured = error;
  }
}

void main() {
  group('RequestIdInterceptor', () {
    test('adds X-Request-Id when missing', () {
      final i = RequestIdInterceptor(_FixedUuid('abc-123'));
      final opts = _opts();
      final h = _CaptureHandler();
      i.onRequest(opts, h);
      expect(h.captured!.headers[RequestIdInterceptor.header], 'abc-123');
    });

    test('preserves a pre-existing X-Request-Id', () {
      final i = RequestIdInterceptor(_FixedUuid('abc-123'));
      final opts = _opts()..headers['X-Request-Id'] = 'preset';
      final h = _CaptureHandler();
      i.onRequest(opts, h);
      expect(h.captured!.headers[RequestIdInterceptor.header], 'preset');
    });
  });

  group('AuthInterceptor', () {
    test('attaches bearer token when present', () {
      final i = AuthInterceptor(() => 'tok');
      final h = _CaptureHandler();
      i.onRequest(_opts(), h);
      expect(h.captured!.headers['Authorization'], 'Bearer tok');
    });

    test('skips header when token is null or empty', () {
      final i = AuthInterceptor(() => null);
      final h = _CaptureHandler();
      i.onRequest(_opts(), h);
      expect(h.captured!.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('IdempotencyInterceptor', () {
    test('adds key on POST', () {
      final i = IdempotencyInterceptor(_FixedUuid('key-1'));
      final h = _CaptureHandler();
      i.onRequest(_opts(method: 'POST'), h);
      expect(h.captured!.headers[IdempotencyInterceptor.header], 'key-1');
    });

    test('respects pre-supplied key from extras', () {
      final i = IdempotencyInterceptor(_FixedUuid('generated'));
      final h = _CaptureHandler();
      i.onRequest(
        _opts(
          method: 'PATCH',
          extra: <String, dynamic>{'idempotency_key': 'pre'},
        ),
        h,
      );
      expect(h.captured!.headers[IdempotencyInterceptor.header], 'pre');
    });

    test('skips when extra.idempotency_skip is true', () {
      final i = IdempotencyInterceptor(_FixedUuid('k'));
      final h = _CaptureHandler();
      i.onRequest(_opts(method: 'POST', extra: {'idempotency_skip': true}), h);
      expect(
        h.captured!.headers.containsKey(IdempotencyInterceptor.header),
        isFalse,
      );
    });

    test('does not add key on GET', () {
      final i = IdempotencyInterceptor(_FixedUuid('k'));
      final h = _CaptureHandler();
      i.onRequest(_opts(), h);
      expect(
        h.captured!.headers.containsKey(IdempotencyInterceptor.header),
        isFalse,
      );
    });
  });

  group('EtagInterceptor', () {
    test('adds If-Match on PATCH when etag is in extras', () {
      const i = EtagInterceptor();
      final h = _CaptureHandler();
      i.onRequest(_opts(method: 'PATCH', extra: {'etag': '"id:5"'}), h);
      expect(h.captured!.headers[EtagInterceptor.header], '"id:5"');
    });

    test('does not add If-Match on GET', () {
      const i = EtagInterceptor();
      final h = _CaptureHandler();
      i.onRequest(_opts(extra: {'etag': '"x"'}), h);
      expect(h.captured!.headers.containsKey(EtagInterceptor.header), isFalse);
    });
  });

  group('ProblemJsonInterceptor', () {
    DioException buildErr({
      required int status,
      Object? body,
      Map<String, List<String>>? headers,
    }) {
      final opts = RequestOptions(path: '/x');
      return DioException(
        requestOptions: opts,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: opts,
          statusCode: status,
          data: body,
          headers: Headers.fromMap(headers ?? <String, List<String>>{}),
        ),
      );
    }

    test('replaces error with a parsed Problem', () {
      const i = ProblemJsonInterceptor();
      final h = _CaptureErrorHandler();
      i.onError(
        buildErr(
          status: 404,
          body: {'type': 't', 'title': 'Not found', 'status': 404},
        ),
        h,
      );
      expect(h.captured!.error, isA<Object>());
      expect(h.captured!.error.toString(), contains('404'));
    });

    test('uses fallback Problem when body is not JSON', () {
      const i = ProblemJsonInterceptor();
      final h = _CaptureErrorHandler();
      i.onError(buildErr(status: 500, body: 'raw'), h);
      expect(h.captured!.error.toString(), contains('500'));
    });
  });
}
