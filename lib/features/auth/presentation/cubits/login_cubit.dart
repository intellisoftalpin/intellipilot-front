// Underscore-prefixed fields are clearer than `{required this._repo}` named
// parameters in the public constructor — disable the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/problem.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';

sealed class LoginState extends Equatable {
  const LoginState();
  @override
  List<Object?> get props => const [];
}

final class LoginIdle extends LoginState {
  const LoginIdle();
}

final class LoginSubmitting extends LoginState {
  const LoginSubmitting();
}

/// Backend returned an MFA challenge. Phase 3 wires the verify UI; for Phase
/// 2 we surface this so the form can show a "MFA required" notice.
final class LoginMfaChallenged extends LoginState {
  const LoginMfaChallenged({required this.mfaToken, required this.methods});
  final String mfaToken;
  final List<String> methods;

  @override
  List<Object?> get props => [mfaToken, methods];
}

/// Terminal success — [SessionEstablished] has already been dispatched to
/// [SessionBloc]; the router will redirect on the next frame.
final class LoginSucceeded extends LoginState {
  const LoginSucceeded();
}

final class LoginFailed extends LoginState {
  const LoginFailed({required this.failure, this.fieldErrors = const []});
  final AppFailure failure;
  final List<FieldError> fieldErrors;

  @override
  List<Object?> get props => [failure, fieldErrors];
}

class LoginCubit extends Cubit<LoginState> {
  LoginCubit({required AuthRepository repo, required SessionBloc session})
    : _repo = repo,
      _session = session,
      super(const LoginIdle());

  final AuthRepository _repo;
  final SessionBloc _session;

  Future<void> submit({required String email, required String password}) async {
    emit(const LoginSubmitting());
    final result = await _repo.login(email: email, password: password);
    result.when(
      ok: (login) {
        switch (login) {
          case LoginTokens(:final tokens):
            _session.add(SessionEstablished(tokens));
            emit(const LoginSucceeded());
          case LoginMfaRequired(:final mfaToken, :final methods):
            _session.add(
              SessionMfaChallenged(mfaToken: mfaToken, methods: methods),
            );
            emit(LoginMfaChallenged(mfaToken: mfaToken, methods: methods));
        }
      },
      err: (f) => emit(
        LoginFailed(
          failure: f,
          fieldErrors: (f is ValidationFailure) ? f.fieldErrors : const [],
        ),
      ),
    );
  }

  void reset() => emit(const LoginIdle());
}
