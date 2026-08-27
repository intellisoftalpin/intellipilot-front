import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';

class _FixedUuid implements UuidGen {
  @override
  String v4() => 'fixed';
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.status, this.body});
  final int status;
  final Object? body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final encoded = body == null ? '' : jsonEncode(body);
    return ResponseBody.fromString(
      encoded,
      status,
      headers: const {
        'content-type': ['application/json'],
      },
    );
  }
}

ApiClient _client(_StubAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    config: const ApiConfig(baseUrl: 'http://test'),
    uuidGen: _FixedUuid(),
    tokenProvider: () => null,
    dio: dio,
  );
}

void main() {
  group('ApiClient', () {
    test('get() returns Ok on 200', () async {
      final client = _client(_StubAdapter(status: 200, body: {'ok': true}));
      final result = await client.get('/health/live');
      expect(result.isOk, isTrue);
      expect(result.valueOrNull?.statusCode, 200);
    });

    test('get() returns Err with mapped failure on 404', () async {
      final client = _client(
        _StubAdapter(
          status: 404,
          body: {'type': 't', 'title': 'nope', 'status': 404},
        ),
      );
      final result = await client.get('/missing');
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('post() returns Err on validation failure', () async {
      final client = _client(
        _StubAdapter(
          status: 422,
          body: {
            'type': 't',
            'title': 'Validation',
            'status': 422,
            'errors': [
              {'field': 'email', 'code': 'email'},
            ],
          },
        ),
      );
      final result = await client.post('/users', body: {'email': 'x'});
      expect(result.isErr, isTrue);
      final failure = result.failureOrNull;
      expect(failure, isA<ValidationFailure>());
      expect((failure! as ValidationFailure).fieldErrors, hasLength(1));
    });

    test('post() forwards idempotency key', () async {
      final client = _client(_StubAdapter(status: 201, body: {}));
      RequestOptions? captured;
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.next(options);
          },
        ),
      );
      await client.post('/x', idempotencyKey: 'idem-key');
      expect(captured?.headers['Idempotency-Key'], 'idem-key');
    });

    test('exposes the supplied config', () {
      final client = _client(_StubAdapter(status: 200));
      expect(client.config.baseUrl, 'http://test');
      expect(client.dio.options.baseUrl, 'http://test');
    });
  });

  group('ApiConfig', () {
    test('fromEnvironment falls back to localhost in tests', () {
      final cfg = ApiConfig.fromEnvironment();
      expect(cfg.baseUrl, 'http://localhost:8080');
      expect(cfg.withCredentials, isTrue);
    });
  });

  group('cookie-less clients', () {
    test('asks the server for the refresh token in the body', () {
      // Desktop and mobile hold several accounts, so they cannot keep one
      // refresh cookie per account in a single jar — each token goes to the OS
      // keychain instead. Without this header a native login receives only a
      // Set-Cookie it has no jar for, stores nothing, and multi-account
      // switching has nothing to switch between.
      //
      // A default header rather than three call sites: login, 2FA verify and
      // passkey authentication all mint sessions.
      final client = _client(_StubAdapter(status: 200));

      expect(
        client.dio.options.headers['X-IntelliPilot-Refresh-In-Body'],
        // Never on web, where the HttpOnly cookie is the entire point. The
        // flag is compile-time, so this asserts whichever platform runs it.
        kIsWeb ? isNull : '1',
      );
    });
  });
}
