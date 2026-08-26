import 'package:flutter/foundation.dart';
import 'package:intellipilot/features/accounts/domain/account.dart';

/// The active account's namespace for cached data.
///
/// Held separately from the account list so the storage decorators can read it
/// synchronously on every key access — secure storage is async, and a cache
/// read cannot await a keychain round-trip.
///
/// Empty means "no account active", which yields its own namespace rather than
/// falling back to a shared one: data written before sign-in must not be handed
/// to whoever signs in first.
class AccountScope extends ChangeNotifier {
  String _key = '';

  String get key => _key;

  void set(Account? account) {
    final next = account?.key ?? '';
    if (next == _key) return;
    _key = next;
    notifyListeners();
  }
}
