import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/data/profile_repository_impl.dart';

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

ResponseBody _ok(String body, {int status = 200}) => ResponseBody.fromString(
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

const _userJson =
    '{"id":"u1","email":"u@e.com","username":"user1","full_name":"User One","lang":"en","timezone":"UTC","is_active":true,"created_at":"2026-05-27T00:00:00Z"}';

void main() {
  test('getProfile parses the user payload', () async {
    final repo = ProfileRepositoryImpl(
      _client(_Adapter((_) async => _ok(_userJson))),
    );
    final res = await repo.getProfile();
    expect(res.valueOrNull?.email, 'u@e.com');
    expect(res.valueOrNull?.username, 'user1');
  });

  test(
    'updateProfile sends only present fields and returns the updated user',
    () async {
      final adapter = _Adapter(
        (_) async => _ok(
          _userJson.replaceAll('"User One"', '"Updated"'),
        ),
      );
      final repo = ProfileRepositoryImpl(_client(adapter));
      final res = await repo.updateProfile(
        const ProfileUpdateRequest(fullName: 'Updated'),
      );
      expect(res.valueOrNull?.fullName, 'Updated');
      expect(adapter.lastRequest?.method, 'PATCH');
      expect(adapter.lastRequest?.data, {'full_name': 'Updated'});
    },
  );

  test('updateProfile returns ValidationFailure on 422', () async {
    final adapter = _Adapter(
      (_) async => _ok('{"title":"validation"}', status: 422),
    );
    final repo = ProfileRepositoryImpl(_client(adapter));
    final res = await repo.updateProfile(
      const ProfileUpdateRequest(timezone: ''),
    );
    expect(res.failureOrNull, isA<ValidationFailure>());
  });

  test('deleteAccount parses status + grace_until', () async {
    final adapter = _Adapter(
      (_) async => _ok(
        '{"status":"scheduled_for_erasure","grace_until":"2026-06-26T00:00:00Z"}',
        status: 202,
      ),
    );
    final repo = ProfileRepositoryImpl(_client(adapter));
    final res = await repo.deleteAccount();
    expect(res.valueOrNull?.status, 'scheduled_for_erasure');
    expect(
      res.valueOrNull?.graceUntil.toIso8601String(),
      contains('2026-06-26'),
    );
  });

  test('exportData returns the JSON map', () async {
    final adapter = _Adapter(
      (_) async => _ok(
        '{"user":{"id":"u1"},"audit_events":[],"exported_at":"2026-05-27T00:00:00Z"}',
      ),
    );
    final repo = ProfileRepositoryImpl(_client(adapter));
    final res = await repo.exportData();
    expect(res.valueOrNull?['user'], isA<Map<String, dynamic>>());
    expect(res.valueOrNull?['audit_events'], isA<List<dynamic>>());
  });
}
