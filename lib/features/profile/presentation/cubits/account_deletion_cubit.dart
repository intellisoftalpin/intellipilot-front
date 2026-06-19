// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';

sealed class AccountDeletionState extends Equatable {
  const AccountDeletionState();
  @override
  List<Object?> get props => const [];
}

final class AccountDeletionIdle extends AccountDeletionState {
  const AccountDeletionIdle();
}

final class AccountDeletionRunning extends AccountDeletionState {
  const AccountDeletionRunning();
}

final class AccountDeletionScheduled extends AccountDeletionState {
  const AccountDeletionScheduled(this.graceUntil);
  final DateTime graceUntil;
  @override
  List<Object?> get props => [graceUntil];
}

final class AccountDeletionFailed extends AccountDeletionState {
  const AccountDeletionFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class AccountDeletionCubit extends Cubit<AccountDeletionState> {
  AccountDeletionCubit({
    required ProfileRepository repo,
    required SessionBloc session,
  }) : _repo = repo,
       _session = session,
       super(const AccountDeletionIdle());

  final ProfileRepository _repo;
  final SessionBloc _session;

  /// [typedConfirmation] is the user's free-text input from the confirm modal;
  /// it must match [expectedUsername] exactly or the call is refused locally.
  /// The backend has no such requirement, but we treat deletion as
  /// destructive and require an in-form confirmation as a safety guard.
  Future<void> deleteAccount({
    required String typedConfirmation,
    required String expectedUsername,
  }) async {
    if (typedConfirmation.trim() != expectedUsername) {
      emit(const AccountDeletionFailed(ValidationFailure(fieldErrors: [])));
      return;
    }
    emit(const AccountDeletionRunning());

    final res = await _repo.deleteAccount();
    res.when(
      ok: (r) {
        // Backend revokes our sessions on success, but the access token in
        // memory survives — push the session machine to Unauthenticated so
        // the router redirects to /login.
        _session.add(const SessionLogoutRequested(callBackend: false));
        emit(AccountDeletionScheduled(r.graceUntil));
      },
      err: (f) => emit(AccountDeletionFailed(f)),
    );
  }
}
