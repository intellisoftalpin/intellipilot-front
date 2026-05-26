import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

void main() {
  setUp(() async {
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: InMemoryKeyValueStorage(),
    );
  });

  tearDown(resetDependencies);

  testWidgets('routes resolve to their respective pages', (tester) async {
    final router = buildRouter();
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

    router.go(Routes.login);
    await tester.pumpAndSettle();
    expect(find.text('Login — coming in Phase 2'), findsOneWidget);
  });

  test('Routes constants are stable', () {
    expect(Routes.home, '/');
    expect(Routes.settings, '/me/settings');
    expect(Routes.login, '/login');
  });
}
