// Underscore-prefixed fields are clearer than `{required this._repo}` here;
// silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';

sealed class MfaVerifyState extends Equatable {
  const MfaVerifyState();
  @override
  List<Object?> get props => const [];
}

final class MfaIdle extends MfaVerifyState {
  const MfaIdle();
}

final class MfaSubmitting extends MfaVerifyState {
  const MfaSubmitting();
}

final class MfaSucceeded extends MfaVerifyState {
  const MfaSucceeded();
}

final class MfaFailed extends MfaVerifyState {
  const MfaFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class MfaVerifyCubit extends Cubit<MfaVerifyState> {
  MfaVerifyCubit({
    required AuthRepository repo,
    required SessionBloc session,
  }) : _repo = repo,
       _session = session,
       super(const MfaIdle());

  final AuthRepository _repo;
  final SessionBloc _session;

  Future<void> submit({
    required String mfaToken,
    required String method,
    required String code,
  }) async {
    emit(const MfaSubmitting());
    final res = await _repo.verifyMfa(
      mfaToken: mfaToken,
      method: method,
      code: code,
    );
    res.when(
      ok: (tokens) {
        _session.add(SessionEstablished(tokens));
        emit(const MfaSucceeded());
      },
      err: (f) => emit(MfaFailed(f)),
    );
  }
}
