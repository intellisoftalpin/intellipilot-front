import 'dart:async';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/session/session_sync.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/interceptors/refresh_interceptor.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';

/// Time before access-token expiry to attempt refresh proactively.
const _refreshLeadTime = Duration(seconds: 30);

/// Minimum delay until refresh — guards against an immediately-expiring token
/// looping the refresh timer.
const _refreshMinDelay = Duration(seconds: 5);

/// A request about to go out with a token this close to expiry renews it
/// first rather than collecting a 401.
const _preflightMargin = Duration(seconds: 10);

/// Longest a request waits for a renewal before going out with the token it
/// has — matching [RefreshInterceptor.maxWait], so the two never stack up
/// into an unbounded wait.
const _preflightMaxWait = Duration(seconds: 20);

/// Retry delays after a renewal failed for want of a network or a healthy
/// server; the last one repeats.
const _transientRetryDelays = [
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 40),
  Duration(seconds: 60),
];

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

sealed class SessionState extends Equatable {
  const SessionState();
  @override
  List<Object?> get props => const [];
}

/// Cold-start state before we've decided whether a session is restorable.
final class SessionUnknown extends SessionState {
  const SessionUnknown();
}

/// Login submit in progress.
final class SessionAuthenticating extends SessionState {
  const SessionAuthenticating();
}

/// Backend asked for a second factor; the UI must collect a code.
final class SessionMfaRequired extends SessionState {
  const SessionMfaRequired({required this.mfaToken, required this.methods});
  final String mfaToken;
  final List<String> methods;

  @override
  List<Object?> get props => [mfaToken, methods];
}

/// We have an access token and the refresh timer is running.
final class SessionAuthenticated extends SessionState {
  const SessionAuthenticated({
    required this.accessToken,
    required this.expiresAt,
  });
  final String accessToken;
  final DateTime expiresAt;

  @override
  List<Object?> get props => [accessToken, expiresAt];
}

/// Refresh is in-flight; the old access token may still be valid in the
/// margin. UI typically renders the previous screen during this.
final class SessionRefreshing extends SessionState {
  const SessionRefreshing({required this.staleAccessToken});
  final String staleAccessToken;

  @override
  List<Object?> get props => [staleAccessToken];
}

final class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated({this.reason});
  final SessionEndReason? reason;

  @override
  List<Object?> get props => [reason];
}

enum SessionEndReason {
  startup,
  loggedOut,
  refreshFailed,
  passwordChanged,
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

sealed class SessionEvent extends Equatable {
  const SessionEvent();
  @override
  List<Object?> get props => const [];
}

/// Fired once at app start; attempts a silent refresh.
final class SessionStartupRequested extends SessionEvent {
  const SessionStartupRequested();
}

/// Issued by the login flow when the backend asks for a 2FA challenge.
/// Phase 3 will introduce the matching cubit that consumes this state.
final class SessionMfaChallenged extends SessionEvent {
  const SessionMfaChallenged({required this.mfaToken, required this.methods});
  final String mfaToken;
  final List<String> methods;

  @override
  List<Object?> get props => [mfaToken, methods];
}

/// Result of a successful credentials / 2FA / passkey flow.
final class SessionEstablished extends SessionEvent {
  const SessionEstablished(this.tokens);
  final TokenResponse tokens;

  @override
  List<Object?> get props => [tokens];
}

/// Either a manual user action or a 401 race that exhausted refresh attempts.
final class SessionLogoutRequested extends SessionEvent {
  const SessionLogoutRequested({this.callBackend = true});
  final bool callBackend;

  @override
  List<Object?> get props => [callBackend];
}

/// Triggered by the refresh timer or by the [RefreshInterceptor] hook.
final class SessionRefreshRequested extends SessionEvent {
  const SessionRefreshRequested();
}

final class _SessionRefreshSucceeded extends SessionEvent {
  const _SessionRefreshSucceeded(this.tokens);
  final TokenResponse tokens;

  @override
  List<Object?> get props => [tokens];
}

final class _SessionRefreshFailed extends SessionEvent {
  const _SessionRefreshFailed({required this.failure});

  /// Why the renewal failed; decides whether the session ends.
  final AppFailure failure;

  @override
  List<Object?> get props => [failure];
}

/// Another tab obtained a fresh access token.
final class _SessionPeerToken extends SessionEvent {
  const _SessionPeerToken(this.token);
  final SharedAccessToken token;

