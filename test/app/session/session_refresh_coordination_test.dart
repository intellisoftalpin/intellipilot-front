import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/session/session_sync.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/problem.dart';
import 'package:intellipilot/core/network/interceptors/refresh_interceptor.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';

import '../../helpers/fake_auth_repository.dart';

/// In-memory stand-in for a BroadcastChannel: every tab sees every other
/// tab's messages, never its own.
class _Bus {
  final _tabs = <_BusChannel>[];

  _BusChannel join() {
    final c = _BusChannel(this);
    _tabs.add(c);
    return c;
  }
}

class _BusChannel implements TabChannel {
  _BusChannel(this._bus);
  final _Bus _bus;
  final _controller = StreamController<Map<String, Object?>>.broadcast();

  @override
  void post(Map<String, Object?> message) {
    for (final tab in _bus._tabs) {
      if (!identical(tab, this)) tab._controller.add(Map.of(message));
    }
  }

  @override
  Stream<Map<String, Object?>> get messages => _controller.stream;

  @override
  void close() => unawaited(_controller.close());
}

TokenResponse _tokens(String access, {int expiresIn = 900}) => TokenResponse(
  accessToken: access,
  tokenType: 'Bearer',
  expiresIn: expiresIn,
);

const _superseded = UnauthorizedFailure(
  problem: Problem(
    type: 'https://intellipilot.dev/problems/refresh_superseded',
    title: 'Unauthorized',
    status: 401,
  ),
);

SessionBloc _bloc(FakeAuthRepository repo, {SessionSync? sync}) => SessionBloc(
  repository: repo,
  sync: sync,
  supersededRetryDelay: () => Duration.zero,
  refreshJitter: () => Duration.zero,
);

SessionAuthenticated _authed(String token) => SessionAuthenticated(
  accessToken: token,
  expiresAt: DateTime.now().add(const Duration(minutes: 10)),
);

