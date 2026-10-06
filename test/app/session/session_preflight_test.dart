import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/interceptors/refresh_interceptor.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';

import '../../helpers/fake_auth_repository.dart';

TokenResponse _tokens(String access) =>
    TokenResponse(accessToken: access, tokenType: 'Bearer', expiresIn: 900);

SessionBloc _bloc(FakeAuthRepository repo, {void Function()? onEnded}) =>
    SessionBloc(
      repository: repo,
      onSessionEnded: onEnded,
      supersededRetryDelay: () => Duration.zero,
      refreshJitter: () => Duration.zero,
    );

SessionAuthenticated _authed(String token, {required Duration life}) =>
    SessionAuthenticated(
      accessToken: token,
      expiresAt: DateTime.now().add(life),
    );

void main() {
  group('freshAccessToken', () {
    test('hands out a live token without refreshing', () async {
      final repo = FakeAuthRepository();
      final bloc = _bloc(repo)
        ..emit(_authed('live', life: const Duration(minutes: 10)));

      expect(await bloc.freshAccessToken(), 'live');
      expect(repo.refreshCalls, 0);
      await bloc.close();
    });

    test('renews an expired token before handing it out', () async {
      final repo = FakeAuthRepository(
        refreshHandler: () async => Ok(_tokens('new')),
      );
      final bloc = _bloc(repo)
        ..emit(_authed('old', life: const Duration(seconds: -30)));

      expect(await bloc.freshAccessToken(), 'new');
      expect(repo.refreshCalls, 1);
      await bloc.close();
    });

    test('a burst of requests on an expired token renews once', () async {
      final gate = Completer<Result<TokenResponse, AppFailure>>();
      final repo = FakeAuthRepository(refreshHandler: () => gate.future);
      final bloc = _bloc(repo)
        ..emit(_authed('old', life: const Duration(seconds: -30)));

      final tokens = Future.wait([
        for (var i = 0; i < 5; i++) bloc.freshAccessToken(),
      ]);
      await Future<void>.delayed(Duration.zero);
      gate.complete(Ok(_tokens('new')));

      expect(await tokens, List.filled(5, 'new'));
      expect(repo.refreshCalls, 1);
      await bloc.close();
    });

    test(
      'waits for a renewal already running instead of the stale token',
      () async {
        final gate = Completer<Result<TokenResponse, AppFailure>>();
        final repo = FakeAuthRepository(refreshHandler: () => gate.future);
        final bloc = _bloc(repo)
          ..emit(_authed('old', life: const Duration(minutes: 1)))
          // The proactive timer fires.
          ..add(const SessionRefreshRequested());
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state, isA<SessionRefreshing>());

        final token = bloc.freshAccessToken();
        gate.complete(Ok(_tokens('new')));

        expect(await token, 'new');
        expect(repo.refreshCalls, 1);
        await bloc.close();
      },
    );

    test('a stuck renewal releases the request after maxWait', () async {
      final repo = FakeAuthRepository(
        refreshHandler: () =>
            Completer<Result<TokenResponse, AppFailure>>().future,
      );
      final bloc = _bloc(repo)
        ..emit(_authed('old', life: const Duration(seconds: -30)));

      final token = await bloc.freshAccessToken(
        maxWait: const Duration(milliseconds: 20),
      );

      expect(token, 'old', reason: 'the 401 path takes over from here');
    });

    test('signed out: no token, no waiting', () async {
      final repo = FakeAuthRepository();
      final bloc = _bloc(repo)..emit(const SessionUnauthenticated());

      expect(await bloc.freshAccessToken(), isNull);
      expect(repo.refreshCalls, 0);
      await bloc.close();
    });
  });

  group('renewIfStale (app back in the foreground)', () {
    test('renews a token about to expire', () async {
      final repo = FakeAuthRepository(
        refreshHandler: () async => Ok(_tokens('new')),
      );
      final bloc = _bloc(repo)
        ..emit(_authed('old', life: const Duration(seconds: 5)))
        ..renewIfStale();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repo.refreshCalls, 1);
      expect(bloc.currentAccessToken, 'new');
      await bloc.close();
    });

    test('leaves a token with life in it alone', () async {
      final repo = FakeAuthRepository();
      final bloc = _bloc(repo)
        ..emit(_authed('live', life: const Duration(minutes: 10)))
        ..renewIfStale();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repo.refreshCalls, 0);
      await bloc.close();
    });
  });

  group('a renewal that fails without an answer from the server', () {
    for (final (name, failure) in [
      ('no network', const NetworkFailure()),
      ('a server error', const ServerFailure()),
      ('rate limiting', const RateLimitedFailure()),
    ]) {
      test('keeps the session on $name', () async {
        var ended = 0;
        final repo = FakeAuthRepository(
          refreshHandler: () async => Err(failure),
        );
        final bloc = _bloc(repo, onEnded: () => ended++)
          ..emit(_authed('old', life: const Duration(seconds: -30)));

        final outcome = await bloc.refreshHook();

        expect(bloc.state, isA<SessionAuthenticated>());
        expect(bloc.currentAccessToken, 'old');
        expect(ended, 0, reason: 'per-user caches must survive');
        expect(
          outcome,
          RefreshOutcome.failed,
          reason: 'retrying with the refused token would only 401 again',
        );
        await bloc.close();
      });
    }

    test('requests do not hammer the server while it backs off', () async {
      final repo = FakeAuthRepository(
        refreshHandler: () async => const Err(NetworkFailure()),
      );
      final bloc = _bloc(repo)
        ..emit(_authed('old', life: const Duration(seconds: -30)));
      await bloc.freshAccessToken();
      expect(repo.refreshCalls, 1);

      expect(await bloc.freshAccessToken(), 'old');
      expect(await bloc.freshAccessToken(), 'old');
      expect(repo.refreshCalls, 1);
      await bloc.close();
    });

    test('recovers once the network is back', () async {
      Result<TokenResponse, AppFailure> answer = const Err(NetworkFailure());
      final repo = FakeAuthRepository(refreshHandler: () async => answer);
      final bloc = _bloc(repo)
        ..emit(_authed('old', life: const Duration(seconds: -30)));
      await bloc.freshAccessToken();

      answer = Ok(_tokens('new'));
      // Coming back to the foreground retries straight away.
      bloc.renewIfStale();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bloc.currentAccessToken, 'new');
      await bloc.close();
    });

    test('a refusal from the server still signs out', () async {
      final repo = FakeAuthRepository(
        refreshHandler: () async => const Err(UnauthorizedFailure()),
      );
      final bloc = _bloc(repo)
        ..emit(_authed('old', life: const Duration(seconds: -30)));

      await bloc.freshAccessToken();

      expect(
        bloc.state,
        const SessionUnauthenticated(reason: SessionEndReason.refreshFailed),
      );
      await bloc.close();
    });
  });

  group('routingChanges', () {
    test('a token renewal is not a routing change', () async {
      final repo = FakeAuthRepository(
        refreshHandler: () async => Ok(_tokens('new')),
      );
      final bloc = _bloc(repo)..add(SessionEstablished(_tokens('first')));
      final changes = <Object>[];
      final sub = bloc.routingChanges.listen(changes.add);
      await Future<void>.delayed(Duration.zero);
      expect(changes, hasLength(1));

      bloc.add(const SessionRefreshRequested());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.currentAccessToken, 'new');
      expect(changes, hasLength(1));

      await sub.cancel();
      await bloc.close();
    });

    test('a new identity and a sign-out are', () async {
      final bloc = _bloc(FakeAuthRepository())
        ..add(SessionEstablished(_tokens('first')));
      final changes = <Object>[];
      final sub = bloc.routingChanges.listen(changes.add);
      await Future<void>.delayed(Duration.zero);

      // An account switch.
      bloc.add(SessionEstablished(_tokens('second')));
      await Future<void>.delayed(Duration.zero);
      expect(changes, hasLength(2));

      bloc.add(const SessionLogoutRequested(callBackend: false));
      await Future<void>.delayed(Duration.zero);
      expect(changes, hasLength(3));

      await sub.cancel();
      await bloc.close();
    });
  });
}
