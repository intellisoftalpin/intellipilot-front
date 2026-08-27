// The `_`-prefixed collaborators are intentionally private fields while the
// constructor keeps readable public parameter names.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/features/accounts/data/account_store.dart';
import 'package:intellipilot/features/accounts/domain/account.dart';
import 'package:intellipilot/features/accounts/domain/account_scope.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';

/// Owns the multi-account lifecycle: adopting a fresh login, switching between
/// signed-in accounts, and logging one out without disturbing the others.
///
/// A [ChangeNotifier] because the set of accounts changes *after* the UI that
/// shows it has been built. Adoption follows a login by a profile round-trip,
/// while the login screen navigates on success immediately — so anything that
/// read the list once at construction reliably missed the account just added
/// and showed no switcher at all.
///
/// Desktop and mobile only. Web is served by its own instance and keeps exactly
/// one cookie-backed session, so nothing here runs there.
class AccountSwitcher extends ChangeNotifier {
  AccountSwitcher({
    required AccountStore store,
    required AccountScope scope,
    required ServerEndpoint endpoint,
    required ApiClient apiClient,
    required AuthRepository auth,
    required ProfileRepository profiles,
    required SessionBloc Function() session,
    required ProjectEventsService Function() events,
    void Function()? onServerChanged,
  }) : _onServerChanged = onServerChanged,
       _store = store,
       _scope = scope,
       _endpoint = endpoint,
       _api = apiClient,
       _auth = auth,
       _profiles = profiles,
       _session = session,
       _events = events;

  final AccountStore _store;
  final AccountScope _scope;
  final ServerEndpoint _endpoint;
  final ApiClient _api;
  final AuthRepository _auth;
  final ProfileRepository _profiles;
  final SessionBloc Function() _session;
  final ProjectEventsService Function() _events;

  /// Invoked when [_apply] actually moves the app to a different server.
  ///
  /// Anything derived from *which* server we talk to — the version
  /// compatibility verdict above all — is stale the moment the endpoint
  /// changes, and a stale "your app is too old" verdict from one server would
  /// otherwise block the app on another.
  final void Function()? _onServerChanged;

  /// The active account's refresh token, held in memory because
  /// [SessionBloc.refreshTokenProvider] is synchronous and a keychain read is
  /// not. Kept current by [_adopt] and by [rememberRotatedToken].
  String? _activeToken;

  /// Guards a switch against a concurrent refresh. Without it, a rotation
  /// landing mid-switch could persist account A's new token while B is being
  /// activated — and a token written to the wrong account is a token that gets
  /// replayed, which revokes a whole session family server-side.
  bool _switching = false;
  bool get isSwitching => _switching;

  Account? _active;
  Account? get active => _active;

  /// Sync accessor for [SessionBloc.refreshTokenProvider].
  String? currentRefreshToken() => _activeToken;

  /// Persist a rotated token for the active account. Wired to
  /// [SessionBloc.onTokensRotated].
  void rememberRotatedToken(String token) {
    _activeToken = token;
    final account = _active;
    if (account != null) {
      unawaited(_store.updateToken(account, token));
    }
  }

  /// Restore the last active account at startup. Returns false when there is
  /// none, which sends the user to the login screen.
  Future<bool> restore() async {
    final account = await _store.active();
    if (account == null) return false;
    final token = await _store.tokenFor(account);
    if (token == null) {
      // Metadata without a credential is unusable — drop it rather than
      // leaving a phantom entry in the switcher.
      await _store.remove(account);
      return false;
    }
    await _apply(account, token);
    return true;
  }

  /// Adopt the account that just signed in.
  ///
  /// [tokens] must carry `refresh_token`: on these platforms the server returns
  /// it because the caller authenticated by body rather than cookie.
  Future<Account?> adoptAfterLogin(TokenResponse tokens) async {
    final refresh = tokens.refreshToken;
    if (refresh == null || refresh.isEmpty) return null;
    // The session must be live before the profile can be read.
    _activeToken = refresh;
    final profile = (await _profiles.getProfile()).valueOrNull;
    if (profile == null) return null;
    final account = Account(
      serverUrl: _endpoint.effective,
      userId: profile.id,
      username: profile.username,
      email: profile.email,
      fullName: profile.fullName,
    );
    await _store.upsert(account, refreshToken: refresh);
    await _apply(account, refresh);
    // The add-account run (if this was one) succeeded, so there is no longer a
    // suspended account to restore — the user is on the new one now.
    _suspended = null;
    notifyListeners();
    return account;
  }