  @override
  List<Object?> get props => [token.accessToken];
}

/// Another tab signed the user out.
final class _SessionPeerSignedOut extends SessionEvent {
  const _SessionPeerSignedOut();
}

/// Problem code the server answers a refresh with when a concurrent request
/// holding the same token rotated it a moment earlier.
const refreshSupersededCode = 'refresh_superseded';

/// A peer's access token is only worth adopting with at least this much life
/// left; anything shorter would just trigger a refresh straight away.
const _minAdoptableLife = Duration(seconds: 60);

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc({
    required AuthRepository repository,
    this.onSessionEnded,
    this.refreshTokenProvider,
    this.onTokensRotated,
    this.onSessionEstablished,
    SessionSync? sync,
    Duration Function()? supersededRetryDelay,
    Duration Function()? refreshJitter,
  }) : _repo = repository,
       _sync = sync ?? SessionSync.none(),
       _supersededRetryDelay = supersededRetryDelay ?? _randomRetryDelay,
       _refreshJitter = refreshJitter ?? _randomJitter,
       super(const SessionUnknown()) {
    on<SessionStartupRequested>(_onStartup);
    on<SessionMfaChallenged>(_onMfaChallenged);
    on<SessionEstablished>(_onEstablished);
    on<SessionRefreshRequested>(_onRefresh);
    on<_SessionRefreshSucceeded>(_onRefreshSucceeded);
    on<_SessionRefreshFailed>(_onRefreshFailed);
    on<SessionLogoutRequested>(_onLogout);
    on<_SessionPeerToken>(_onPeerToken);
    on<_SessionPeerSignedOut>(_onPeerSignedOut);
    _sync.answerWith(_shareableToken);
    _syncSub = _sync.incoming.listen((m) {
      if (isClosed) return;
      switch (m) {
        case PeerTokenMessage(:final token):
          add(_SessionPeerToken(token));
        case PeerSignedOutMessage():
          add(const _SessionPeerSignedOut());
      }
    });
  }

  final SessionSync _sync;
  late final StreamSubscription<SessionSyncMessage> _syncSub;
  final Duration Function() _supersededRetryDelay;
  final Duration Function() _refreshJitter;

  /// The one refresh in flight, shared by startup, the proactive timer and
  /// the 401 hook. The server rotates the refresh token on every use and
  /// reads a second presentation of it as theft, so two refreshes must never
  /// run side by side — within a tab this guarantees it, across tabs
  /// [SessionSync.exclusive] does.
  Future<Result<TokenResponse, AppFailure>>? _inflight;

  static final _random = math.Random();

  static Duration _randomRetryDelay() =>
      Duration(milliseconds: 300 + _random.nextInt(500));

  /// Spreads proactive refreshes so tabs opened together don't all fire at
  /// the same instant.
  static Duration _randomJitter() =>
      Duration(milliseconds: _random.nextInt(15000));

  final AuthRepository _repo;

  /// Fired whenever the session ends (logout or a failed refresh) — used to
  /// purge per-user local caches so no data crosses accounts.
  final void Function()? onSessionEnded;

  /// Supplies the active account's refresh token on platforms that hold several
  /// accounts and therefore cannot rely on a single cookie jar. Null on web,
  /// where the HttpOnly cookie is used and this must stay out of the way.
  final String? Function()? refreshTokenProvider;

  /// Called with a rotated refresh token immediately after every successful
  /// refresh.
  ///
  /// **This is the write-after-rotate invariant and it is not optional.** The
  /// server treats a replayed refresh token as a compromise and revokes the
  /// whole session family, so persisting late does not merely lose a rotation —
  /// it signs the account out and writes a `reuse_detected` audit entry.
  final void Function(String refreshToken)? onTokensRotated;

  /// Called whenever a session is newly established — password login, MFA
  /// completion, passkey, invitation acceptance. One hook here covers every
  /// entry point, so a new sign-in path cannot forget to register its account.
  final void Function(TokenResponse tokens)? onSessionEstablished;
  Timer? _refreshTimer;

  /// Retries a renewal that failed for want of a network or a healthy server.
  Timer? _retryTimer;
  int _retryAttempt = 0;

  /// When the access token held across a renewal expires — restored if the
  /// renewal fails transiently, since the session itself is still alive.
  DateTime? _heldExpiresAt;

  /// Bumped whenever a session is newly established, so a sign-in or an
  /// account switch can be told apart from the same user's token renewal.
  int _identity = 0;

  /// Which signed-in identity the current session belongs to; changes on
  /// sign-in and account switch, never on a token renewal.
  int get identity => _identity;

