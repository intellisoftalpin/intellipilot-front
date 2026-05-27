import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/theme/theme_cubit.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/presentation/forgot_password_page.dart';
import 'package:intellipilot/features/auth/presentation/login_page.dart';
import 'package:intellipilot/features/auth/presentation/register_page.dart';
import 'package:intellipilot/features/auth/presentation/reset_password_page.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';

Widget _wrap(Widget child) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ThemeCubit>.value(value: getIt<ThemeCubit>()),
      BlocProvider<LocaleCubit>.value(value: getIt<LocaleCubit>()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Navigator(
        onGenerateRoute: (_) =>
            MaterialPageRoute<void>(builder: (_) => child),
      ),
    ),
  );
}

void main() {
  late FakeAuthRepository repo;

  setUp(() async {
    repo = FakeAuthRepository();
    await resetDependencies();
    await configureForTests(
      settingsStorage: InMemoryKeyValueStorage(),
      uiStorage: InMemoryKeyValueStorage(),
      authRepository: repo,
    );
  });

  tearDown(resetDependencies);

  testWidgets('LoginPage shows form and error banner on submit failure',
      (tester) async {
    await tester.pumpWidget(_wrap(const LoginPage()));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    // Trigger validation by submitting empty.
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('This field is required.'), findsWidgets);

    // Try with credentials; FakeAuthRepository defaults to Unauthorized.
    await tester.enterText(
      find.widgetWithText(TextField, 'Email').first,
      'u@e.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password').first,
      'pw12345678',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('incorrect'), findsOneWidget);
  });

  testWidgets('LoginPage surfaces MFA notice on mfa_required',
      (tester) async {
    repo.loginHandler = (_, _) async => const Ok<LoginResult, AppFailure>(
      LoginMfaRequired(mfaToken: 'mfa', methods: ['totp']),
    );

    await tester.pumpWidget(_wrap(const LoginPage()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email').first,
      'u@e.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password').first,
      'pw12345678',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2FA'), findsOneWidget);
  });

  testWidgets('RegisterPage renders all required fields', (tester) async {
    await tester.pumpWidget(_wrap(const RegisterPage()));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsWidgets);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Full name (optional)'), findsOneWidget);
  });

  testWidgets('RegisterPage shows ConflictFailure copy on 409', (tester) async {
    repo.registerHandler =
        () async => const Err<Unit, AppFailure>(ConflictFailure());

    await tester.pumpWidget(_wrap(const RegisterPage()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email').first,
      'u@e.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Username').first,
      'user1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password').first,
      'pw12345678',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already in use'), findsOneWidget);
  });

  testWidgets('ForgotPasswordPage shows success panel with dev token banner',
      (tester) async {
    repo.requestResetHandler = (_) async =>
        const Ok<PasswordResetRequestResponse, AppFailure>(
          PasswordResetRequestResponse(status: 'ok', resetToken: 'TOK123'),
        );

    await tester.pumpWidget(_wrap(const ForgotPasswordPage()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email').first,
      'u@e.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send reset link'));
    await tester.pumpAndSettle();

    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text('Development reset token'), findsOneWidget);
    expect(find.text('TOK123'), findsOneWidget);
  });

  testWidgets(
    'ResetPasswordPage pre-fills the token from initialToken',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const ResetPasswordPage(initialToken: 'PREFILL')),
      );
      await tester.pumpAndSettle();

      expect(find.text('PREFILL'), findsOneWidget);
    },
  );

  testWidgets('ResetPasswordPage submit failure shows the error banner',
      (tester) async {
    repo.confirmResetHandler = () async => const Err<Unit, AppFailure>(
      ValidationFailure(fieldErrors: []),
    );

    await tester.pumpWidget(
      _wrap(const ResetPasswordPage(initialToken: 'tok')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New password').first,
      'pw12345678',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await tester.pumpAndSettle();

    expect(find.textContaining('stronger'), findsOneWidget);
  });

  test('Routes constants surface the new auth paths', () {
    expect(Routes.register, '/register');
    expect(Routes.forgotPassword, '/forgot-password');
    expect(Routes.resetPassword, '/reset-password');
  });
}
