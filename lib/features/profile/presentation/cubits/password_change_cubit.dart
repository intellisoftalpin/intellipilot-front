// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';

sealed class PasswordChangeState extends Equatable {
  const PasswordChangeState();
  @override
  List<Object?> get props => const [];
}

final class PasswordChangeIdle extends PasswordChangeState {
  const PasswordChangeIdle();
}

final class PasswordChangeRunning extends PasswordChangeState {
  const PasswordChangeRunning();
}

final class PasswordChangeSucceeded extends PasswordChangeState {
  const PasswordChangeSucceeded();
}

final class PasswordChangeFailed extends PasswordChangeState {
  const PasswordChangeFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class PasswordChangeCubit extends Cubit<PasswordChangeState> {
  PasswordChangeCubit({
    required ProfileRepository repo,
    required SessionBloc session,
  }) : _repo = repo,
       _session = session,
       super(const PasswordChangeIdle());

  final ProfileRepository _repo;
  final SessionBloc _session;

  Future<void> submit({
    required String currentPassword,
    required String newPassword,
  }) async {
    emit(const PasswordChangeRunning());
    final res = await _repo.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    res.when(
      ok: (_) {
        // The backend revokes every session on success, but the in-memory
        // access token survives — push the session machine to Unauthenticated
        // so the router redirects to /login. callBackend:false because the
        // logout endpoint would now reject our just-revoked token.
        _session.add(const SessionLogoutRequested(callBackend: false));
        emit(const PasswordChangeSucceeded());
      },
      err: (f) => emit(PasswordChangeFailed(f)),
    );
  }
}
