import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/mfa/presentation/mfa_verify_page.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';

Widget _wrap(Widget child) => MultiBlocProvider(
  providers: [
    BlocProvider<SessionBloc>.value(value: getIt<SessionBloc>()),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

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

  testWidgets('MfaVerifyPage renders the verify form when challenged', (
    tester,
  ) async {
    // Put the session into the MFA-required state, as login does.
    getIt<SessionBloc>().add(
      const SessionMfaChallenged(
        mfaToken: 'mfa-token',
        methods: ['totp', 'recovery', 'passkey'],
      ),
    );
    await tester.pump();

    await tester.pumpWidget(_wrap(const MfaVerifyPage()));
    await tester.pumpAndSettle();

    // Must NOT be a blank/gray screen — the form chrome must be present.
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