  /// Session changes the router has to react to: signing in or out, an MFA
  /// challenge, a newly established identity.
  ///
  /// A token renewal is none of these, yet it flips the state twice
  /// (refreshing, then authenticated again). Refreshing the router on those
  /// rebuilt every open page, and pages that load in `build` restarted their
  /// loading — with the stale token, so it ran into a 401 of its own.
  Stream<Object> get routingChanges => stream.map(_routingKey).distinct();

  Object _routingKey(SessionState s) => switch (s) {
    SessionAuthenticated() ||
    SessionRefreshing() => (SessionAuthenticated, _identity),
    _ => s.runtimeType,
  };

  /// Hand a rotated refresh token to the account store before the previous one
  /// could ever be replayed. No-op on web, where the server rotates the cookie.
  void _persistRotated(TokenResponse tokens) {
    final rotated = tokens.refreshToken;
    if (rotated != null && rotated.isNotEmpty) {
      onTokensRotated?.call(rotated);
    }
  }

  /// Access-token provider for the [AuthInterceptor].
  String? get currentAccessToken {
    final s = state;
    if (s is SessionAuthenticated) return s.accessToken;
    if (s is SessionRefreshing) return s.staleAccessToken;
    return null;
  }

  /// Access token for an outgoing request, renewed first when the one held
  /// has expired or a renewal is already running.
  ///
  /// Browsers pause the refresh timer in background tabs and while the device
  /// sleeps, so the first requests after a wake-up would otherwise go out with
  /// an expired token, each come back 401 and wait to be retried. Never waits
  /// longer than [maxWait]: past that the request goes out with the token at
  /// hand and the 401 path takes over.
  Future<String?> freshAccessToken({
    Duration maxWait = _preflightMaxWait,
  }) async {
    final s = state;
    if (s is SessionAuthenticated) {
      final expiring =
          s.expiresAt.difference(DateTime.now()) < _preflightMargin;
      // Backing off after a failed renewal: retrying for every request would
      // hammer a server that is down. The retry timer and 401s still renew.
      if (!expiring || _retryTimer != null) return s.accessToken;
      add(const SessionRefreshRequested());
    } else if (s is! SessionRefreshing) {
      return currentAccessToken;
    }
    try {
      await stream
          .firstWhere(
            (s) => s is! SessionRefreshing && s is! SessionUnknown,
            // The bloc closed while we waited.
            orElse: () => state,
          )
          .timeout(maxWait);
    } on TimeoutException {
      // Go out with what we have.
    }
    return currentAccessToken;
  }

  /// Renew now if the token is about to expire — called when the app comes
  /// back to the foreground, where the refresh timer may not have run.
  void renewIfStale() {
    final s = state;
    if (s is! SessionAuthenticated) return;
    if (s.expiresAt.difference(DateTime.now()) < _refreshLeadTime) {
      add(const SessionRefreshRequested());
    }
  }

  /// Hook the [RefreshInterceptor] calls on 401.
  Future<RefreshOutcome> refreshHook() async {
    // The server just refused the token we hold: never adopt it back from a
    // peer, or every request would 401 against it without ever refreshing.
    final s = state;
    // Signed out: there is nothing to renew, [_onRefresh] ignores the request
    // and the wait below would only end at the next sign-in.
    if (s is SessionUnauthenticated) return RefreshOutcome.failed;
    final rejected = switch (s) {
      SessionAuthenticated(:final accessToken) => accessToken,
      SessionRefreshing(:final staleAccessToken) => staleAccessToken,
      _ => null,
    };
    if (rejected != null) _markRejected(rejected);
    add(const SessionRefreshRequested());
    // Wait until we leave the Refreshing state.
    final next = await stream.firstWhere(
      (s) => s is! SessionRefreshing && s is! SessionUnknown,
    );
    // A renewal that failed transiently keeps the session on the token the
    // server just refused; retrying the request with it would only 401 again.
    return next is SessionAuthenticated && next.accessToken != rejected
        ? RefreshOutcome.refreshed
        : RefreshOutcome.failed;
  }

  // -------------------------------------------------------------------------
  // Handlers
  // -------------------------------------------------------------------------

  Future<void> _onStartup(
    SessionStartupRequested event,
    Emitter<SessionState> emit,
  ) async {
    // A new tab asks the open ones first (inside the refresh): adopting their
    // access token needs no refresh at all, so the shared cookie is untouched.
    final result = await _refreshShared();
    result.when(
      ok: (tokens) {
        _scheduleRefresh(tokens.expiresIn);
        emit(
          SessionAuthenticated(
            accessToken: tokens.accessToken,
            expiresAt: _expiresAt(tokens.expiresIn),
          ),
        );
      },
      err: (_) => emit(
        const SessionUnauthenticated(reason: SessionEndReason.startup),
      ),
    );
  }

