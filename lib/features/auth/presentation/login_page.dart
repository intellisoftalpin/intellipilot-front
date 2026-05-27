import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/auth/presentation/auth_validators.dart';
import 'package:intellipilot/features/auth/presentation/cubits/login_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:reactive_forms/reactive_forms.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LoginCubit>(
      create: (_) => LoginCubit(
        repo: getIt<AuthRepository>(),
        session: getIt<SessionBloc>(),
      ),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  late final FormGroup _form;

  @override
  void initState() {
    super.initState();
    _form = FormGroup({
      'email': FormControl<String>(validators: AuthValidators.email),
      'password': FormControl<String>(
        validators: AuthValidators.password,
      ),
    });
  }

  void _submit() {
    if (!_form.valid) {
      _form.markAllAsTouched();
      return;
    }
    context.read<LoginCubit>().submit(
      email: _form.control('email').value as String,
      password: _form.control('password').value as String,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: BlocListener<LoginCubit, LoginState>(
        listener: (context, state) {
          if (state is LoginSucceeded) {
            // Router guard redirects automatically; no-op.
          }
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ReactiveForm(
                formGroup: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t.appTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.loginSubtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    ReactiveTextField<String>(
                      formControlName: 'email',
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: t.fieldEmail,
                        prefixIcon: const Icon(Icons.alternate_email),
                      ),
                      validationMessages: {
                        ValidationMessage.required: (_) => t.errFieldRequired,
                        ValidationMessage.email: (_) => t.errEmailInvalid,
                        ValidationMessage.maxLength: (_) => t.errTooLong,
                      },
                    ),
                    const SizedBox(height: 12),
                    ReactiveTextField<String>(
                      formControlName: 'password',
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: t.fieldPassword,
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      validationMessages: {
                        ValidationMessage.required: (_) => t.errFieldRequired,
                        ValidationMessage.minLength: (_) =>
                            t.errPasswordMinLength,
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () =>
                            context.goNamed('forgot_password'),
                        child: Text(t.linkForgotPassword),
                      ),
                    ),
                    const SizedBox(height: 8),
                    BlocBuilder<LoginCubit, LoginState>(
                      builder: (context, state) {
                        final busy = state is LoginSubmitting;
                        return FilledButton(
                          onPressed: busy ? null : _submit,
                          child: busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(t.actionSignIn),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    BlocBuilder<LoginCubit, LoginState>(
                      builder: (_, state) {
                        if (state is LoginFailed) {
                          return _AuthErrorBanner(failure: state.failure);
                        }
                        if (state is LoginMfaChallenged) {
                          return _AuthInfoBanner(text: t.loginMfaNotice);
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => context.goNamed('register'),
                      child: Text(t.linkCreateAccount),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthErrorBanner extends StatelessWidget {
  const _AuthErrorBanner({required this.failure});
  final AppFailure failure;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context).colorScheme;
    final message = switch (failure) {
      UnauthorizedFailure() => t.errInvalidCredentials,
      NetworkFailure() => t.errNetwork,
      RateLimitedFailure() => t.errTooManyAttempts,
      ValidationFailure() => t.errValidation,
      ServerFailure() => t.errServer,
      _ => t.errUnknown,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthInfoBanner extends StatelessWidget {
  const _AuthInfoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: theme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
