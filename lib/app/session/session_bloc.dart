import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Phase-1 skeleton. Phase 2 will introduce the full state machine
/// (Authenticating → MfaRequired → Authenticated → Refreshing, etc.).
///
/// The interceptor pipeline already pulls the access token via
/// [SessionBloc.currentAccessToken] so Phase 2 can plug it in without
/// touching the network layer.
sealed class SessionState extends Equatable {
  const SessionState();

  @override
  List<Object?> get props => const [];
}

final class SessionUnknown extends SessionState {
  const SessionUnknown();
}

final class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

final class SessionAuthenticated extends SessionState {
  const SessionAuthenticated({required this.accessToken});
  final String accessToken;

  @override
  List<Object?> get props => [accessToken];
}

sealed class SessionEvent extends Equatable {
  const SessionEvent();
  @override
  List<Object?> get props => const [];
}

final class SessionRestored extends SessionEvent {
  const SessionRestored();
}

final class SessionLoggedOut extends SessionEvent {
  const SessionLoggedOut();
}

class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc() : super(const SessionUnknown()) {
    on<SessionRestored>((event, emit) {
      // No persisted session yet — Phase 2 will add refresh-token-driven
      // restoration. For now we settle into unauthenticated.
      emit(const SessionUnauthenticated());
    });
    on<SessionLoggedOut>((event, emit) {
      emit(const SessionUnauthenticated());
    });
  }

  /// Access token provider for the [AuthInterceptor]. Null while
  /// unauthenticated. Phase 2 will wire real tokens through here.
  String? get currentAccessToken {
    final s = state;
    if (s is SessionAuthenticated) return s.accessToken;
    return null;
  }
}
