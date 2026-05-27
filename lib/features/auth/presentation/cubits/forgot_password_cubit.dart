import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';

sealed class ForgotPasswordState extends Equatable {
  const ForgotPasswordState();
  @override
  List<Object?> get props => const [];
}

final class ForgotPasswordIdle extends ForgotPasswordState {
  const ForgotPasswordIdle();
}

final class ForgotPasswordSubmitting extends ForgotPasswordState {
  const ForgotPasswordSubmitting();
}

final class ForgotPasswordSucceeded extends ForgotPasswordState {
  const ForgotPasswordSucceeded({this.devToken});

  /// Backend's dev-mode reset_token, surfaced inline so QA can copy it without
  /// a mailer. Always null in production.
  final String? devToken;

  @override
  List<Object?> get props => [devToken];
}

final class ForgotPasswordFailed extends ForgotPasswordState {
  const ForgotPasswordFailed(this.failure);
  final AppFailure failure;

  @override
  List<Object?> get props => [failure];
}

class ForgotPasswordCubit extends Cubit<ForgotPasswordState> {
  ForgotPasswordCubit(this._repo) : super(const ForgotPasswordIdle());
  final AuthRepository _repo;

  Future<void> submit(String email) async {
    emit(const ForgotPasswordSubmitting());
    final result = await _repo.requestPasswordReset(email);
    result.when(
      ok: (res) => emit(ForgotPasswordSucceeded(devToken: res.resetToken)),
      err: (f) => emit(ForgotPasswordFailed(f)),
    );
  }

  void reset() => emit(const ForgotPasswordIdle());
}
