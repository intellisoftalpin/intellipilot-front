// Underscore-prefixed fields are clearer than `{required this._repo}` here;
// silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';

sealed class PasskeySignInState extends Equatable {
  const PasskeySignInState();
  @override
  List<Object?> get props => const [];
}

final class PasskeySignInIdle extends PasskeySignInState {
  const PasskeySignInIdle();
}

final class PasskeySignInRunning extends PasskeySignInState {
  const PasskeySignInRunning();
}

final class PasskeySignInSucceeded extends PasskeySignInState {
  const PasskeySignInSucceeded();
}

final class PasskeySignInFailed extends PasskeySignInState {
  const PasskeySignInFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class PasskeySignInCubit extends Cubit<PasskeySignInState> {
  PasskeySignInCubit({
    required MfaRepository repo,
    required PasskeyService passkeys,
    required SessionBloc session,
  }) : _repo = repo,
       _passkeys = passkeys,
       _session = session,
       super(const PasskeySignInIdle());

  final MfaRepository _repo;
  final PasskeyService _passkeys;
  final SessionBloc _session;

  bool get isSupported => _passkeys.isSupported;

  Future<void> signIn(String email) async {
    if (!_passkeys.isSupported) {
      emit(const PasskeySignInFailed(UnknownFailure()));
      return;
    }
    emit(const PasskeySignInRunning());

    final start = await _repo.startPasskeyAuthentication(email);
    final fail = start.failureOrNull;
    if (fail != null) {
      emit(PasskeySignInFailed(fail));
      return;
    }
    final ceremony = start.valueOrNull!;

    Map<String, dynamic> credential;
    try {
      credential = await _passkeys.authenticate(ceremony.options);
    } on PasskeyCeremonyError catch (e) {
      emit(PasskeySignInFailed(UnknownFailure(cause: e)));
      return;
    }

    final finish = await _repo.finishPasskeyAuthentication(
      stateId: ceremony.stateId,
      credential: credential,
    );
    finish.when(
      ok: (tokens) {
        _session.add(SessionEstablished(tokens));
        emit(const PasskeySignInSucceeded());
      },
      err: (f) => emit(PasskeySignInFailed(f)),
    );
  }
}
