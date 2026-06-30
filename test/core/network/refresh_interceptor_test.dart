import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/interceptors/refresh_interceptor.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responses);
  final List<Future<ResponseBody> Function(RequestOptions)> responses;
  int call = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) {
    final r = responses[call++];
    return r(options);
  }
}

ResponseBody _json(String body, {int status = 200}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  group('RefreshInterceptor', () {
    test(
      'on 401 calls refresh hook and retries original request once',
      () async {
        var hookCalls = 0;
        final adapter = _StubAdapter([
          (_) async => _json('{"title":"unauthorized"}', status: 401),
          (_) async => _json('{"ok":true}'),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        dio.interceptors.add(
          RefreshInterceptor(() async {
            hookCalls++;
            return RefreshOutcome.refreshed;
          }, dio: dio),
        );

        final res = await dio.get<dynamic>('/api/v1/me');
        expect(res.statusCode, 200);
        expect(adapter.call, 2, reason: 'one retry expected after refresh');
        expect(hookCalls, 1);
      },
    );

    test('on 401 with refresh failure surfaces the 401', () async {
      final adapter = _StubAdapter([
        (_) async => _json('{"title":"unauthorized"}', status: 401),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(
        RefreshInterceptor(
          () async => RefreshOutcome.failed,
          dio: dio,
        ),
      );

      expect(
        () => dio.get<dynamic>('/api/v1/me'),
        throwsA(
          predicate<DioException>((e) => e.response?.statusCode == 401),
        ),
      );
    });

    test(
      'skips refresh for /auth/login (a 401 there is a credential failure)',
      () async {
        var hookCalls = 0;
        final adapter = _StubAdapter([
          (_) async => _json('{"title":"unauthorized"}', status: 401),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        dio.interceptors.add(
          RefreshInterceptor(() async {
            hookCalls++;
            return RefreshOutcome.refreshed;
          }, dio: dio),
        );

        expect(
          () => dio.post<dynamic>('/api/v1/auth/login'),
          throwsA(isA<DioException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(hookCalls, 0);
      },
    );

    test('does not refresh on non-401 errors', () async {
      var hookCalls = 0;
      final adapter = _StubAdapter([
        (_) async => _json('{"title":"server"}', status: 500),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      dio.interceptors.add(
        RefreshInterceptor(() async {
          hookCalls++;
          return RefreshOutcome.refreshed;
        }, dio: dio),
      );

      expect(
        () => dio.get<dynamic>('/api/v1/me'),
        throwsA(isA<DioException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(hookCalls, 0);
    });
  });
}