  /// Switch to another signed-in account.
  ///
  /// Ordering matters and is the whole point of this method: the outgoing
  /// identity's live connections are closed before the incoming one's
  /// credentials are used, so no request is ever made with a mismatched pair of
  /// (server, token).
  Future<bool> switchTo(Account account, {String? currentRoute}) async {
    if (_switching || account == _active) return false;
    _switching = true;
    try {
      // 1. Remember where the outgoing account was, so returning restores it.
      final outgoing = _active;
      if (outgoing != null && currentRoute != null) {
        await _store.rememberRoute(outgoing, currentRoute);
      }

      // 2. Close the outgoing identity's streams and stop its refresh timer.
      _events().shutdownAll();
      _session().add(const SessionLogoutRequested(callBackend: false));

      // 3. Point at the incoming account's server before using its token.
      final token = await _store.tokenFor(account);
      if (token == null) {
        await _store.remove(account);
        notifyListeners();
        return false;
      }
      await _apply(account, token);

      // 4. Exchange the stored refresh token for a live session.
      final res = await _auth.refresh(refreshToken: token);
      final tokens = res.valueOrNull;
      if (tokens == null) {
        // The stored credential is dead (revoked, expired, or the family was
        // revoked). Drop the account rather than leaving one that cannot work.
        await _store.remove(account);
        _active = null;
        _activeToken = null;
        _scope.set(null);
        notifyListeners();
        return false;
      }
      rememberRotatedToken(tokens.refreshToken ?? token);
      _session().add(SessionEstablished(tokens));
      // Choosing an account explicitly ends any add-account run in progress —
      // otherwise a later cancel would resurrect an account the user has
      // already moved on from.
      _suspended = null;
      notifyListeners();
      return true;
    } finally {
      _switching = false;
    }
  }

  /// The account put on hold by [beginAddAccount], awaiting a completed login
  /// or a cancellation.
  Account? _suspended;

  /// The account an add-account run stood down, if any. Read by the wizard
  /// header, which must still name it after step ① cleared [active].
  Account? get suspendedAccount => _suspended;

  /// Stand the active account down so a *different* server can be adopted.
  ///
  /// Mirrors steps 1–2 of [switchTo], and exists for the same reason: between
  /// pointing the app at the new server and signing in there, the app would
  /// otherwise still hold the previous account's token — and one background
  /// refresh or SSE reconnect in that window sends account A's credential to
  /// server B. So the outgoing identity's connections are closed first.
  ///
  /// The account is not removed: it stays signed in and stored, so
  /// [cancelAddAccount] can bring it back. Call this only once validation has
  /// succeeded — a failed connect attempt must leave the session untouched.
  Future<void> beginAddAccount({String? currentRoute}) async {
    final outgoing = _active;
    if (outgoing == null) return;
    if (currentRoute != null) {
      await _store.rememberRoute(outgoing, currentRoute);
    }
    _events().shutdownAll();
    _session().add(const SessionLogoutRequested(callBackend: false));
    _suspended = outgoing;
    // Cleared rather than kept, so nothing can read a live identity while the
    // app points at a server that has not authenticated it.
    _active = null;
    _activeToken = null;
    _scope.set(null);
    notifyListeners();
  }

  /// Abandon an add-account run and restore whatever [beginAddAccount] stood
  /// down — server, token and session.
  ///
  /// Returns false when there was nothing to restore, which is the normal case
  /// for cancelling at step ① before any server was adopted.
  Future<bool> cancelAddAccount() async {
    final back = _suspended;
    _suspended = null;
    if (back == null) return false;
    return switchTo(back);
  }

  /// Log the active account out and activate the next one, if any.
  ///
  /// Returns the account now active, or null when none remain (the caller then
  /// shows the login screen).
  Future<Account?> logoutActive() async {
    final going = _active;
    if (going == null) return null;
    final token = _activeToken;
    // Best effort: revoke server-side, but a network failure must not leave the
    // account stuck locally.
    await _auth.logout(refreshToken: token);
    await _store.remove(going);
    _events().shutdownAll();

    final next = await _store.nextAfter(going);
    if (next == null) {
      _active = null;
      _activeToken = null;
      _scope.set(null);
      await _store.clearActive();
      notifyListeners();
      return null;
    }
    await switchTo(next);
    return _active;
  }

  /// Record the active account's current route, so a later switch back returns
  /// to it. Cheap enough to call on every navigation.
  Future<void> rememberRoute(String route) async {
    final account = _active;
    if (account == null || _switching) return;
    // The shell sees every navigation, so skip repeats rather than writing to
    // the keychain on each rebuild.
    if (route == _lastRememberedRoute) return;
    _lastRememberedRoute = route;
    await _store.rememberRoute(account, route);
  }

  String? _lastRememberedRoute;

  /// Every account with stored credentials, active or not.
  Future<List<Account>> accounts() => _store.list();

  /// The route to land on after switching in: the remembered one, or null to
  /// use the default landing page.
  Future<String?> restoredRouteFor(Account account) async {
    final accounts = await _store.list();
    return accounts.where((a) => a == account).firstOrNull?.lastRoute;
  }

  /// Make [account] the active identity: endpoint, scope, active pointer.
  Future<void> _apply(Account account, String token) async {
    if (account.serverUrl != _endpoint.effective) {
      await _endpoint.save(account.serverUrl);
      _api.baseUrl = account.serverUrl;
      _onServerChanged?.call();
    }
    _active = account;
    _activeToken = token;
    _lastRememberedRoute = null;
    _scope.set(account);
    await _store.setActive(account);
    // Single point where the active account moves, so a startup restore is
    // covered along with adoption and switching.
    notifyListeners();
  }
}
