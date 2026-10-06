import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/profile/presentation/widgets/profile_gate.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

Widget _gate({String project = 'p1'}) => ProfileGate(
  key: ValueKey(project),
  builder: (context, profile) => Text('$project:${profile.username}'),
);

void main() {
  late FakeProfileRepository profiles;
  late SessionBloc session;

  setUp(() {
    profiles = FakeProfileRepository();
    session = SessionBloc(repository: FakeAuthRepository());
    getIt
      ..registerSingleton<ProfileRepository>(profiles)
      ..registerSingleton<SessionBloc>(session);
  });

  tearDown(() async {
    await session.close();
    await getIt.reset();
  });

  testWidgets('loads the profile once however often it rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_gate()));
    await tester.pumpAndSettle();
    expect(find.text('p1:user1'), findsOneWidget);

    // What a router refresh does to the page.
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(_app(_gate()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    expect(profiles.getCalls, 1);
  });

  testWidgets('starts afresh for another project', (tester) async {
    await tester.pumpWidget(_app(_gate()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(_gate(project: 'p2')));
    await tester.pumpAndSettle();

    expect(find.text('p2:user1'), findsOneWidget);
    expect(profiles.getCalls, 2);
  });

  testWidgets('loads again when another account signs in', (tester) async {
    await tester.pumpWidget(_app(_gate()));
    await tester.pumpAndSettle();

    session.add(
      const SessionEstablished(
        TokenResponse(accessToken: 'b', tokenType: 'Bearer', expiresIn: 900),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(_app(_gate()));
    await tester.pumpAndSettle();

    expect(profiles.getCalls, 2);
  });
}
