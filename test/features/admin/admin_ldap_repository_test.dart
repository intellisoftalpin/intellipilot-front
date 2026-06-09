import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/admin/data/admin_repository_impl.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';

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

const _ldapJson =
    '{"enabled":true,"server_url":"ldap://dc.example.com:389",'
    '"use_start_tls":false,"skip_tls_verify":false,"base_dn":"dc=example,dc=com",'
    '"default_domain":"example.com","bind_dn_format":"%s",'
    '"user_search_filter":"(sAMAccountName=%s)","superadmin_group":"Admins",'
    '"attr_email":"mail","attr_display_name":"displayName",'
    '"attr_username":"sAMAccountName","connection_timeout_secs":10,'
    '"updated_at":"2026-06-09T00:00:00Z","updated_by":null}';

UpdateLdapSettingsRequest _req() => const UpdateLdapSettingsRequest(
  enabled: true,
  serverUrl: 'ldap://dc.example.com:389',
  useStartTls: false,
  skipTlsVerify: false,
  baseDn: 'dc=example,dc=com',
  defaultDomain: 'example.com',
  bindDnFormat: '%s',
  userSearchFilter: '(sAMAccountName=%s)',
  superadminGroup: 'Admins',
  attrEmail: 'mail',
  attrDisplayName: 'displayName',
  attrUsername: 'sAMAccountName',
  connectionTimeoutSecs: 10,
);

void main() {
  group('AdminRepositoryImpl LDAP', () {
    test('getLdapSettings parses the config', () async {
      final repo = AdminRepositoryImpl(
        _client(_Adapter((_) async => _ok(_ldapJson))),
      );
      final res = await repo.getLdapSettings();
      final s = res.valueOrNull;
      expect(s?.enabled, true);
      expect(s?.serverUrl, 'ldap://dc.example.com:389');
      expect(s?.superadminGroup, 'Admins');
      expect(s?.connectionTimeoutSecs, 10);
    });

    test('updateLdapSettings PUTs the body and parses the result', () async {
      final adapter = _Adapter((_) async => _ok(_ldapJson));
      final repo = AdminRepositoryImpl(_client(adapter));
      final res = await repo.updateLdapSettings(_req());
      expect(res.isOk, true);
      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/api/v1/admin/ldap-settings');
      final sent = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(sent['enabled'], true);
      expect(sent['user_search_filter'], '(sAMAccountName=%s)');
    });

    test('testLdapSettings wraps {settings, username, password}', () async {
      final adapter = _Adapter(
        (_) async => _ok('{"ok":false,"message":"Connection error"}'),
      );
      final repo = AdminRepositoryImpl(_client(adapter));
      final res = await repo.testLdapSettings(
        settings: _req(),
        username: 'alex@example.com',
        password: 'secret',
      );
      expect(res.valueOrNull?.ok, false);
      expect(adapter.lastRequest?.path, '/api/v1/admin/ldap-settings/test');
      final sent = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(sent['username'], 'alex@example.com');
      expect((sent['settings'] as Map<String, dynamic>)['enabled'], true);
    });
  });
}
