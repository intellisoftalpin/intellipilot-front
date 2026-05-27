import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/mfa/data/mfa_repository_impl.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) {
    lastRequest = options;
    return respond(options);
  }
}

ResponseBody _ok(String body, {int status = 200}) =>
    ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

ApiClient _client(_Adapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    uuidGen: const DefaultUuidGen(),
    tokenProvider: () => null,
    dio: dio,
  );
}

void main() {
  test('startTotp parses TotpStartResponse', () async {
    final adapter = _Adapter(
      (_) async => _ok(
        '{"secret_base32":"S","provisioning_uri":"otpauth://x","qr_png_base64":"iVB"}',
      ),
    );
    final repo = MfaRepositoryImpl(_client(adapter));
    final res = await repo.startTotp();
    expect(res.valueOrNull?.secretBase32, 'S');
    expect(res.valueOrNull?.provisioningUri, 'otpauth://x');
  });

  test('confirmTotp returns recovery codes on 200', () async {
    final adapter = _Adapter(
      (_) async => _ok('{"recovery_codes":["a","b","c"]}'),
    );
    final repo = MfaRepositoryImpl(_client(adapter));
    final res = await repo.confirmTotp('123456');
    expect(res.valueOrNull?.codes, ['a', 'b', 'c']);
  });

  test('confirmTotp maps 422 to ValidationFailure', () async {
    final adapter = _Adapter(
      (_) async => _ok('{"title":"invalid_code"}', status: 422),
    );
    final repo = MfaRepositoryImpl(_client(adapter));
    final res = await repo.confirmTotp('000000');
    expect(res.failureOrNull, isA<ValidationFailure>());
  });

  test('disableTotp returns Ok on 204', () async {
    final adapter = _Adapter(
      (_) async => ResponseBody.fromString('', 204),
    );
    final repo = MfaRepositoryImpl(_client(adapter));
    final res = await repo.disableTotp();
    expect(res.isOk, true);
  });

  test('listPasskeys parses the array', () async {
    final adapter = _Adapter(
      (_) async => _ok(
        '{"passkeys":[{"id":"p1","nickname":"Mac","created_at":"2026-05-27T10:00:00Z","last_used_at":null}]}',
      ),
    );
    final repo = MfaRepositoryImpl(_client(adapter));
    final res = await repo.listPasskeys();
    expect(res.valueOrNull?.length, 1);
    expect(res.valueOrNull?.first.nickname, 'Mac');
    expect(res.valueOrNull?.first.lastUsedAt, isNull);
  });

  test('startPasskeyRegistration unwraps state_id + creation_options',
      () async {
    final adapter = _Adapter(
      (_) async => _ok(
        '{"state_id":"abc","creation_options":{"publicKey":{"rp":{"name":"x"}}}}',
      ),
    );
    final repo = MfaRepositoryImpl(_client(adapter));
    final res = await repo.startPasskeyRegistration();
    expect(res.valueOrNull?.stateId, 'abc');
    expect(res.valueOrNull?.options['publicKey'], isA<Map<String, dynamic>>());
  });

  test('regenerateRecoveryCodes returns 409 ConflictFailure when no 2FA',
      () async {
    final adapter = _Adapter(
      (_) async => _ok('{"title":"no_2fa"}', status: 409),
    );
    final repo = MfaRepositoryImpl(_client(adapter));
    final res = await repo.regenerateRecoveryCodes();
    expect(res.failureOrNull, isA<ConflictFailure>());
  });

  test('finishPasskeyAuthentication parses TokenResponse', () async {
    final adapter = _Adapter(
      (_) async => _ok(
        '{"access_token":"t","token_type":"Bearer","expires_in":600}',
      ),
    );
    final repo = MfaRepositoryImpl(_client(adapter));
    final res = await repo.finishPasskeyAuthentication(
      stateId: 's',
      credential: const {'id': 'cred'},
    );
    expect(res.valueOrNull?.accessToken, 't');
  });

  test('deletePasskey returns NotFoundFailure on 404', () async {
    final adapter = _Adapter(
      (_) async => _ok('{"title":"not_found"}', status: 404),
    );
    final repo = MfaRepositoryImpl(_client(adapter));
    final res = await repo.deletePasskey('missing');
    expect(res.failureOrNull, isA<NotFoundFailure>());
  });

  test('startPasskeyAuthentication unwraps request_options', () async {
    final adapter = _Adapter(
      (_) async => _ok(
        '{"state_id":"abc","request_options":{"publicKey":{"challenge":"y"}}}',
      ),
    );
    final repo = MfaRepositoryImpl(_client(adapter));
    final res = await repo.startPasskeyAuthentication('u@e.com');
    expect(res.valueOrNull?.stateId, 'abc');
  });
}
