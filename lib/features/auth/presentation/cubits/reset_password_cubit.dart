import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';

sealed class ResetPasswordState extends Equatable {
  const ResetPasswordState();
  @override
  List<Object?> get props => const [];
}

final class ResetPasswordIdle extends ResetPasswordState {
  const ResetPasswordIdle();
}

final class ResetPasswordSubmitting extends ResetPasswordState {
  const ResetPasswordSubmitting();
}

final class ResetPasswordSucceeded extends ResetPasswordState {
  const ResetPasswordSucceeded();
}

final class ResetPasswordFailed extends ResetPasswordState {
  const ResetPasswordFailed(this.failure);
  final AppFailure failure;

  @override
  List<Object?> get props => [failure];
}

class ResetPasswordCubit extends Cubit<ResetPasswordState> {
  ResetPasswordCubit(this._repo) : super(const ResetPasswordIdle());
  final AuthRepository _repo;

  Future<void> submit({
    required String token,
    required String newPassword,
  }) async {
    emit(const ResetPasswordSubmitting());
    final result = await _repo.confirmPasswordReset(
      token: token,
      newPassword: newPassword,
    );
    result.when(
      ok: (_) => emit(const ResetPasswordSucceeded()),
      err: (f) => emit(ResetPasswordFailed(f)),
    );
  }

  void reset() => emit(const ResetPasswordIdle());
}
