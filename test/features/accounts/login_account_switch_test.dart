import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/l10n/week_start_cubit.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/accounts/data/account_store.dart';
import 'package:intellipilot/features/accounts/domain/account.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';

class _EmptyProjects extends Fake implements ProjectsRepository {
  @override
  Future<Result<List<Project>, AppFailure>> listProjects() async =>
      const Ok([]);
}

const _first = Account(
  serverUrl: 'https://one.example.com',
  userId: 'u1',
  username: 'ann',
  email: 'ann@one.example.com',
);
const _second = Account(
  serverUrl: 'https://two.example.com',
  userId: 'u2',
  username: 'bob',
  email: 'bob@two.example.com',
);

const _tokens = TokenResponse(
  accessToken: 'access',
  tokenType: 'Bearer',
  expiresIn: 3600,
  refreshToken: 'rotated',
);

/// Login screen with both accounts stored, reached unauthenticated — the state
/// the app is in after abandoning an add-account run, or after a stored token
/// turned out to be dead at startup.
Future<GoRouter> _pumpLogin(
  WidgetTester tester, {
  required bool refreshWorks,
}) async {
  await resetDependencies();
  await configureForTests(
    settingsStorage: InMemoryKeyValueStorage(),
    uiStorage: InMemoryKeyValueStorage(),
    authRepository: FakeAuthRepository(
      refreshHandler: () async =>
          refreshWorks ? const Ok(_tokens) : const Err(UnauthorizedFailure()),
    ),
    projectsRepository: _EmptyProjects(),
  );
  final store = getIt<AccountStore>();
  await store.upsert(_first, refreshToken: 'r1');
  await store.upsert(_second, refreshToken: 'r2');

  final session = getIt<SessionBloc>();
  session.add(const SessionLogoutRequested(callBackend: false));
  await tester.pump();

  final router = buildRouter(session: session);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>.value(value: getIt<ThemeCubit>()),
        BlocProvider<LocaleCubit>.value(value: getIt<LocaleCubit>()),
        BlocProvider<WeekStartCubit>.value(value: getIt<WeekStartCubit>()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.go(Routes.login);
  await tester.pumpAndSettle();
  return router;
}

void main() {
  tearDown(resetDependencies);

  testWidgets('the login screen offers the accounts already signed in', (
    tester,
  ) async {
    // Without this the only way off the login screen was to finish a login the
    // user had already changed their mind about.
    await _pumpLogin(tester, refreshWorks: true);

    expect(find.text('Continue as'), findsOneWidget);
    // Server first: the same username routinely exists on two instances.
    expect(find.text('one.example.com'), findsWidgets);
    expect(find.text('two.example.com'), findsWidgets);
    expect(find.text('ann'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    // The credential form is still there for a genuinely new sign-in.
    expect(find.text('or sign in below'), findsOneWidget);
  });

  testWidgets('picking one signs straight into it', (tester) async {
    final router = await _pumpLogin(tester, refreshWorks: true);

    await tester.tap(find.text('two.example.com').first);
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Routes.projects,
    );

    // The live session schedules a token refresh; leave it running and the test
    // ends with a pending timer.
    getIt<SessionBloc>().add(const SessionLogoutRequested(callBackend: false));
    await tester.pump();
  });

  testWidgets('an account whose stored session died says so and drops out', (
    tester,
  ) async {
    // Silently doing nothing on tap would look like a broken button; leaving a
    // dead row in the list would invite tapping it again.
    await _pumpLogin(tester, refreshWorks: false);

    await tester.tap(find.text('two.example.com').first);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not switch to that account'),
      findsOneWidget,
    );
    expect(find.text('two.example.com'), findsNothing);
    // The other account survives — one dead credential must not clear the list.
    expect(find.text('one.example.com'), findsWidgets);
  });
}
