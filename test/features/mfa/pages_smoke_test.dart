import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/mfa/data/dtos/mfa_dtos.dart';
import 'package:intellipilot/features/mfa/presentation/mfa_verify_page.dart';
import 'package:intellipilot/features/mfa/presentation/passkey_signin_page.dart';
import 'package:intellipilot/features/mfa/presentation/passkeys_page.dart';
import 'package:intellipilot/features/mfa/presentation/recovery_codes_page.dart';
import 'package:intellipilot/features/mfa/presentation/security_page.dart';
import 'package:intellipilot/features/mfa/presentation/totp_setup_page.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_mfa_repository.dart';

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
  late FakeMfaRepository mfa;
  late FakeAuthRepository auth;

  setUp(() async {
    mfa = FakeMfaRepository();
    auth = FakeAuthRepository();
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: InMemoryKeyValueStorage(),
      authRepository: auth,
      mfaRepository: mfa,
      passkeyService: StubPasskeyService(),
    );
  });
  tearDown(resetDependencies);

  testWidgets('SecurityPage renders all tiles', (tester) async {
    await tester.pumpWidget(_wrap(const SecurityPage()));
    await tester.pumpAndSettle();
    expect(find.text('Set up authenticator app'), findsOneWidget);
    expect(find.text('Recovery codes'), findsWidgets);
    expect(find.text('Manage passkeys'), findsOneWidget);
  });

  testWidgets('TotpSetupPage shows QR + secret when start succeeds', (
    tester,
  ) async {
    mfa.startTotpHandler = () async => const Ok<TotpStartResponse, AppFailure>(
      TotpStartResponse(
        secretBase32: 'JBSWY3DPEHPK3PXP',
        provisioningUri: 'otpauth://totp/x',
        qrPngBase64:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAfbLI3wAAAABJRU5ErkJggg==',
      ),
    );
    await tester.pumpWidget(_wrap(const TotpSetupPage()));
    await tester.pumpAndSettle();
    expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
    expect(find.text('6-digit code'), findsOneWidget);
  });

  testWidgets('RecoveryCodesPage shows codes after regenerate', (tester) async {
    mfa.regenerateHandler = () async =>
        const Ok<RecoveryCodesResponse, AppFailure>(
          RecoveryCodesResponse(codes: ['code-1', 'code-2']),
        );
    await tester.pumpWidget(_wrap(const RecoveryCodesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Generate new codes'));
    await tester.pumpAndSettle();
    expect(find.text('code-1'), findsOneWidget);
    expect(find.text('code-2'), findsOneWidget);
  });

  testWidgets('PasskeysPage shows empty state when no passkeys', (
    tester,
  ) async {
    mfa.listPasskeysHandler = () async =>
        const Ok<List<PasskeyListItem>, AppFailure>([]);
    await tester.pumpWidget(_wrap(const PasskeysPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining("haven't added"), findsOneWidget);
  });

  testWidgets('MfaVerifyPage shows context-lost message without challenge', (
    tester,
  ) async {
    // SessionBloc is in SessionUnknown by default → not SessionMfaRequired.
    await tester.pumpWidget(_wrap(const MfaVerifyPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('sign-in session expired'), findsOneWidget);
  });

  testWidgets('MfaVerifyPage renders form when session is MfaRequired', (
    tester,
  ) async {
    getIt<SessionBloc>().add(
      const SessionMfaChallenged(
        mfaToken: 'mfa-1',
        methods: ['totp', 'recovery'],
      ),
    );
    await tester.pump();
    await tester.pumpWidget(_wrap(const MfaVerifyPage()));
    await tester.pumpAndSettle();
    expect(find.text('Authenticator'), findsOneWidget);
    expect(find.text('Recovery code'), findsOneWidget);
  });

  testWidgets('PasskeySignInPage shows unsupported notice on stub', (
    tester,
  ) async {
    // StubPasskeyService defaults to supported=true; replace with unsupported.
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: InMemoryKeyValueStorage(),
      authRepository: auth,
      mfaRepository: mfa,
      passkeyService: StubPasskeyService(supported: false),
    );
    await tester.pumpWidget(_wrap(const PasskeySignInPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining("aren't available"), findsOneWidget);
  });

  testWidgets('PasskeySignInPage shows form when supported', (tester) async {
    await tester.pumpWidget(_wrap(const PasskeySignInPage()));
    await tester.pumpAndSettle();
    expect(find.text('Continue with a passkey'), findsOneWidget);
  });
}
