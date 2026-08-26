import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/features/accounts/data/account_store.dart';
import 'package:intellipilot/features/accounts/data/secret_store.dart';
import 'package:intellipilot/features/accounts/domain/account.dart';

Account _acct(String server, String user, {String username = 'ann'}) => Account(
  serverUrl: server,
  userId: user,
  username: username,
  email: '$username@example.com',
);

void main() {
  late InMemorySecretStore secure;
  late AccountStore store;

  setUp(() {
    secure = InMemorySecretStore();
    store = AccountStore(secrets: secure);
  });

  group('Account identity', () {
    test('is the (server, user) pair, not the user alone', () {
      final a = _acct('https://one.example.com', 'u1');
      final b = _acct('https://two.example.com', 'u1');
      // Same person, two instances — two distinct accounts.
      expect(a == b, isFalse);
      expect(a.key, isNot(b.key));
    });

    test('same username on different servers stays distinguishable', () {
      final a = _acct('https://one.example.com', 'u1');
      final b = _acct('https://two.example.com', 'u2');
      expect(a.userLabel, b.userLabel); // identical usernames
      expect(a.serverLabel, isNot(b.serverLabel)); // server disambiguates
    });
  });

  group('serverLabel', () {
    test('shows the host, hiding a default port', () {
      expect(
        _acct('https://pilot.securium.ch', 'u').serverLabel,
        'pilot.securium.ch',
      );
      expect(
        _acct('https://pilot.securium.ch:443', 'u').serverLabel,
        'pilot.securium.ch',
      );
      expect(_acct('http://example.com:80', 'u').serverLabel, 'example.com');
    });

    test('keeps a non-default port, and shows a bare IP as-is', () {
      // A LAN instance has no domain to show — the IP IS the label.
      expect(
        _acct('http://192.168.1.10:8080', 'u').serverLabel,
        '192.168.1.10:8080',
      );
    });
  });

  group('store', () {
    test('upsert stores the account and its token', () async {
      final a = _acct('https://one.example.com', 'u1');
      await store.upsert(a, refreshToken: 'tok-1');

      expect((await store.list()).single, a);
      expect(await store.tokenFor(a), 'tok-1');
    });

    test(
      'upserting an existing account refreshes it, not duplicates it',
      () async {
        final a = _acct('https://one.example.com', 'u1');
        await store.upsert(a, refreshToken: 'tok-1');
        await store.upsert(a, refreshToken: 'tok-2');

        expect((await store.list()).length, 1);
        expect(await store.tokenFor(a), 'tok-2');
      },
    );

    test('tokens are kept per account, never shared', () async {
      final a = _acct('https://one.example.com', 'u1');
      final b = _acct('https://two.example.com', 'u1');
      await store.upsert(a, refreshToken: 'tok-a');
      await store.upsert(b, refreshToken: 'tok-b');

      expect(await store.tokenFor(a), 'tok-a');
      expect(await store.tokenFor(b), 'tok-b');
    });

    test('updateToken replaces a rotated token', () async {
      // The server revokes the whole family if a spent token is replayed, so
      // this must overwrite rather than accumulate.
      final a = _acct('https://one.example.com', 'u1');
      await store.upsert(a, refreshToken: 'tok-1');
      await store.updateToken(a, 'tok-2');
      expect(await store.tokenFor(a), 'tok-2');
    });

    test('remove forgets the account AND its token', () async {
      final a = _acct('https://one.example.com', 'u1');
      await store.upsert(a, refreshToken: 'tok-1');
      await store.setActive(a);
      await store.remove(a);

      expect(await store.list(), isEmpty);
      expect(await store.tokenFor(a), isNull);
      expect(await store.activeKey(), isNull);
    });

    test('list is ordered most-recently-used first', () async {
      final a = _acct('https://a.example.com', 'u1');
      final b = _acct('https://b.example.com', 'u2');
      await store.upsert(a, refreshToken: 't');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.upsert(b, refreshToken: 't');

      expect((await store.list()).first, b);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.setActive(a);
      expect((await store.list()).first, a);
    });

    test(
      'nextAfter picks the most recent survivor for post-logout switch',
      () async {
        final a = _acct('https://a.example.com', 'u1');
        final b = _acct('https://b.example.com', 'u2');
        await store.upsert(a, refreshToken: 't');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await store.upsert(b, refreshToken: 't');

        expect(await store.nextAfter(b), a);
        // Last account out leaves nobody to switch to.
        await store.remove(a);
        expect(await store.nextAfter(b), isNull);
      },
    );

    test('rememberRoute round-trips per account', () async {
      final a = _acct('https://a.example.com', 'u1');
      final b = _acct('https://b.example.com', 'u2');
      await store.upsert(a, refreshToken: 't');
      await store.upsert(b, refreshToken: 't');

      await store.rememberRoute(a, '/projects/PS/boards/main');
      await store.rememberRoute(b, '/projects/XX/issues');

      final list = await store.list();
      expect(
        list.firstWhere((x) => x == a).lastRoute,
        '/projects/PS/boards/main',
      );
      expect(list.firstWhere((x) => x == b).lastRoute, '/projects/XX/issues');
    });

    test('a corrupt store reports empty rather than wedging startup', () async {
      secure.data['accounts.list'] = '{not json';
      expect(await store.list(), isEmpty);
    });

    test('active account round-trips and can be cleared', () async {
      final a = _acct('https://a.example.com', 'u1');
      await store.upsert(a, refreshToken: 't');
      await store.setActive(a);
      expect(await store.active(), a);
      await store.clearActive();
      expect(await store.active(), isNull);
    });
  });
}