void main() {
  group('single-flight refresh', () {
    test('timer and 401 hook firing together refresh exactly once', () async {
      final gate = Completer<Result<TokenResponse, AppFailure>>();
      final repo = FakeAuthRepository(refreshHandler: () => gate.future);
      final bloc = _bloc(repo)..emit(_authed('old'));

      // The proactive timer fires...
      bloc.add(const SessionRefreshRequested());
      // ...and, while that is in flight, a request comes back 401.
      final hook = bloc.refreshHook();
      await Future<void>.delayed(Duration.zero);
      bloc.add(const SessionRefreshRequested());
      await Future<void>.delayed(Duration.zero);

      gate.complete(Ok(_tokens('new')));
      expect(await hook, RefreshOutcome.refreshed);
      expect(
        repo.refreshCalls,
        1,
        reason: 'a second refresh replays the token',
      );
      expect((bloc.state as SessionAuthenticated).accessToken, 'new');
      await bloc.close();
    });

    test('a 401 during startup joins the startup refresh', () async {
      final gate = Completer<Result<TokenResponse, AppFailure>>();
      final repo = FakeAuthRepository(refreshHandler: () => gate.future);
      final bloc = _bloc(repo)..add(const SessionStartupRequested());
      await Future<void>.delayed(Duration.zero);

      final hook = bloc.refreshHook();
      await Future<void>.delayed(Duration.zero);
      gate.complete(Ok(_tokens('first')));

      expect(await hook, RefreshOutcome.refreshed);
      expect(repo.refreshCalls, 1);
      await bloc.close();
    });
  });

  group('superseded refresh', () {
    test('retries once and stays signed in', () async {
      var calls = 0;
      final repo = FakeAuthRepository(
        refreshHandler: () async {
          calls++;
          return calls == 1
              ? const Err<TokenResponse, AppFailure>(_superseded)
              : Ok<TokenResponse, AppFailure>(_tokens('after-retry'));
        },
      );
      final bloc = _bloc(repo)..emit(_authed('old'));

      final outcome = bloc.refreshHook();
      expect(await outcome, RefreshOutcome.refreshed);
      expect(repo.refreshCalls, 2);
      expect((bloc.state as SessionAuthenticated).accessToken, 'after-retry');
      await bloc.close();
    });

    test('a 401 after sign-out fails at once instead of waiting', () async {
      final repo = FakeAuthRepository();
      final bloc = _bloc(repo)
        ..emit(const SessionUnauthenticated(reason: SessionEndReason.startup));

      expect(
        await bloc.refreshHook().timeout(const Duration(seconds: 1)),
        RefreshOutcome.failed,
      );
      expect(repo.refreshCalls, 0);
      await bloc.close();
    });

    test('a plain 401 is not retried and signs out', () async {
      final repo = FakeAuthRepository(
        refreshHandler: () async =>
            const Err<TokenResponse, AppFailure>(UnauthorizedFailure()),
      );
      final bloc = _bloc(repo)..emit(_authed('old'));

      expect(await bloc.refreshHook(), RefreshOutcome.failed);
      expect(repo.refreshCalls, 1);
      expect(bloc.state, isA<SessionUnauthenticated>());
      await bloc.close();
    });
  });

  group('cross-tab', () {
    late _Bus bus;

    setUp(() => bus = _Bus());

    SessionSync tab() => ChannelSessionSync(bus.join(), LocalTabLock());

    test("a new tab adopts an open tab's token without refreshing", () async {
      final openRepo = FakeAuthRepository();
      final open = _bloc(openRepo, sync: tab())..emit(_authed('shared'));

      final newRepo = FakeAuthRepository();
      final fresh = _bloc(newRepo, sync: tab())
        ..add(const SessionStartupRequested());
      await fresh.stream.firstWhere((s) => s is SessionAuthenticated);

      expect((fresh.state as SessionAuthenticated).accessToken, 'shared');
      expect(newRepo.refreshCalls, 0, reason: 'the shared cookie is untouched');
      await open.close();
      await fresh.close();
    });

    test('a lone new tab refreshes after nobody answers', () async {
      final repo = FakeAuthRepository(
        refreshHandler: () async => Ok(_tokens('own')),
      );
      final bloc = _bloc(repo, sync: tab())
        ..add(const SessionStartupRequested());
      await bloc.stream.firstWhere((s) => s is SessionAuthenticated);

      expect(repo.refreshCalls, 1);
      await bloc.close();
    });

    test('a refresh in one tab is adopted by the others', () async {
      final repoA = FakeAuthRepository(
        refreshHandler: () async => Ok(_tokens('rotated', expiresIn: 900)),
      );
      final a = _bloc(repoA, sync: tab())..emit(_authed('old'));
      final repoB = FakeAuthRepository();
      final b = _bloc(repoB, sync: tab())..emit(_authed('old'));

      expect(await a.refreshHook(), RefreshOutcome.refreshed);
      await b.stream.firstWhere(
        (s) => s is SessionAuthenticated && s.accessToken == 'rotated',
      );
      expect(repoB.refreshCalls, 0);
      await a.close();
      await b.close();
    });

    test(
      "a tab queued behind another tab's refresh reuses its token",
      () async {
        final lock = LocalTabLock();
        final gate = Completer<Result<TokenResponse, AppFailure>>();
        final repoA = FakeAuthRepository(refreshHandler: () => gate.future);
        final repoB = FakeAuthRepository(
          refreshHandler: () async => Ok(_tokens('should-not-happen')),
        );
        // Both tabs share one lock, as navigator.locks would give them.
        final a = _bloc(repoA, sync: ChannelSessionSync(bus.join(), lock))
          ..emit(_authed('old'));
        final b = _bloc(repoB, sync: ChannelSessionSync(bus.join(), lock))
          ..emit(_authed('old'));

        final hookA = a.refreshHook();
        await Future<void>.delayed(Duration.zero);
        final hookB = b.refreshHook();
        await Future<void>.delayed(Duration.zero);
        gate.complete(Ok(_tokens('from-a')));

        expect(await hookA, RefreshOutcome.refreshed);
        expect(await hookB, RefreshOutcome.refreshed);
        expect(repoB.refreshCalls, 0, reason: 'b must not replay the cookie');
        expect((b.state as SessionAuthenticated).accessToken, 'from-a');
        await a.close();
        await b.close();
      },
    );

    test('signing out in one tab signs out the others', () async {
      final a = _bloc(FakeAuthRepository(), sync: tab())..emit(_authed('t'));
      final b = _bloc(FakeAuthRepository(), sync: tab())..emit(_authed('t'));

      a.add(const SessionLogoutRequested());
      await b.stream.firstWhere((s) => s is SessionUnauthenticated);
      await a.close();
      await b.close();
    });
  });

  test('LocalTabLock runs bodies one at a time', () async {
    final lock = LocalTabLock();
    final order = <String>[];
    final first = Completer<void>();
    final a = lock.run(() async {
      order.add('a-start');
      await first.future;
      order.add('a-end');
    });
    final b = lock.run(() async => order.add('b'));
    await Future<void>.delayed(Duration.zero);
    first.complete();
    await Future.wait([a, b]);
    expect(order, ['a-start', 'a-end', 'b']);
  });

  group('a tab that never releases the lock', () {
    test('startup still signs in instead of spinning forever', () async {
      final repo = FakeAuthRepository(
        refreshHandler: () async => Ok(_tokens('fresh')),
      );
      final sync = ChannelSessionSync(
        _Bus().join(),
        PatientTabLock(
          _FrozenHolderLocks(),
          maxWait: const Duration(milliseconds: 20),
        ),
      );
      final bloc = _bloc(repo, sync: sync)
        ..add(const SessionStartupRequested());

      final settled = await bloc.stream
          .firstWhere((s) => s is! SessionUnknown)
          .timeout(const Duration(seconds: 2));
      expect((settled as SessionAuthenticated).accessToken, 'fresh');
      expect(repo.refreshCalls, 1);
      await bloc.close();
      await sync.dispose();
    });
  });
}

/// The lock is held by a frozen background tab: a polite request is never
/// granted; only stealing gets it.
class _FrozenHolderLocks implements LockRequester {
  @override
  Future<bool> request(
    Future<void> Function() onGranted, {
    Future<void>? abandonWhen,
    bool steal = false,
  }) async {
    if (!steal) {
      await (abandonWhen ?? Completer<void>().future);
      return false;
    }
    await onGranted();
    return true;
  }
}
