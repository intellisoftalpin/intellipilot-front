import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/network/interceptors/refresh_interceptor.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';

/// Time before access-token expiry to attempt refresh proactively.
const _refreshLeadTime = Duration(seconds: 30);

/// Minimum delay until refresh — guards against an immediately-expiring token
/// looping the refresh timer.
const _refreshMinDelay = Duration(seconds: 5);

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
  const _SessionRefreshFailed();
}

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
  }) : _repo = repository,
       super(const SessionUnknown()) {
    on<SessionStartupRequested>(_onStartup);
    on<SessionMfaChallenged>(_onMfaChallenged);
    on<SessionEstablished>(_onEstablished);
    on<SessionRefreshRequested>(_onRefresh);
    on<_SessionRefreshSucceeded>(_onRefreshSucceeded);
    on<_SessionRefreshFailed>(_onRefreshFailed);
    on<SessionLogoutRequested>(_onLogout);
  }

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

  /// Hook the [RefreshInterceptor] calls on 401.
  Future<RefreshOutcome> refreshHook() async {
    add(const SessionRefreshRequested());
    // Wait until we leave the Refreshing state.
    final next = await stream.firstWhere(
      (s) => s is! SessionRefreshing && s is! SessionUnknown,
    );
    return next is SessionAuthenticated
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
    final result = await _repo.refresh(
      refreshToken: refreshTokenProvider?.call(),
    );
    result.when(
      ok: (tokens) {
        _persistRotated(tokens);
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
    onSessionEstablished?.call(event.tokens);
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
    final current = state;
    if (current is! SessionAuthenticated && current is! SessionRefreshing) {
      return;
    }
    final stale = current is SessionAuthenticated
        ? current.accessToken
        : (current as SessionRefreshing).staleAccessToken;
    emit(SessionRefreshing(staleAccessToken: stale));

    final result = await _repo.refresh(
      refreshToken: refreshTokenProvider?.call(),
    );
    result.when(
      ok: (tokens) {
        _persistRotated(tokens);
        add(_SessionRefreshSucceeded(tokens));
      },
      err: (_) => add(const _SessionRefreshFailed()),
    );
  }

  void _onRefreshSucceeded(
    _SessionRefreshSucceeded event,
    Emitter<SessionState> emit,
  ) {
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

  void _scheduleRefresh(int expiresInSecs) {
    _cancelTimer();
    final lead = Duration(seconds: expiresInSecs) - _refreshLeadTime;
    final delay = lead < _refreshMinDelay ? _refreshMinDelay : lead;
    _refreshTimer = Timer(delay, () => add(const SessionRefreshRequested()));
  }

  void _cancelTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  Future<void> close() {
    _cancelTimer();
    return super.close();
  }
}
