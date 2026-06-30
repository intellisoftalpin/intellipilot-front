import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';

import '../../helpers/fake_auth_repository.dart';

void main() {
  group('SessionBloc', () {
    late FakeAuthRepository repo;

    setUp(() {
      repo = FakeAuthRepository();
    });

    SessionBloc make() => SessionBloc(repository: repo);

    test('starts in SessionUnknown', () {
      expect(make().state, const SessionUnknown());
    });

    blocTest<SessionBloc, SessionState>(
      'SessionStartupRequested with no session -> Unauthenticated(startup)',
      build: make,
      act: (b) => b.add(const SessionStartupRequested()),
      expect: () => [
        const SessionUnauthenticated(reason: SessionEndReason.startup),
      ],
    );

    blocTest<SessionBloc, SessionState>(
      'SessionStartupRequested with valid cookie -> Authenticated',
      build: () {
        repo.refreshHandler = () async => const Ok<TokenResponse, AppFailure>(
          TokenResponse(
            accessToken: 'access-xyz',
            tokenType: 'Bearer',
            expiresIn: 600,
          ),
        );
        return make();
      },
      act: (b) => b.add(const SessionStartupRequested()),
      wait: const Duration(milliseconds: 10),
      verify: (b) {
        expect(b.state, isA<SessionAuthenticated>());
        expect(
          (b.state as SessionAuthenticated).accessToken,
          'access-xyz',
        );
      },
    );

    blocTest<SessionBloc, SessionState>(
      'SessionEstablished -> Authenticated and exposes currentAccessToken',
      build: make,
      act: (b) => b.add(
        const SessionEstablished(
          TokenResponse(
            accessToken: 'tok-1',
            tokenType: 'Bearer',
            expiresIn: 600,
          ),
        ),
      ),
      verify: (b) {
        expect(b.state, isA<SessionAuthenticated>());
        expect(b.currentAccessToken, 'tok-1');
      },
    );

    blocTest<SessionBloc, SessionState>(
      'SessionLogoutRequested -> Unauthenticated(loggedOut), calls backend',
      build: make,
      seed: () => SessionAuthenticated(
        accessToken: 't',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      ),
      act: (b) => b.add(const SessionLogoutRequested()),
      expect: () => [
        const SessionUnauthenticated(reason: SessionEndReason.loggedOut),
      ],
      verify: (_) {
        expect(repo.logoutCalls, 1);
      },
    );

    blocTest<SessionBloc, SessionState>(
      'SessionLogoutRequested(callBackend: false) skips repo.logout',
      build: make,
      seed: () => SessionAuthenticated(
        accessToken: 't',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      ),
      act: (b) => b.add(const SessionLogoutRequested(callBackend: false)),
      verify: (_) {
        expect(repo.logoutCalls, 0);
      },
    );

    blocTest<SessionBloc, SessionState>(
      'SessionRefreshRequested success -> Refreshing then Authenticated',
      build: () {
        repo.refreshHandler = () async => const Ok<TokenResponse, AppFailure>(
          TokenResponse(
            accessToken: 'tok-rotated',
            tokenType: 'Bearer',
            expiresIn: 600,
          ),
        );
        return make();
      },
      seed: () => SessionAuthenticated(
        accessToken: 'tok-old',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      ),
      act: (b) => b.add(const SessionRefreshRequested()),
      wait: const Duration(milliseconds: 10),
      verify: (b) {
        expect(b.state, isA<SessionAuthenticated>());
        expect(b.currentAccessToken, 'tok-rotated');
      },
    );

    blocTest<SessionBloc, SessionState>(
      'SessionRefreshRequested failure -> Unauthenticated(refreshFailed)',
      build: () {
        repo.refreshHandler = () async => const Err<TokenResponse, AppFailure>(
          UnauthorizedFailure(),
        );
        return make();
      },
      seed: () => SessionAuthenticated(
        accessToken: 'tok-stale',
        expiresAt: DateTime.now().add(const Duration(seconds: 5)),
      ),
      act: (b) => b.add(const SessionRefreshRequested()),
      wait: const Duration(milliseconds: 10),
      verify: (b) {
        expect(
          b.state,
          const SessionUnauthenticated(
            reason: SessionEndReason.refreshFailed,
          ),
        );
      },
    );

    test(
      'SessionRefreshing exposes the stale access token via state.props',
      () {
        const s = SessionRefreshing(staleAccessToken: 'stale-1');
        expect(s.staleAccessToken, 'stale-1');
        expect(s.props, const ['stale-1']);
      },
    );

    test('currentAccessToken is null while unauthenticated', () {
      expect(make().currentAccessToken, isNull);
    });
  });
}
