import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/accounts/data/scoped_storage.dart';
import 'package:intellipilot/features/accounts/domain/account.dart';
import 'package:intellipilot/features/accounts/domain/account_scope.dart';

Account _acct(String server, String user) =>
    Account(serverUrl: server, userId: user, username: 'ann', email: 'a@b');

void main() {
  late InMemoryKeyValueStorage inner;
  late AccountScope scope;
  late ScopedKeyValueStorage store;

  setUp(() {
    inner = InMemoryKeyValueStorage();
    scope = AccountScope();
    store = ScopedKeyValueStorage(inner: inner, scope: () => scope.key);
  });

  test('two accounts cannot see one another data under the same key', () async {
    // This is the whole point: every per-user cache keys by (userId, projectId)
    // with no server dimension, so without scoping the same key would collide
    // across instances.
    scope.set(_acct('https://one.example.com', 'u1'));
    await store.set<String>('board:p1', 'cards-from-one');

    scope.set(_acct('https://two.example.com', 'u1'));
    expect(store.get<String>('board:p1'), isNull);
    await store.set<String>('board:p1', 'cards-from-two');

    scope.set(_acct('https://one.example.com', 'u1'));
    expect(store.get<String>('board:p1'), 'cards-from-one');
  });

  test('the same user on the same server sees their own data again', () async {
    final a = _acct('https://one.example.com', 'u1');
    scope.set(a);
    await store.set<String>('k', 'v');
    scope.set(null);
    scope.set(a);
    expect(store.get<String>('k'), 'v');
  });

  test('data written with no account is not visible to any account', () async {
    // Otherwise whoever signs in first would inherit pre-sign-in state.
    scope.set(null);
    await store.set<String>('k', 'anonymous');
    scope.set(_acct('https://one.example.com', 'u1'));
    expect(store.get<String>('k'), isNull);
  });

  test('remove only affects the active account', () async {
    final a = _acct('https://a.example.com', 'u1');
    final b = _acct('https://b.example.com', 'u2');
    scope.set(a);
    await store.set<String>('k', 'a');
    scope.set(b);
    await store.set<String>('k', 'b');

    await store.remove('k');
    expect(store.get<String>('k'), isNull);
    scope.set(a);
    expect(store.get<String>('k'), 'a');
  });

  test('scope is resolved per call, not captured at construction', () async {
    // Switching accounts must take effect without rebuilding the DI graph.
    scope.set(_acct('https://a.example.com', 'u1'));
    await store.set<String>('k', 'first');
    scope.set(_acct('https://b.example.com', 'u1'));
    await store.set<String>('k', 'second');
    expect(
      inner.get<String>('acct:${_acct('https://a.example.com', 'u1').key}/k'),
      'first',
    );
    expect(
      inner.get<String>('acct:${_acct('https://b.example.com', 'u1').key}/k'),
      'second',
    );
  });

  test('AccountScope notifies only on a real change', () {
    var notifications = 0;
    scope.addListener(() => notifications++);
    final a = _acct('https://a.example.com', 'u1');
    scope.set(a);
    scope.set(a);
    expect(notifications, 1);
    scope.set(null);
    expect(notifications, 2);
  });
}
