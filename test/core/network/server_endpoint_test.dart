import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/network/server_connection_service.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/network/tls/cert_trust.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';

ServerEndpoint _endpoint({String pin = '', KeyValueStorage? storage}) =>
    ServerEndpoint(
      storage: storage ?? InMemoryKeyValueStorage(),
      compileTimeBase: pin,
    );

void main() {
  tearDown(() => ServerEndpoint.active = null);

  group('ServerConnectionService.normalise', () {
    test('adds https when no scheme is given', () {
      expect(
        ServerConnectionService.normalise('pilot.example.com'),
        'https://pilot.example.com',
      );
    });

    test('keeps an explicit scheme and port', () {
      expect(
        ServerConnectionService.normalise('http://192.168.1.10:8080'),
        'http://192.168.1.10:8080',
      );
    });

    test('trims whitespace and trailing slashes', () {
      expect(
        ServerConnectionService.normalise('  https://a.example.com//  '),
        'https://a.example.com',
      );
    });

    test('rejects an address carrying a path, query or fragment', () {
      // Silently dropping part of what someone typed is worse than refusing:
      // they would never learn the app ignored it.
      expect(ServerConnectionService.normalise('example.com/pilot'), isNull);
      expect(ServerConnectionService.normalise('example.com?a=1'), isNull);
      expect(ServerConnectionService.normalise('example.com#x'), isNull);
    });

    test('rejects nonsense and unsupported schemes', () {
      expect(ServerConnectionService.normalise(''), isNull);
      expect(ServerConnectionService.normalise('   '), isNull);
      expect(ServerConnectionService.normalise('ftp://example.com'), isNull);
      expect(ServerConnectionService.normalise('https://'), isNull);
    });

    test('flags cleartext addresses', () {
      expect(
        ServerConnectionService.isCleartext('http://example.com'),
        isTrue,
      );
      expect(
        ServerConnectionService.isCleartext('https://example.com'),
        isFalse,
      );
    });
  });

  group('ServerEndpoint.compileTimePin', () {
    test('is empty without a define, so the wizard runs in debug too', () {
      // These tests run in debug. A localhost shortcut here would mean the
      // wizard is unreachable via `flutter run` — the one path that ships
      // would be the one never exercised in development.
      expect(ServerEndpoint.compileTimePin(), '');
      expect(
        _endpoint(pin: ServerEndpoint.compileTimePin()).isConfigured,
        isFalse,
      );
    });
  });

  group('ServerEndpoint resolution', () {
    test('a build-time pin wins and skips the wizard', () {
      final e = _endpoint(pin: 'https://fixed.example.com');
      expect(e.isPinnedAtBuildTime, isTrue);
      expect(e.effective, 'https://fixed.example.com');
      expect(e.isConfigured, isTrue);
    });

    test('a build-time pin ignores anything stored', () async {
      final storage = InMemoryKeyValueStorage();
      final e = _endpoint(pin: 'https://fixed.example.com', storage: storage);
      await e.save('https://other.example.com');
      expect(e.effective, 'https://fixed.example.com');
    });

    test('with no pin, the stored server is used', () async {
      final e = _endpoint();
      expect(e.isConfigured, isFalse);
      await e.save('https://chosen.example.com');
      expect(e.effective, 'https://chosen.example.com');
      expect(e.isConfigured, isTrue);
    });

    test('save reports whether the server actually changed', () async {
      final e = _endpoint();
      // First ever save is not a "change" — there is no previous server whose
      // cached data would need wiping.
      expect(await e.save('https://a.example.com'), isFalse);
      expect(await e.save('https://a.example.com'), isFalse);
      expect(await e.save('https://b.example.com'), isTrue);
    });

    test('clear returns to unconfigured', () async {
      final e = _endpoint();
      await e.save('https://a.example.com');
      await e.clear();
      expect(e.isConfigured, isFalse);
    });
  });

  group('ApiConfig.baseUrl', () {
    test('falls back to its constructed value when no endpoint is active', () {
      // This is the web path: ServerEndpoint.active is never set there, so the
      // compile-time value (empty in release) is used and requests stay
      // relative to the page origin.
      const config = ApiConfig(baseUrl: '');
      expect(config.baseUrl, '');
      const dev = ApiConfig(baseUrl: 'http://localhost:8080');
      expect(dev.baseUrl, 'http://localhost:8080');
    });

    test('follows the active endpoint once one is configured', () async {
      final e = _endpoint();
      ServerEndpoint.active = e;
      const config = ApiConfig(baseUrl: 'http://localhost:8080');
      // Not configured yet → the constructed fallback still applies, so a dev
      // run with no server chosen behaves as before.
      expect(config.baseUrl, 'http://localhost:8080');

      await e.save('https://live.example.com');
      expect(config.baseUrl, 'https://live.example.com');
    });

    test('a switch is visible to every reader, not just Dio', () async {
      // ~12 widgets build image URLs from ApiConfig.baseUrl at paint time. If
      // this getter went stale, API calls would move to the new server while
      // avatars and attachments kept pointing at the old one.
      final e = _endpoint();
      ServerEndpoint.active = e;
      const config = ApiConfig(baseUrl: 'http://fallback');
      await e.save('https://one.example.com');
      expect(config.baseUrl, 'https://one.example.com');
      await e.save('https://two.example.com');
      expect(config.baseUrl, 'https://two.example.com');
    });
  });

  group('CertPinStore', () {
    test('accepts only the exact pinned fingerprint for that host', () async {
      final store = CertPinStore(InMemoryKeyValueStorage());
      const fp = 'aa:bb:cc';
      expect(store.isTrusted('a.example.com', 443, fp), isFalse);

      await store.pin('a.example.com', 443, fp);
      expect(store.isTrusted('a.example.com', 443, fp), isTrue);
      // Case-insensitive: fingerprint formatting varies between tools.
      expect(store.isTrusted('a.example.com', 443, 'AA:BB:CC'), isTrue);

      // A different certificate on the same host is NOT trusted — a cert
      // changing under you is exactly when you want to be asked again.
      expect(store.isTrusted('a.example.com', 443, 'dd:ee:ff'), isFalse);
      // Nor another host, nor another port.
      expect(store.isTrusted('b.example.com', 443, fp), isFalse);
      expect(store.isTrusted('a.example.com', 8443, fp), isFalse);
    });

    test('there is no blanket trust — unpinned hosts always fail', () {
      final store = CertPinStore(InMemoryKeyValueStorage());
      expect(store.hasPinFor('anything', 443), isFalse);
      expect(store.isTrusted('anything', 443, 'whatever'), isFalse);
    });

    test('unpin removes the exception', () async {
      final store = CertPinStore(InMemoryKeyValueStorage());
      await store.pin('a.example.com', 443, 'aa');
      await store.unpin('a.example.com', 443);
      expect(store.isTrusted('a.example.com', 443, 'aa'), isFalse);
    });
  });

  group('KeyValueStorage.clear', () {
    test('drops every key, which is what a server switch relies on', () async {
      final s = InMemoryKeyValueStorage();
      await s.set<String>('a', '1');
      await s.set<String>('b', '2');
      await s.clear();
      expect(s.get<String>('a'), isNull);
      expect(s.get<String>('b'), isNull);
    });
  });
}
