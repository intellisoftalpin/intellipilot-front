import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/mfa/data/dtos/mfa_dtos.dart';
import 'package:intellipilot/features/mfa/presentation/cubits/mfa_verify_cubit.dart';
import 'package:intellipilot/features/mfa/presentation/cubits/passkey_signin_cubit.dart';
import 'package:intellipilot/features/mfa/presentation/cubits/passkeys_cubit.dart';
import 'package:intellipilot/features/mfa/presentation/cubits/recovery_codes_cubit.dart';
import 'package:intellipilot/features/mfa/presentation/cubits/totp_setup_cubit.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_mfa_repository.dart';

void main() {
  group('TotpSetupCubit', () {
    late FakeMfaRepository repo;
    setUp(() => repo = FakeMfaRepository());

    blocTest<TotpSetupCubit, TotpSetupState>(
      'start() emits Starting then AwaitingCode on success',
      build: () {
        repo.startTotpHandler = () async => const Ok<TotpStartResponse, AppFailure>(
          TotpStartResponse(
            secretBase32: 'ABCDEF',
            provisioningUri: 'otpauth://totp/...',
            qrPngBase64: 'iVBORw0KGgo=',
          ),
        );
        return TotpSetupCubit(repo);
      },
      act: (c) => c.start(),
      expect: () => [isA<TotpStarting>(), isA<TotpAwaitingCode>()],
    );

    blocTest<TotpSetupCubit, TotpSetupState>(
      'confirm() success emits Confirming then Enabled',
      build: () {
        repo.confirmTotpHandler =
            (_) async => const Ok<RecoveryCodesResponse, AppFailure>(
              RecoveryCodesResponse(codes: ['aaa', 'bbb', 'ccc']),
            );
        return TotpSetupCubit(repo);
      },
      seed: () => const TotpAwaitingCode(
        TotpStartResponse(
          secretBase32: 'ABCDEF',
          provisioningUri: 'otpauth://totp/...',
          qrPngBase64: 'iVBORw0KGgo=',
        ),
      ),
      act: (c) => c.confirm('123456'),
      expect: () => [isA<TotpConfirming>(), isA<TotpEnabled>()],
    );

    blocTest<TotpSetupCubit, TotpSetupState>(
      'confirm() failure stays Failed with the original start data',
      build: () {
        repo.confirmTotpHandler = (_) async =>
            const Err<RecoveryCodesResponse, AppFailure>(
              ValidationFailure(fieldErrors: []),
            );
        return TotpSetupCubit(repo);
      },
      seed: () => const TotpAwaitingCode(
        TotpStartResponse(
          secretBase32: 'ABCDEF',
          provisioningUri: 'otpauth://totp/...',
          qrPngBase64: 'iVBORw0KGgo=',
        ),
      ),
      act: (c) => c.confirm('000000'),
      expect: () => [
        isA<TotpConfirming>(),
        predicate<TotpSetupState>(
          (s) => s is TotpFailed && s.start != null,
          'failed with start data preserved',
        ),
      ],
    );
  });

  group('RecoveryCodesCubit', () {
    late FakeMfaRepository repo;
    setUp(() => repo = FakeMfaRepository());

    blocTest<RecoveryCodesCubit, RecoveryCodesState>(
      'regenerate() success emits Revealed',
      build: () {
        repo.regenerateHandler =
            () async => const Ok<RecoveryCodesResponse, AppFailure>(
              RecoveryCodesResponse(codes: ['x', 'y']),
            );
        return RecoveryCodesCubit(repo);
      },
      act: (c) => c.regenerate(),
      expect: () => [isA<RecoveryRegenerating>(), isA<RecoveryRevealed>()],
    );

    blocTest<RecoveryCodesCubit, RecoveryCodesState>(
      'regenerate() failure emits Failed',
      build: () {
        repo.regenerateHandler =
            () async => const Err<RecoveryCodesResponse, AppFailure>(
              ConflictFailure(),
            );
        return RecoveryCodesCubit(repo);
      },
      act: (c) => c.regenerate(),
      expect: () => [isA<RecoveryRegenerating>(), isA<RecoveryFailed>()],
    );
  });

  group('MfaVerifyCubit', () {
    late FakeAuthRepository auth;
    late SessionBloc session;

    setUp(() {
      auth = FakeAuthRepository();
      session = SessionBloc(repository: auth);
    });
    tearDown(() => session.close());

    blocTest<MfaVerifyCubit, MfaVerifyState>(
      'success dispatches SessionEstablished and emits Succeeded',
      build: () {
        auth.verifyMfaHandler = () async =>
            const Ok<TokenResponse, AppFailure>(
              TokenResponse(
                accessToken: 't',
                tokenType: 'Bearer',
                expiresIn: 600,
              ),
            );
        return MfaVerifyCubit(repo: auth, session: session);
      },
      act: (c) => c.submit(mfaToken: 'mfa', method: 'totp', code: '123456'),
      expect: () => [isA<MfaSubmitting>(), isA<MfaSucceeded>()],
      verify: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(session.state, isA<SessionAuthenticated>());
      },
    );

    blocTest<MfaVerifyCubit, MfaVerifyState>(
      'failure emits Failed',
      build: () => MfaVerifyCubit(repo: auth, session: session),
      act: (c) => c.submit(mfaToken: 'mfa', method: 'totp', code: '000000'),
      expect: () => [
        isA<MfaSubmitting>(),
        predicate<MfaVerifyState>(
          (s) => s is MfaFailed && s.failure is UnauthorizedFailure,
          'failed with unauthorized',
        ),
      ],
    );
  });

  group('PasskeysCubit', () {
    late FakeMfaRepository repo;
    late StubPasskeyService passkeys;
    setUp(() {
      repo = FakeMfaRepository();
      passkeys = StubPasskeyService();
    });

    blocTest<PasskeysCubit, PasskeysState>(
      'load() returns Loaded list',
      build: () {
        repo.listPasskeysHandler = () async =>
            Ok<List<PasskeyListItem>, AppFailure>([
              PasskeyListItem(
                id: 'p1',
                nickname: 'Mac',
                createdAt: DateTime(2026, 5, 27),
              ),
            ]);
        return PasskeysCubit(repo: repo, passkeys: passkeys);
      },
      act: (c) => c.load(),
      expect: () => [isA<PasskeysLoading>(), isA<PasskeysLoaded>()],
    );

    blocTest<PasskeysCubit, PasskeysState>(
      'add() runs the ceremony, calls finish, then reloads',
      build: () {
        repo.startPasskeyRegHandler = () async =>
            const Ok<PasskeyCeremony, AppFailure>(
              PasskeyCeremony(
                stateId: 's1',
                options: {'rp': {'name': 'r'}},
              ),
            );
        repo.listPasskeysHandler = () async =>
            Ok<List<PasskeyListItem>, AppFailure>([
              PasskeyListItem(
                id: 'p1',
                nickname: 'X',
                createdAt: DateTime(2026, 5, 27),
              ),
            ]);
        return PasskeysCubit(repo: repo, passkeys: passkeys);
      },
      seed: () => const PasskeysLoaded(items: []),
      act: (c) => c.add(nickname: 'X'),
      verify: (c) {
        expect(c.state, isA<PasskeysLoaded>());
        expect((c.state as PasskeysLoaded).items.length, 1);
      },
    );

    blocTest<PasskeysCubit, PasskeysState>(
      'add() records lastError when start fails',
      build: () {
        repo.startPasskeyRegHandler = () async =>
            const Err<PasskeyCeremony, AppFailure>(NetworkFailure());
        return PasskeysCubit(repo: repo, passkeys: passkeys);
      },
      seed: () => const PasskeysLoaded(items: []),
      act: (c) => c.add(),
      verify: (c) {
        expect(c.state, isA<PasskeysLoaded>());
        expect((c.state as PasskeysLoaded).lastError, isA<NetworkFailure>());
      },
    );

    blocTest<PasskeysCubit, PasskeysState>(
      'add() records lastError when ceremony throws',
      build: () {
        repo.startPasskeyRegHandler = () async =>
            const Ok<PasskeyCeremony, AppFailure>(
              PasskeyCeremony(stateId: 's', options: {}),
            );
        passkeys.throwOnRegister = true;
        return PasskeysCubit(repo: repo, passkeys: passkeys);
      },
      seed: () => const PasskeysLoaded(items: []),
      act: (c) => c.add(),
      verify: (c) {
        expect(c.state, isA<PasskeysLoaded>());
        expect((c.state as PasskeysLoaded).lastError, isNotNull);
      },
    );

    blocTest<PasskeysCubit, PasskeysState>(
      'add() is a no-op when service not supported',
      build: () {
        passkeys.supported = false;
        return PasskeysCubit(repo: repo, passkeys: passkeys);
      },
      seed: () => const PasskeysLoaded(items: []),
      act: (c) => c.add(),
      verify: (c) {
        expect((c.state as PasskeysLoaded).lastError, isNotNull);
      },
    );

    blocTest<PasskeysCubit, PasskeysState>(
      'remove() reloads list on success',
      build: () {
        repo.listPasskeysHandler = () async =>
            const Ok<List<PasskeyListItem>, AppFailure>([]);
        return PasskeysCubit(repo: repo, passkeys: passkeys);
      },
      seed: () => PasskeysLoaded(
        items: [
          PasskeyListItem(
            id: 'p1',
            nickname: 'X',
            createdAt: DateTime(2026),
          ),
        ],
      ),
      act: (c) => c.remove('p1'),
      verify: (c) {
        expect((c.state as PasskeysLoaded).items, isEmpty);
      },
    );

    blocTest<PasskeysCubit, PasskeysState>(
      'remove() records error on failure',
      build: () {
        repo.deletePasskeyHandler =
            (_) async => const Err<Unit, AppFailure>(NotFoundFailure());
        return PasskeysCubit(repo: repo, passkeys: passkeys);
      },
      seed: () => PasskeysLoaded(
        items: [
          PasskeyListItem(
            id: 'p1',
            nickname: 'X',
            createdAt: DateTime(2026),
          ),
        ],
      ),
      act: (c) => c.remove('p1'),
      verify: (c) {
        expect((c.state as PasskeysLoaded).lastError, isA<NotFoundFailure>());
      },
    );

    blocTest<PasskeysCubit, PasskeysState>(
      'load() emits LoadFailed on transport failure',
      build: () {
        repo.listPasskeysHandler = () async =>
            const Err<List<PasskeyListItem>, AppFailure>(NetworkFailure());
        return PasskeysCubit(repo: repo, passkeys: passkeys);
      },
      act: (c) => c.load(),
      expect: () => [isA<PasskeysLoading>(), isA<PasskeysLoadFailed>()],
    );
  });

  group('PasskeySignInCubit', () {
    late FakeMfaRepository repo;
    late FakeAuthRepository auth;
    late SessionBloc session;
    late StubPasskeyService passkeys;

    setUp(() {
      repo = FakeMfaRepository();
      auth = FakeAuthRepository();
      session = SessionBloc(repository: auth);
      passkeys = StubPasskeyService();
    });
    tearDown(() => session.close());

    blocTest<PasskeySignInCubit, PasskeySignInState>(
      'happy path dispatches SessionEstablished',
      build: () {
        repo.startPasskeyAuthHandler = (_) async =>
            const Ok<PasskeyCeremony, AppFailure>(
              PasskeyCeremony(stateId: 's', options: {}),
            );
        repo.finishPasskeyAuthHandler = () async =>
            const Ok<TokenResponse, AppFailure>(
              TokenResponse(
                accessToken: 't',
                tokenType: 'Bearer',
                expiresIn: 600,
              ),
            );
        return PasskeySignInCubit(
          repo: repo,
          passkeys: passkeys,
          session: session,
        );
      },
      act: (c) => c.signIn('u@e.com'),
      expect: () => [isA<PasskeySignInRunning>(), isA<PasskeySignInSucceeded>()],
      verify: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(session.state, isA<SessionAuthenticated>());
      },
    );

    blocTest<PasskeySignInCubit, PasskeySignInState>(
      'failure when service is not supported',
      build: () {
        passkeys.supported = false;
        return PasskeySignInCubit(
          repo: repo,
          passkeys: passkeys,
          session: session,
        );
      },
      act: (c) => c.signIn('u@e.com'),
      expect: () => [isA<PasskeySignInFailed>()],
    );

    blocTest<PasskeySignInCubit, PasskeySignInState>(
      'failure when start endpoint returns 401',
      build: () => PasskeySignInCubit(
        repo: repo,
        passkeys: passkeys,
        session: session,
      ),
      act: (c) => c.signIn('u@e.com'),
      expect: () => [isA<PasskeySignInRunning>(), isA<PasskeySignInFailed>()],
    );

    blocTest<PasskeySignInCubit, PasskeySignInState>(
      'failure when finish endpoint returns 401',
      build: () {
        repo.startPasskeyAuthHandler = (_) async =>
            const Ok<PasskeyCeremony, AppFailure>(
              PasskeyCeremony(stateId: 's', options: {}),
            );
        // finishPasskeyAuthHandler defaults to UnauthorizedFailure.
        return PasskeySignInCubit(
          repo: repo,
          passkeys: passkeys,
          session: session,
        );
      },
      act: (c) => c.signIn('u@e.com'),
      verify: (c) {
        expect(c.state, isA<PasskeySignInFailed>());
      },
    );

    blocTest<PasskeySignInCubit, PasskeySignInState>(
      'failure when browser ceremony throws',
      build: () {
        repo.startPasskeyAuthHandler = (_) async =>
            const Ok<PasskeyCeremony, AppFailure>(
              PasskeyCeremony(stateId: 's', options: {}),
            );
        passkeys.throwOnAuth = true;
        return PasskeySignInCubit(
          repo: repo,
          passkeys: passkeys,
          session: session,
        );
      },
      act: (c) => c.signIn('u@e.com'),
      verify: (c) {
        expect(c.state, isA<PasskeySignInFailed>());
      },
    );
  });
}
