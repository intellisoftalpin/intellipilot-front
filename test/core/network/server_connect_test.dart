import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/network/cookie_setup.dart';
import 'package:intellipilot/core/network/server_connection_service.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/network/tls/cert_trust.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';

/// Canned responses for the `/api/v1/auth/config` validation probe.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
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

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

/// A valid IntelliPilot `/auth/config` payload.
const _validConfig = {
  'open_registration': false,
  'password_reset_enabled': true,
};

class _Fixture {
  _Fixture(Future<ResponseBody> Function(RequestOptions) respond)
    : boards = InMemoryKeyValueStorage(),
      ui = InMemoryKeyValueStorage(),
      drafts = InMemoryKeyValueStorage(),
      settings = InMemoryKeyValueStorage() {
    endpoint = ServerEndpoint(storage: settings, compileTimeBase: '');
    client = ApiClient(
      config: const ApiConfig(baseUrl: 'http://unset'),
      uuidGen: const DefaultUuidGen(),
      tokenProvider: () => null,
      dio: Dio(),
    );
    service = ServerConnectionService(
      endpoint: endpoint,
      apiClient: client,
      certPins: CertPinStore(settings),
      cookies: CookieSetup.inMemory(),
      storage: (box) => switch (box) {
        HiveBoxes.boards => boards,
        HiveBoxes.ui => ui,
        HiveBoxes.drafts => drafts,
        _ => settings,
      },
      probeDioFactory: (base) =>
          Dio(BaseOptions(baseUrl: base, validateStatus: (s) => s != null))
            ..httpClientAdapter = _Adapter(respond),
    );
  }

  final KeyValueStorage boards;
  final KeyValueStorage ui;
  final KeyValueStorage drafts;
  final KeyValueStorage settings;
  late final ServerEndpoint endpoint;
  late final ApiClient client;
  late final ServerConnectionService service;
}

void main() {
  group('connect outcomes', () {
    test('a valid IntelliPilot is adopted', () async {
      final f = _Fixture((_) async => _json(_validConfig));
      final res = await f.service.connect('pilot.example.com');

      expect(res.outcome, ConnectOutcome.ok);
      expect(res.url, 'https://pilot.example.com');
      expect(f.endpoint.effective, 'https://pilot.example.com');
      // Dio must follow, or API calls would keep going to the old host.
      expect(f.client.dio.options.baseUrl, 'https://pilot.example.com');
    });

    test('a malformed address never reaches the network', () async {
      var called = false;
      final f = _Fixture((_) async {
        called = true;
        return _json(_validConfig);
      });
      final res = await f.service.connect('not a url/with path');

      expect(res.outcome, ConnectOutcome.invalidUrl);
      expect(called, isFalse);
      expect(f.endpoint.isConfigured, isFalse);
    });

    test('something that is not IntelliPilot is rejected', () async {
      // A web server answering 200 with unrelated JSON must not be accepted
      // just because it responded.
      final f = _Fixture((_) async => _json({'hello': 'world'}));
      final res = await f.service.connect('example.com');

      expect(res.outcome, ConnectOutcome.notIntelliPilot);
      expect(f.endpoint.isConfigured, isFalse);
    });

    test('a non-200 is rejected', () async {
      final f = _Fixture((_) async => _json({'x': 1}, status: 404));
      final res = await f.service.connect('example.com');
      expect(res.outcome, ConnectOutcome.notIntelliPilot);
    });

    test('an unreachable host is reported as such', () async {
      final f = _Fixture(
        (o) async => throw DioException.connectionError(
          requestOptions: o,
          reason: 'no route',
        ),
      );
      final res = await f.service.connect('nowhere.example.com');

      expect(res.outcome, ConnectOutcome.unreachable);
      expect(f.endpoint.isConfigured, isFalse);
    });

    test('nothing is persisted unless validation passed', () async {
      final f = _Fixture((_) async => _json({'nope': true}));
      await f.service.connect('example.com');
      // A typo must not leave the app pointing somewhere that only fails
      // later, at the login screen, with a worse error.
      expect(f.endpoint.stored, isNull);
    });
  });

  group('switching servers', () {
    test(
      'changing server wipes per-server caches but keeps settings',
      () async {
        final f = _Fixture((_) async => _json(_validConfig));
        await f.service.connect('first.example.com');

        await f.boards.set<String>('snapshot', 'cards-from-first');
        await f.ui.set<String>('rail', 'expanded');
        await f.drafts.set<String>('draft', 'text');
        await f.settings.set<String>('theme', 'dark');

        await f.service.connect('second.example.com');

        // Board snapshots, filters and layouts are keyed by (userId, projectId)
        // with no notion of which server — they cannot outlive the connection.
        expect(f.boards.get<String>('snapshot'), isNull);
        expect(f.ui.get<String>('rail'), isNull);
        expect(f.drafts.get<String>('draft'), isNull);
        // Theme/locale are the user's global preferences, not server data.
        expect(f.settings.get<String>('theme'), 'dark');
        expect(f.endpoint.effective, 'https://second.example.com');
      },
    );

    test('reconnecting to the SAME server keeps caches', () async {
      final f = _Fixture((_) async => _json(_validConfig));
      await f.service.connect('same.example.com');
      await f.boards.set<String>('snapshot', 'keep-me');

      await f.service.connect('same.example.com');

      expect(f.boards.get<String>('snapshot'), 'keep-me');
    });
  });
}