  void _onMfaChallenged(
    SessionMfaChallenged event,
    Emitter<SessionState> emit,
  ) {
    emit(
      SessionMfaRequired(mfaToken: event.mfaToken, methods: event.methods),
    );
  }

  void _onEstablished(SessionEstablished event, Emitter<SessionState> emit) {
    _identity++;
    onSessionEstablished?.call(event.tokens);
    _announce(event.tokens);
    _scheduleRefresh(event.tokens.expiresIn);
    emit(
      SessionAuthenticated(
        accessToken: event.tokens.accessToken,
        expiresAt: _expiresAt(event.tokens.expiresIn),
      ),
    );
  }

  Future<void> _onRefresh(
    SessionRefreshRequested event,
    Emitter<SessionState> emit,
  ) async {
    // Already refreshing (startup, the timer or an earlier 401): that one
    // settles the state for everyone waiting on it.
    if (_inflight != null) return;
    final current = state;
    if (current is! SessionAuthenticated && current is! SessionRefreshing) {
      return;
    }
    final stale = current is SessionAuthenticated
        ? current.accessToken
        : (current as SessionRefreshing).staleAccessToken;
    if (current is SessionAuthenticated) _heldExpiresAt = current.expiresAt;
    emit(SessionRefreshing(staleAccessToken: stale));

    final result = await _refreshShared();
    result.when(
      ok: (tokens) => add(_SessionRefreshSucceeded(tokens)),
      err: (failure) => add(_SessionRefreshFailed(failure: failure)),
    );
  }

  /// Join the refresh in flight, or start one.
  Future<Result<TokenResponse, AppFailure>> _refreshShared() =>
      _inflight ??= _refreshExclusive().whenComplete(() => _inflight = null);

  Future<Result<TokenResponse, AppFailure>> _refreshExclusive() {
    final requestedAt = DateTime.now();
    return _sync.exclusive(() async {
      // Another tab may hold a perfectly good token — one it refreshed while
      // we queued for the lock, or simply the one it has had all along (a
      // freshly opened tab). Taking it spares the shared cookie a rotation.
      // Asked for explicitly because a broadcast of that refresh is not
      // guaranteed to reach us before the lock does.
      final peer = _peerTokenSince(requestedAt) ?? await _askPeersForToken();
      if (peer != null) return Ok<TokenResponse, AppFailure>(_fromPeer(peer));

      var result = await _repo.refresh(
        refreshToken: refreshTokenProvider?.call(),
      );
      if (_isSuperseded(result)) {
        // A concurrent request rotated the token a moment ago. The jar (or,
        // natively, the account store) now holds its successor: try again.
        await Future<void>.delayed(_supersededRetryDelay());
        result = await _repo.refresh(
          refreshToken: refreshTokenProvider?.call(),
        );
      }
      if (result case Ok(:final value)) {
        _persistRotated(value);
        _announce(value);
      }
      return result;
    });
  }

  Future<SharedAccessToken?> _askPeersForToken() async {
    final token = await _sync.askPeers();
    return token != null && _adoptable(token) ? token : null;
  }

  static bool _isSuperseded(Result<TokenResponse, AppFailure> r) =>
      r is Err<TokenResponse, AppFailure> &&
      r.failure.problem?.code == refreshSupersededCode;

  SharedAccessToken? _lastPeerToken;
  DateTime? _lastPeerTokenAt;

  SharedAccessToken? _peerTokenSince(DateTime since) {
    final token = _lastPeerToken;
    final at = _lastPeerTokenAt;
    if (token == null || at == null || at.isBefore(since)) return null;
    return _adoptable(token) ? token : null;
  }

  /// Access tokens the server has answered with a 401, newest last.
  final _rejected = <String>[];

  void _markRejected(String token) {
    _rejected
      ..remove(token)
      ..add(token);
    if (_rejected.length > 8) _rejected.removeAt(0);
  }

  bool _adoptable(SharedAccessToken t) =>
      !_rejected.contains(t.accessToken) &&
      t.expiresAt.difference(DateTime.now()) >= _minAdoptableLife;

  static TokenResponse _fromPeer(SharedAccessToken t) => TokenResponse(
    accessToken: t.accessToken,
    tokenType: 'Bearer',
    expiresIn: t.secondsLeft(DateTime.now()),
  );

