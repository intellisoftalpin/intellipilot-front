import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/profile/presentation/account_page.dart';
import 'package:intellipilot/features/profile/presentation/profile_page.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

Widget _wrap(Widget child) => MultiBlocProvider(
  providers: [
    BlocProvider<ThemeCubit>.value(value: getIt<ThemeCubit>()),
    BlocProvider<LocaleCubit>.value(value: getIt<LocaleCubit>()),
    BlocProvider<SessionBloc>.value(value: getIt<SessionBloc>()),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Navigator(
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => child),
    ),
  ),
);

void main() {
  late FakeProfileRepository profile;
  late RecordingDownloader downloader;

  setUp(() async {
    profile = FakeProfileRepository();
    downloader = RecordingDownloader();
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: InMemoryKeyValueStorage(),
      authRepository: FakeAuthRepository(),
      profileRepository: profile,
      fileDownloader: downloader,
    );
  });

  tearDown(resetDependencies);

  testWidgets('ProfilePage renders fields seeded from the loaded user',
      (tester) async {
    await tester.pumpWidget(_wrap(const ProfilePage()));
    await tester.pumpAndSettle();
    expect(find.text('u@e.com'), findsOneWidget);
    expect(find.text('@user1'), findsOneWidget);
    expect(find.text('User One'), findsOneWidget);
    expect(find.text('UTC'), findsOneWidget);
  });

  testWidgets('ProfilePage save shows the saved snack', (tester) async {
    await tester.pumpWidget(_wrap(const ProfilePage()));
    await tester.pumpAndSettle();
    // The form now carries an avatar editor + motto + mood, so the save
    // button can sit below the fold — scroll it into view first.
    final saveButton = find.widgetWithText(FilledButton, 'Save changes');
    await tester.scrollUntilVisible(
      saveButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.text('Profile updated.'), findsOneWidget);
  });

  testWidgets('AccountPage shows export + danger zone sections',
      (tester) async {
    await tester.pumpWidget(_wrap(const AccountPage()));
    await tester.pumpAndSettle();
    expect(find.text('Export your data'), findsOneWidget);
    expect(find.text('Danger zone'), findsOneWidget);
    expect(find.text('Delete account'), findsWidgets);
  });

  testWidgets('Export action triggers the downloader', (tester) async {
    await tester.pumpWidget(_wrap(const AccountPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(downloader.calls, 1);
    expect(downloader.lastFilename, 'intellipilot-export.json');
  });
}
