import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/auth/data/auth_repository_impl.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';

/// Stub adapter that returns a canned [ResponseBody] per matched path+method.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) => respond(options);
}

ResponseBody _ok(String body, {int status = 200}) {
  return ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

ApiClient _client(HttpClientAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    uuidGen: const DefaultUuidGen(),
    tokenProvider: () => null,
    dio: dio,
  );
}

void main() {
  group('AuthRepositoryImpl', () {
    test('login() returns LoginTokens on token response', () async {
      final client = _client(
        _StubAdapter(
          (_) async => _ok(
            '{"access_token":"a","token_type":"Bearer","expires_in":900}',
          ),
        ),
      );
      final repo = AuthRepositoryImpl(client);
      final res = await repo.login(email: 'u@e.com', password: 'pw12345678');
      expect(res.isOk, true);
      final ok = res.valueOrNull!;
      expect(ok, isA<LoginTokens>());
      expect((ok as LoginTokens).tokens.accessToken, 'a');
    });

    test(
      'login() returns LoginMfaRequired when mfa_required is true',
      () async {
        final client = _client(
          _StubAdapter(
            (_) async => _ok(
              '{"mfa_required":true,"mfa_token":"mfa1","methods":["totp"]}',
            ),
          ),
        );
        final repo = AuthRepositoryImpl(client);
        final res = await repo.login(email: 'u@e.com', password: 'pw12345678');
        expect(res.valueOrNull, isA<LoginMfaRequired>());
        final mfa = res.valueOrNull! as LoginMfaRequired;
        expect(mfa.mfaToken, 'mfa1');
        expect(mfa.methods, ['totp']);
      },
    );

    test('login() returns UnauthorizedFailure on 401', () async {
      final client = _client(
        _StubAdapter((_) async => _ok('{"title":"Unauthorized"}', status: 401)),
      );
      final repo = AuthRepositoryImpl(client);
      final res = await repo.login(email: 'u@e.com', password: 'wrong');
      expect(res.isErr, true);
      expect(res.failureOrNull, isA<UnauthorizedFailure>());
    });

    test('register() returns Ok(Unit) on 201', () async {
      final client = _client(
        _StubAdapter(
          (_) async => _ok('{"id":"1","email":"u@e.com"}', status: 201),
        ),
      );
      final repo = AuthRepositoryImpl(client);
      final res = await repo.register(
        email: 'u@e.com',
        username: 'user1',
        password: 'pw12345678',
        fullName: '',
      );
      expect(res.isOk, true);
    });

    test('register() returns ConflictFailure on 409', () async {
      final client = _client(
        _StubAdapter(
          (_) async => _ok('{"title":"already_exists"}', status: 409),
        ),
      );
      final repo = AuthRepositoryImpl(client);
      final res = await repo.register(
        email: 'u@e.com',
        username: 'user1',
        password: 'pw12345678',
        fullName: '',
      );
      expect(res.failureOrNull, isA<ConflictFailure>());
    });

    test('requestPasswordReset() parses dev token from body', () async {
      final client = _client(
        _StubAdapter(
          (_) async => _ok('{"status":"ok","reset_token":"raw-tok"}'),
        ),
      );
      final repo = AuthRepositoryImpl(client);
      final res = await repo.requestPasswordReset('u@e.com');
      expect(res.valueOrNull?.resetToken, 'raw-tok');
    });

    test('confirmPasswordReset() returns Ok on 204', () async {
      final client = _client(
        _StubAdapter(
          (req) async => ResponseBody.fromString('', 204),
        ),
      );
      final repo = AuthRepositoryImpl(client);
      final res = await repo.confirmPasswordReset(
        token: 'tok',
        newPassword: 'pw12345678',
      );
      expect(res.isOk, true);
    });

    test(
      'confirmPasswordReset() maps 400 to UnknownFailure (default)',
      () async {
        final client = _client(
          _StubAdapter(
            (_) async => _ok('{"title":"invalid_token"}', status: 400),
          ),
        );
        final repo = AuthRepositoryImpl(client);
        final res = await repo.confirmPasswordReset(
          token: 'bad',
          newPassword: 'pw12345678',
        );
        expect(res.isErr, true);
      },
    );

    test('logout() treats 204 as success', () async {
      final client = _client(
        _StubAdapter(
          (_) async => ResponseBody.fromString('', 204),
        ),
      );
      final repo = AuthRepositoryImpl(client);
      final res = await repo.logout();
      expect(res.isOk, true);
    });

    test('refresh() returns Ok with rotated token', () async {
      final client = _client(
        _StubAdapter(
          (_) async => _ok(
            '{"access_token":"new","token_type":"Bearer","expires_in":600}',
          ),
        ),
      );
      final repo = AuthRepositoryImpl(client);
      final res = await repo.refresh();
      expect(res.valueOrNull?.accessToken, 'new');
    });
  });
}
