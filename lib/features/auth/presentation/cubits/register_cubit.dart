import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/problem.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';

sealed class RegisterState extends Equatable {
  const RegisterState();
  @override
  List<Object?> get props => const [];
}

final class RegisterIdle extends RegisterState {
  const RegisterIdle();
}

final class RegisterSubmitting extends RegisterState {
  const RegisterSubmitting();
}

final class RegisterSucceeded extends RegisterState {
  const RegisterSucceeded();
}

final class RegisterFailed extends RegisterState {
  const RegisterFailed({required this.failure, this.fieldErrors = const []});
  final AppFailure failure;
  final List<FieldError> fieldErrors;

  @override
  List<Object?> get props => [failure, fieldErrors];
}

class RegisterCubit extends Cubit<RegisterState> {
  RegisterCubit(this._repo) : super(const RegisterIdle());
  final AuthRepository _repo;

  Future<void> submit({
    required String email,
    required String username,
    required String password,
    required String fullName,
  }) async {
    emit(const RegisterSubmitting());
    final result = await _repo.register(
      email: email,
      username: username,
      password: password,
      fullName: fullName,
    );
    result.when(
      ok: (_) => emit(const RegisterSucceeded()),
      err: (f) => emit(
        RegisterFailed(
          failure: f,
          fieldErrors:
              (f is ValidationFailure) ? f.fieldErrors : const [],
        ),
      ),
    );
  }

  void reset() => emit(const RegisterIdle());
}
