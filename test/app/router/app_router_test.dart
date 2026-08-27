import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/l10n/week_start_cubit.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';

/// Enough of a projects repository for /projects to render. The guard is what
/// these tests exercise; the page just has to not throw.
class _EmptyProjects extends Fake implements ProjectsRepository {
  @override
  Future<Result<List<Project>, AppFailure>> listProjects() async =>
      const Ok([]);
}

void main() {
  setUp(() async {
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: InMemoryKeyValueStorage(),
      authRepository: FakeAuthRepository(),
    );
  });

  tearDown(resetDependencies);

  testWidgets(
    'unauthenticated visit to / redirects to /login',
    (tester) async {
      // Drive the session into Unauthenticated explicitly.
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

      // Login page renders.
      expect(find.text('Sign in'), findsWidgets);
    },
  );

  testWidgets(
    'an unauthenticated user can reach the connect wizard from login',
    (tester) async {
      // The whole point of the "Change server" affordance: someone who typed
      // the wrong address must be able to get back to step ①. The guard has to
      // let /connect through for an unauthenticated user even though a server
      // is already configured.
      // Model a real desktop install: no --dart-define, so nothing is pinned
      // at build time, and a server the user chose in the wizard. (The default
      // test DI pins one, which correctly hides the banner.)
      final storage = InMemoryKeyValueStorage();
      final endpoint = ServerEndpoint(storage: storage, compileTimeBase: '');
      await endpoint.save('https://typo.example.com');
      getIt.registerSingleton<ServerEndpoint>(endpoint);

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
      expect(find.text('Sign in'), findsWidgets);
      // The server is named up front, so a mistyped host is obvious.
      expect(find.textContaining('typo.example.com'), findsOneWidget);

      // The affordance must be ON the login screen, not buried below the fold.
      expect(find.text('Change server'), findsOneWidget);

      await tester.tap(find.text('Change server'));
      await tester.pumpAndSettle();

      // And it must actually land on the wizard, not be bounced back.
      expect(find.text('Connect to your server'), findsOneWidget);
    },
  );

  testWidgets(
    'add another account starts at step ① with an empty server field',
    (tester) async {
      // Two bugs in one place. The guard bounces authenticated users off the
      // wizard, which is right when someone stumbles back onto it and wrong
      // when they deliberately chose "Add another account" — that used to land
      // on the projects list. And the entry point was step ② (/login), which
      // silently assumed the current server, so a second account on a
      // *different* server could not be added at all.
      final storage = InMemoryKeyValueStorage();
      final endpoint = ServerEndpoint(storage: storage, compileTimeBase: '');
      await endpoint.save('https://one.example.com');
      getIt.registerSingleton<ServerEndpoint>(endpoint);

      final session = getIt<SessionBloc>();
      session.add(
        const SessionEstablished(
          TokenResponse(accessToken: 'a', tokenType: 'Bearer', expiresIn: 3600),
        ),
      );
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

      router.go(Routes.addAccount());
      await tester.pumpAndSettle();

      // Step ①, not bounced and not step ②.
      expect(find.text('Connect to your server'), findsOneWidget);
      expect(find.text('Add another account'), findsWidgets);

      // Empty, not prefilled with the server already signed in to: entering a
      // different one is the entire reason this step exists.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, isEmpty);
    },
  );

  testWidgets('an authenticated user is still bounced off a plain /connect', (
    tester,
  ) async {
    // "Change server" for the only account remains a deliberate act from the
    // login screen; landing there while signed in must still go home.
    getIt.registerSingleton<ProjectsRepository>(_EmptyProjects());
    final storage = InMemoryKeyValueStorage();
    final endpoint = ServerEndpoint(storage: storage, compileTimeBase: '');
    await endpoint.save('https://one.example.com');
    getIt.registerSingleton<ServerEndpoint>(endpoint);

    final session = getIt<SessionBloc>();
    session.add(
      const SessionEstablished(
        TokenResponse(accessToken: 'a', tokenType: 'Bearer', expiresIn: 3600),
      ),
    );
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

    router.go(Routes.connect);
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Routes.projects,
    );
    expect(find.text('Connect to your server'), findsNothing);
  });

  testWidgets('step ② of an add-account run is reachable', (tester) async {
    // Once step ① has adopted the new server, the login screen must stay
    // reachable even though the guard normally bounces authenticated users.
    final storage = InMemoryKeyValueStorage();
    final endpoint = ServerEndpoint(storage: storage, compileTimeBase: '');
    await endpoint.save('https://two.example.com');
    getIt.registerSingleton<ServerEndpoint>(endpoint);

    final session = getIt<SessionBloc>();
    session.add(
      const SessionEstablished(
        TokenResponse(accessToken: 'a', tokenType: 'Bearer', expiresIn: 3600),
      ),
    );
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

    router.go(Routes.addAccountLogin());
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Add another account'), findsWidgets);
  });

  testWidgets(
    'an authenticated user is still bounced off a plain /login',
    (tester) async {
      // The original protection must survive: only the explicit add flag gets
      // through, or a stray back-navigation would strand a signed-in user.
      getIt.registerSingleton<ProjectsRepository>(_EmptyProjects());
      final session = getIt<SessionBloc>();
      session.add(
        const SessionEstablished(
          TokenResponse(accessToken: 'a', tokenType: 'Bearer', expiresIn: 3600),
        ),
      );
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

      // Bounced to the projects list, and crucially NOT showing the
      // add-account header — only the explicit flag may get through.
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        Routes.projects,
      );
      expect(find.text('Add another account'), findsNothing);
    },
  );

  testWidgets('authenticated session lands on home and can reach settings', (
    tester,
  ) async {
    final session = getIt<SessionBloc>()
      ..add(
        const SessionEstablished(
          TokenResponse(
            accessToken: 'tok',
            tokenType: 'Bearer',
            expiresIn: 3600,
          ),
        ),
      );
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
    expect(find.textContaining('Welcome back'), findsOneWidget);

    router.go(Routes.settings);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
  });

  test('Routes constants are stable', () {
    expect(Routes.home, '/');
    expect(Routes.settings, '/me/settings');
    expect(Routes.login, '/login');
    expect(Routes.register, '/register');
    expect(Routes.forgotPassword, '/forgot-password');
    expect(Routes.resetPassword, '/reset-password');
  });
}
