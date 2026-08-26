// `_secrets` is intentionally a private field behind a public parameter.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:intellipilot/features/accounts/data/secret_store.dart';
import 'package:intellipilot/features/accounts/domain/account.dart';

/// Persists the signed-in accounts and their refresh tokens.
///
/// Everything lives in the platform keychain (Keychain on Apple, Keystore-backed
/// storage on Android) rather than Hive: a refresh token is a bearer credential
/// with a long life, and Hive boxes are plaintext files on disk. Account
/// metadata rides along in the same store so the list and the tokens cannot
/// drift apart.
class AccountStore {
  AccountStore({required SecretStore secrets}) : _secrets = secrets;

  final SecretStore _secrets;

  static const _accountsKey = 'accounts.list';
  static const _activeKey = 'accounts.active';
  static String _tokenKey(String accountKey) => 'accounts.token.$accountKey';

  // ---------------------------------------------------------------------------
  // accounts
  // ---------------------------------------------------------------------------

  /// Every signed-in account, most recently used first — which is the order the
  /// switcher shows and the order "log out, then activate the next" follows.
  Future<List<Account>> list() async {
    final raw = await _secrets.read(_accountsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final accounts = decoded
          .whereType<Map<String, dynamic>>()
          .map(Account.fromJson)
          .toList();
      accounts.sort((a, b) {
        final at = a.lastUsedAt;
        final bt = b.lastUsedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      return accounts;
    } on Object {
      // Corrupt store: report empty rather than wedging startup. The user
      // re-authenticates, which is recoverable; a crash loop is not.
      return const [];
    }
  }

  Future<void> _write(List<Account> accounts) => _secrets.write(
    _accountsKey,
    jsonEncode([for (final a in accounts) a.toJson()]),
  );

  /// Add or update an account and store its refresh token.
  ///
  /// Upsert by `(serverUrl, userId)`, so signing into an account that is
  /// already present refreshes its token instead of duplicating the row.
  Future<void> upsert(Account account, {required String refreshToken}) async {
    final accounts = await list();
    final without = accounts.where((a) => a != account).toList();
    await _write([account.copyWith(lastUsedAt: DateTime.now()), ...without]);
    await _secrets.write(_tokenKey(account.key), refreshToken);
  }

  /// Replace an account's stored token after a rotation.
  ///
  /// **Must be called on every successful refresh, before the previous token
  /// could be replayed.** The server treats a reused refresh token as a
  /// compromise and revokes the entire session family, so a stale token here
  /// does not merely fail — it signs the account out and writes a
  /// `reuse_detected` entry to the audit log.
  Future<void> updateToken(Account account, String refreshToken) =>
      _secrets.write(_tokenKey(account.key), refreshToken);

  Future<String?> tokenFor(Account account) =>
      _secrets.read(_tokenKey(account.key));

  /// Forget an account entirely, token included.
  Future<void> remove(Account account) async {
    final accounts = await list();
    await _write(accounts.where((a) => a != account).toList());
    await _secrets.delete(_tokenKey(account.key));
    if (await activeKey() == account.key) {
      await _secrets.delete(_activeKey);
    }
  }

  /// Record the route an account was last on, so switching back returns there.
  Future<void> rememberRoute(Account account, String route) async {
    final accounts = await list();
    await _write([
      for (final a in accounts)
        if (a == account) a.copyWith(lastRoute: route) else a,
    ]);
  }

  // ---------------------------------------------------------------------------
  // active account
  // ---------------------------------------------------------------------------

  Future<String?> activeKey() => _secrets.read(_activeKey);

  Future<Account?> active() async {
    final key = await activeKey();
    if (key == null) return null;
    final accounts = await list();
    return accounts.where((a) => a.key == key).firstOrNull;
  }

  /// Make [account] active and stamp it as most recently used.
  Future<void> setActive(Account account) async {
    final accounts = await list();
    await _write([
      for (final a in accounts)
        if (a == account) a.copyWith(lastUsedAt: DateTime.now()) else a,
    ]);
    await _secrets.write(_activeKey, account.key);
  }

  Future<void> clearActive() => _secrets.delete(_activeKey);

  /// The account to fall back to when the active one logs out: the most
  /// recently used of the rest, or null when none remain.
  Future<Account?> nextAfter(Account removed) async {
    final accounts = await list();
    return accounts.where((a) => a != removed).firstOrNull;
  }
}
