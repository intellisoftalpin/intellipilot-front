import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/network/sse/project_events_service.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/utils/uuid_gen.dart';
import 'package:intellipilot/features/accounts/data/account_store.dart';
import 'package:intellipilot/features/accounts/data/secret_store.dart';
import 'package:intellipilot/features/accounts/domain/account.dart';
import 'package:intellipilot/features/accounts/domain/account_scope.dart';
import 'package:intellipilot/features/accounts/domain/account_switcher.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

const _tokens = TokenResponse(
  accessToken: 'access',
  tokenType: 'Bearer',
  expiresIn: 3600,
  refreshToken: 'rotated',
);

FakeAuthRepository _auth() => FakeAuthRepository(
  refreshHandler: () async => const Ok(_tokens),
  logoutHandler: () async => const Ok(Unit.instance),
);

class _Fixture {
  _Fixture() {
    store = AccountStore(secrets: InMemorySecretStore());
    scope = AccountScope();
    endpoint = ServerEndpoint(
      storage: InMemoryKeyValueStorage(),
      compileTimeBase: '',
    );
    api = ApiClient(
      config: const ApiConfig(baseUrl: 'http://unset'),
      uuidGen: const DefaultUuidGen(),
      tokenProvider: () => null,
      dio: Dio(),
    );
    session = SessionBloc(repository: _auth());
    events = ProjectEventsService(
      baseUrl: () => endpoint.effective,
      tokenProvider: () => null,
    );
    switcher = AccountSwitcher(
      store: store,
      scope: scope,
      endpoint: endpoint,
      apiClient: api,
      auth: _auth(),
      profiles: FakeProfileRepository(
        getProfileHandler: () async => Ok(_profile),
      ),
      session: () => session,
      events: () => events,
      onServerChanged: () => serverChanges++,
    );
  }

  late final AccountStore store;
  late final AccountScope scope;
  late final ServerEndpoint endpoint;
  late final ApiClient api;
  late final SessionBloc session;
  late final ProjectEventsService events;
  late final AccountSwitcher switcher;
  int serverChanges = 0;
}

final _profile = UserProfile(
  id: 'u2',
  email: 'bob@two.example.com',
  username: 'bob',
  fullName: 'Bob',
  lang: 'en',
  timezone: 'UTC',
  isActive: true,
  isSuperadmin: false,
  mustChangePassword: false,
  createdAt: DateTime.utc(2026),
);

const _first = Account(
  serverUrl: 'https://one.example.com',
  userId: 'u1',
  username: 'ann',
  email: 'ann@one.example.com',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'beginAddAccount stands the account down without discarding it',
    () async {
      final f = _Fixture();
      await f.store.upsert(_first, refreshToken: 'r1');
      await f.store.setActive(_first);
      await f.switcher.restore();
      expect(f.switcher.active, _first);

      await f.switcher.beginAddAccount(currentRoute: '/projects/p1/board');

      // No live identity while the app is about to point at another server: a
      // background refresh in that window would send this token to the new host.
      expect(f.switcher.active, isNull);
      expect(f.switcher.currentRefreshToken(), isNull);
      expect(f.scope.key, isEmpty);
      // But the account itself survives, so cancelling can bring it back.
      expect(f.switcher.suspendedAccount, _first);
      expect((await f.store.list()).single, _first);
    },
  );

  test(
    'cancelAddAccount restores the suspended account and its route',
    () async {
      final f = _Fixture();
      await f.store.upsert(_first, refreshToken: 'r1');
      await f.store.setActive(_first);
      await f.switcher.restore();
      await f.switcher.beginAddAccount(currentRoute: '/projects/p1/board');
      // Step ① adopted a different server, as it would after a real connect.
      await f.endpoint.save('https://two.example.com');

      final restored = await f.switcher.cancelAddAccount();

      expect(restored, isTrue);
      expect(f.switcher.active, _first);
      expect(f.switcher.suspendedAccount, isNull);
      // Server, token and remembered route all come back.
      expect(f.endpoint.effective, 'https://one.example.com');
      expect(f.switcher.currentRefreshToken(), 'rotated');
      expect(
        await f.switcher.restoredRouteFor(_first),
        '/projects/p1/board',
      );
    },
  );

  test('cancelling before a server was adopted is a no-op', () async {
    final f = _Fixture();
    await f.store.upsert(_first, refreshToken: 'r1');
    await f.store.setActive(_first);
    await f.switcher.restore();

    // Nothing suspended yet — the user backed out of step ① immediately.
    expect(await f.switcher.cancelAddAccount(), isFalse);
    expect(f.switcher.active, _first);
    expect(f.endpoint.effective, 'https://one.example.com');
  });

  test('moving to another server invalidates server-derived state', () async {
    // A stale "your app is too old" verdict from one server would otherwise
    // keep blocking the app on another.
    final f = _Fixture();
    await f.store.upsert(_first, refreshToken: 'r1');
    await f.store.setActive(_first);
    await f.switcher.restore();

    expect(f.serverChanges, 1);
  });

  test('adopting an account after login notifies its listeners', () async {
    // The switcher is read by the top-bar menu and the login screen's account
    // list, both of which are built BEFORE adoption finishes: a login navigates
    // on success while adoption is still waiting on a profile round-trip. A
    // one-shot read therefore always missed the account just added, and the
    // switcher never appeared at all.
    final f = _Fixture();
    await f.endpoint.save('https://two.example.com');
    var notifications = 0;
    f.switcher.addListener(() => notifications++);

    final adopted = await f.switcher.adoptAfterLogin(_tokens);

    expect(adopted, isNotNull);
    expect(notifications, greaterThan(0));
    expect((await f.switcher.accounts()).map((a) => a.userId), contains('u2'));
  });

  test('a login that returns no refresh token adopts nothing', () async {
    // What a production server did until now: the token went into a Set-Cookie
    // the desktop app has no jar for, so there was nothing to persist.
    final f = _Fixture();
    await f.endpoint.save('https://two.example.com');

    const noRefresh = TokenResponse(
      accessToken: 'access',
      tokenType: 'Bearer',
      expiresIn: 3600,
    );
    expect(await f.switcher.adoptAfterLogin(noRefresh), isNull);
    expect(await f.switcher.accounts(), isEmpty);
  });
}