  void _announce(TokenResponse tokens) => _sync.announceToken(
    SharedAccessToken(
      accessToken: tokens.accessToken,
      expiresAt: _expiresAt(tokens.expiresIn),
    ),
  );

  /// What this tab tells a newly opened one that asks for a token.
  SharedAccessToken? _shareableToken() {
    final s = state;
    if (s is! SessionAuthenticated) return null;
    final token = SharedAccessToken(
      accessToken: s.accessToken,
      expiresAt: s.expiresAt,
    );
    return _adoptable(token) ? token : null;
  }

  void _onPeerToken(_SessionPeerToken event, Emitter<SessionState> emit) {
    _lastPeerToken = event.token;
    _lastPeerTokenAt = DateTime.now();
    final s = state;
    // Mid-login states belong to this tab's own flow; leave them alone. A tab
    // sitting on the login screen is fine to sign in: every tab shares the
    // one cookie, so a reload would have signed it in anyway.
    if (s is SessionAuthenticating || s is SessionMfaRequired) return;
    if (!_adoptable(event.token)) return;
    if (s is SessionAuthenticated &&
        !event.token.expiresAt.isAfter(s.expiresAt)) {
      return;
    }
    _scheduleRefresh(_fromPeer(event.token).expiresIn);
    emit(
      SessionAuthenticated(
        accessToken: event.token.accessToken,
        expiresAt: event.token.expiresAt,
      ),
    );
  }

  void _onPeerSignedOut(
    _SessionPeerSignedOut event,
    Emitter<SessionState> emit,
  ) {
    final s = state;
    if (s is! SessionAuthenticated && s is! SessionRefreshing) return;
    _cancelTimer();
    onSessionEnded?.call();
    emit(const SessionUnauthenticated(reason: SessionEndReason.loggedOut));
  }

  void _onRefreshSucceeded(
    _SessionRefreshSucceeded event,
    Emitter<SessionState> emit,
  ) {
    _cancelRetry();
    _scheduleRefresh(event.tokens.expiresIn);
    emit(
      SessionAuthenticated(
        accessToken: event.tokens.accessToken,
        expiresAt: _expiresAt(event.tokens.expiresIn),
      ),
    );
  }

  void _onRefreshFailed(
    _SessionRefreshFailed event,
    Emitter<SessionState> emit,
  ) {
    final s = state;
    // No network yet (a device waking up), a server error or rate limiting
    // says nothing about the session: keep it and try again shortly. Only an
    // answer from the server that refuses the renewal ends it.
    // Settled some other way meanwhile (a peer's token, a sign-out): leave it.
    if (_isTransient(event.failure)) {
      if (s is SessionRefreshing) {
        _scheduleRetry();
        emit(
          SessionAuthenticated(
            accessToken: s.staleAccessToken,
            expiresAt: _heldExpiresAt ?? DateTime.now(),
          ),
        );
      }
      return;
    }
    _cancelTimer();
    onSessionEnded?.call();
    emit(
      const SessionUnauthenticated(reason: SessionEndReason.refreshFailed),
    );
  }

  Future<void> _onLogout(
    SessionLogoutRequested event,
    Emitter<SessionState> emit,
  ) async {
    _cancelTimer();
    if (event.callBackend) {
      await _repo.logout();
      // The cookie every tab shares is gone; tell them rather than letting
      // each discover it on its next refresh.
      _sync.announceSignedOut();
    }
    onSessionEnded?.call();
    emit(
      const SessionUnauthenticated(reason: SessionEndReason.loggedOut),
    );
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  DateTime _expiresAt(int expiresInSecs) =>
      DateTime.now().add(Duration(seconds: expiresInSecs));

  static bool _isTransient(AppFailure f) =>
      f is NetworkFailure || f is ServerFailure || f is RateLimitedFailure;

  void _scheduleRetry() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _retryTimer?.cancel();
    final i = math.min(_retryAttempt, _transientRetryDelays.length - 1);
    _retryAttempt++;
    _retryTimer = Timer(_transientRetryDelays[i], () {
      _retryTimer = null;
      add(const SessionRefreshRequested());
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
  }

  void _scheduleRefresh(int expiresInSecs) {
    _cancelTimer();
    final lead =
        Duration(seconds: expiresInSecs) - _refreshLeadTime - _refreshJitter();
    final delay = lead < _refreshMinDelay ? _refreshMinDelay : lead;
    _refreshTimer = Timer(delay, () => add(const SessionRefreshRequested()));
  }

  void _cancelTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _cancelRetry();
  }

  @override
  Future<void> close() async {
    _cancelTimer();
    await _syncSub.cancel();
    return super.close();
  }
}
