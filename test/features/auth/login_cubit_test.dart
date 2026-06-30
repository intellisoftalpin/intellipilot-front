import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/presentation/cubits/login_cubit.dart';

import '../../helpers/fake_auth_repository.dart';

void main() {
  group('LoginCubit', () {
    late FakeAuthRepository repo;
    late SessionBloc session;

    setUp(() {
      repo = FakeAuthRepository();
      session = SessionBloc(repository: repo);
    });

    tearDown(() => session.close());

    LoginCubit make() => LoginCubit(repo: repo, session: session);

    blocTest<LoginCubit, LoginState>(
      'happy path: submits, dispatches SessionEstablished, emits LoginSucceeded',
      build: () {
        repo.loginHandler = (_, _) async => const Ok<LoginResult, AppFailure>(
          LoginTokens(
            TokenResponse(
              accessToken: 'a',
              tokenType: 'Bearer',
              expiresIn: 600,
            ),
          ),
        );
        return make();
      },
      act: (c) => c.submit(email: 'u@e.com', password: 'pw12345678'),
      expect: () => [isA<LoginSubmitting>(), isA<LoginSucceeded>()],
      verify: (_) async {
        // SessionBloc transitions to Authenticated after the event lands.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(session.state, isA<SessionAuthenticated>());
      },
    );

    blocTest<LoginCubit, LoginState>(
      'mfa branch: emits LoginMfaChallenged when backend asks for 2FA',
      build: () {
        repo.loginHandler = (_, _) async => const Ok<LoginResult, AppFailure>(
          LoginMfaRequired(mfaToken: 'mfa', methods: ['totp']),
        );
        return make();
      },
      act: (c) => c.submit(email: 'u@e.com', password: 'pw12345678'),
      expect: () => [isA<LoginSubmitting>(), isA<LoginMfaChallenged>()],
      verify: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(session.state, isA<SessionMfaRequired>());
      },
    );

    blocTest<LoginCubit, LoginState>(
      'failure path: emits LoginFailed with the failure',
      build: make,
      act: (c) => c.submit(email: 'u@e.com', password: 'wrong'),
      expect: () => [
        isA<LoginSubmitting>(),
        predicate<LoginState>(
          (s) => s is LoginFailed && s.failure is UnauthorizedFailure,
          'failed with UnauthorizedFailure',
        ),
      ],
    );

    blocTest<LoginCubit, LoginState>(
      'reset() goes back to LoginIdle',
      build: make,
      seed: () => const LoginFailed(failure: UnauthorizedFailure()),
      act: (c) => c.reset(),
      expect: () => [isA<LoginIdle>()],
    );
  });
}
