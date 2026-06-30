import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/presentation/cubits/forgot_password_cubit.dart';
import 'package:intellipilot/features/auth/presentation/cubits/register_cubit.dart';
import 'package:intellipilot/features/auth/presentation/cubits/reset_password_cubit.dart';

import '../../helpers/fake_auth_repository.dart';

void main() {
  group('ForgotPasswordCubit', () {
    late FakeAuthRepository repo;

    setUp(() => repo = FakeAuthRepository());

    blocTest<ForgotPasswordCubit, ForgotPasswordState>(
      'emits success with dev token when backend returns one',
      build: () {
        repo.requestResetHandler = (_) async =>
            const Ok<PasswordResetRequestResponse, AppFailure>(
              PasswordResetRequestResponse(
                status: 'ok',
                resetToken: 'dev-tok',
              ),
            );
        return ForgotPasswordCubit(repo);
      },
      act: (c) => c.submit('u@e.com'),
      expect: () => [
        isA<ForgotPasswordSubmitting>(),
        predicate<ForgotPasswordState>(
          (s) => s is ForgotPasswordSucceeded && s.devToken == 'dev-tok',
          'success with dev token',
        ),
      ],
    );

    blocTest<ForgotPasswordCubit, ForgotPasswordState>(
      'emits failure on transport failure',
      build: () {
        repo.requestResetHandler = (_) async =>
            const Err<PasswordResetRequestResponse, AppFailure>(
              NetworkFailure(),
            );
        return ForgotPasswordCubit(repo);
      },
      act: (c) => c.submit('u@e.com'),
      expect: () => [
        isA<ForgotPasswordSubmitting>(),
        isA<ForgotPasswordFailed>(),
      ],
    );
  });

  group('ResetPasswordCubit', () {
    late FakeAuthRepository repo;

    setUp(() => repo = FakeAuthRepository());

    blocTest<ResetPasswordCubit, ResetPasswordState>(
      'emits success on Ok',
      build: () => ResetPasswordCubit(repo),
      act: (c) => c.submit(token: 'tok', newPassword: 'pw12345678'),
      expect: () => [
        isA<ResetPasswordSubmitting>(),
        isA<ResetPasswordSucceeded>(),
      ],
    );

    blocTest<ResetPasswordCubit, ResetPasswordState>(
      'emits failure when repo returns Err',
      build: () {
        repo.confirmResetHandler = () async =>
            const Err<Unit, AppFailure>(NetworkFailure());
        return ResetPasswordCubit(repo);
      },
      act: (c) => c.submit(token: 'tok', newPassword: 'pw12345678'),
      expect: () => [
        isA<ResetPasswordSubmitting>(),
        isA<ResetPasswordFailed>(),
      ],
    );
  });

  group('RegisterCubit', () {
    late FakeAuthRepository repo;

    setUp(() => repo = FakeAuthRepository());

    blocTest<RegisterCubit, RegisterState>(
      'emits success on Ok',
      build: () {
        repo.registerHandler = () async =>
            const Ok<Unit, AppFailure>(Unit.instance);
        return RegisterCubit(repo);
      },
      act: (c) => c.submit(
        email: 'u@e.com',
        username: 'user1',
        password: 'pw12345678',
        fullName: '',
      ),
      expect: () => [isA<RegisterSubmitting>(), isA<RegisterSucceeded>()],
    );

    blocTest<RegisterCubit, RegisterState>(
      'emits failure with fieldErrors on ValidationFailure',
      build: () {
        repo.registerHandler = () async => const Err<Unit, AppFailure>(
          ValidationFailure(fieldErrors: []),
        );
        return RegisterCubit(repo);
      },
      act: (c) => c.submit(
        email: 'u@e.com',
        username: 'user1',
        password: 'weak',
        fullName: '',
      ),
      expect: () => [
        isA<RegisterSubmitting>(),
        isA<RegisterFailed>(),
      ],
    );
  });
}
