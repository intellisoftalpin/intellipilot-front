import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';

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

  testWidgets('authenticated session lands on home and can reach settings',
      (tester) async {
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
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome to IntelliPilot'), findsOneWidget);

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
