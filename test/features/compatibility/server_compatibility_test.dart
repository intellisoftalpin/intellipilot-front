import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/build_info.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/compatibility/domain/compatibility_cubit.dart';
import 'package:intellipilot/features/compatibility/domain/server_compatibility.dart';

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

CompatibilityCubit _cubit(
  Future<ResponseBody> Function(RequestOptions) respond, {
  String clientVersion = '0.6.31',
}) => CompatibilityCubit(
  api: ApiClient(
    config: const ApiConfig(baseUrl: 'http://localhost'),
    uuidGen: const DefaultUuidGen(),
    tokenProvider: () => null,
    dio: Dio()..httpClientAdapter = _Adapter(respond),
  ),
  clientVersion: clientVersion,
);

void main() {
  group('judge', () {
    test('an older client major.minor is blocked', () {
      expect(
        judge(clientVersion: '0.6.31', serverVersion: '0.7.0'),
        CompatibilityStatus.clientTooOld,
      );
      expect(
        judge(clientVersion: '0.6.31', serverVersion: '1.0.0'),
        CompatibilityStatus.clientTooOld,
      );
    });

    test('patch differences never block', () {
      // An installed app cannot track a customer's server patch-for-patch, and
      // an app store review takes days — blocking on patches would break every
      // client on every server patch release.
      expect(
        judge(clientVersion: '0.6.1', serverVersion: '0.6.99'),
        CompatibilityStatus.ok,
      );
      expect(
        judge(clientVersion: '0.6.99', serverVersion: '0.6.1'),
        CompatibilityStatus.ok,
      );
    });

    test('a client ahead of the server is fine', () {
      expect(
        judge(clientVersion: '0.7.0', serverVersion: '0.6.31'),
        CompatibilityStatus.ok,
      );
    });

    test('equal versions are fine', () {
      expect(
        judge(clientVersion: '0.6.31', serverVersion: '0.6.31'),
        CompatibilityStatus.ok,
      );
    });

    test('unparseable or missing versions never block', () {
      // Refusing to run because a version string looked odd would be worse
      // than the mismatch being guarded against.
      for (final pair in [
        ('0.6.31', null),
        (null, '0.6.31'),
        ('0.6.31', 'nightly'),
        ('', '0.6.31'),
        ('0.6.31', ''),
      ]) {
        expect(
          judge(clientVersion: pair.$1, serverVersion: pair.$2),
          CompatibilityStatus.unknown,
          reason: 'client=${pair.$1} server=${pair.$2}',
        );
      }
    });

    test('tolerates a leading v and trailing metadata', () {
      expect(
        judge(clientVersion: 'v0.6.31', serverVersion: '0.6.31-rc1+abc'),
        CompatibilityStatus.ok,
      );
    });
  });

  group('VersionPair', () {
    test('orders by major first, then minor', () {
      expect(
        const VersionPair(0, 9).isOlderThan(const VersionPair(1, 0)),
        isTrue,
      );
      expect(
        const VersionPair(1, 0).isOlderThan(const VersionPair(0, 9)),
        isFalse,
      );
      expect(
        const VersionPair(0, 6).isOlderThan(const VersionPair(0, 7)),
        isTrue,
      );
    });
  });

  group('CompatibilityCubit', () {
    test('blocks when the server reports a newer minor', () async {
      final c = _cubit((_) async => _json({'version': '0.7.0'}));
      await c.check();
      expect(c.state.isBlocked, isTrue);
      expect(c.state.serverVersion, '0.7.0');
    });

    test('does not block on a matching server', () async {
      final c = _cubit((_) async => _json({'version': '0.6.31'}));
      await c.check();
      expect(c.state.isBlocked, isFalse);
    });

    test('a failed probe leaves the app usable', () async {
      // A network blip must never lock someone out of a working install.
      final c = _cubit(
        (o) async =>
            throw DioException.connectionError(requestOptions: o, reason: 'x'),
      );
      await c.check();
      expect(c.state.status, CompatibilityStatus.unknown);
      expect(c.state.isBlocked, isFalse);
    });

    test('a malformed body leaves the app usable', () async {
      final c = _cubit((_) async => _json({'nope': true}));
      await c.check();
      expect(c.state.isBlocked, isFalse);
    });

    test('reset clears a verdict, for when the server changes', () async {
      final c = _cubit((_) async => _json({'version': '0.7.0'}));
      await c.check();
      expect(c.state.isBlocked, isTrue);
      c.reset();
      expect(c.state.isBlocked, isFalse);
      expect(c.state.serverVersion, isNull);
    });
  });

  group('BuildInfo', () {
    test('version fallback matches pubspec.yaml', () {
      // The gate compares BuildInfo.version against the server. A stale
      // fallback here would make every build without --dart-define (any
      // `flutter run`, and every desktop/mobile build today) look years out of
      // date and block itself.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(
        r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(m, isNotNull, reason: 'version not found in pubspec.yaml');
      expect(BuildInfo.version, m!.group(1));
      expect(BuildInfo.build, m.group(2));
    });
  });
}
