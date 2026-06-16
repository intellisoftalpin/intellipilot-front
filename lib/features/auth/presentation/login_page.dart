import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/branding/brand_logo.dart';
import 'package:intellipilot/app/branding/branding_cubit.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/url_opener.dart';
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
      'email': FormControl<String>(validators: AuthValidators.loginIdentifier),
      'password': FormControl<String>(validators: AuthValidators.password),
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
    return BlocBuilder<BrandingCubit, Branding>(
      bloc: getIt<BrandingCubit>(),
      builder: (context, branding) => Scaffold(
        body: BlocListener<LoginCubit, LoginState>(
          listener: (context, state) {
            if (state is LoginSucceeded) {
              // Router guard redirects automatically; no-op.
            }
          },
          child: Column(
            children: [
              Expanded(
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
                            const Center(
                              child: BrandLogo(size: 88, borderRadius: 18),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              branding.appName ?? t.appTitle,
                              style: Theme.of(context).textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t.loginSubtitle,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (branding.appMessage != null) ...[
                              const SizedBox(height: 16),
                              _AuthInfoBanner(text: branding.appMessage!),
                            ],
                            const SizedBox(height: 24),
                            ReactiveTextField<String>(
                              formControlName: 'email',
                              autofillHints: const [AutofillHints.username],
                              decoration: InputDecoration(
                                labelText: t.fieldEmailOrUsername,
                                prefixIcon: const Icon(Icons.person_outline),
                              ),
                              validationMessages: {
                                ValidationMessage.required: (_) =>
                                    t.errFieldRequired,
                                ValidationMessage.maxLength: (_) =>
                                    t.errTooLong,
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
                                ValidationMessage.required: (_) =>
                                    t.errFieldRequired,
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
                                  return _AuthErrorBanner(
                                    failure: state.failure,
                                  );
                                }
                                if (state is LoginMfaChallenged) {
                                  return _AuthInfoBanner(
                                    text: t.loginMfaNotice,
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              icon: const Icon(Icons.fingerprint, size: 18),
                              onPressed: () =>
                                  context.goNamed('passkey_sign_in'),
                              label: Text(t.linkSignInWithPasskey),
                            ),
                            const SizedBox(height: 4),
                            const _RegisterLink(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const _LoginFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Developer attribution footer, shown on the login screen only. Links open in
/// a new tab via [openExternalUrl]; native targets degrade to a no-op.
class _LoginFooter extends StatelessWidget {
  const _LoginFooter();

  static const _website = 'https://intellisoftalpin.com';
  static const _repo = 'https://github.com/intellisoftalpin/intellipilot';
  static const _license =
      'https://github.com/intellisoftalpin/intellipilot/blob/main/LICENSE';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final year = DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text('© 2025–$year IntelliSoftAlpin', style: muted),
          _FooterLink(
            label: 'intellisoftalpin.com',
            onTap: () => openExternalUrl(_website),
          ),
          _FooterLink(label: 'GitHub', onTap: () => openExternalUrl(_repo)),
          _FooterLink(
            label: 'MIT License',
            onTap: () => openExternalUrl(_license),
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Self-service signup link, shown only when the server reports open
/// registration is enabled. Hidden while loading or on error, so a closed
/// instance never advertises a signup path that the backend would reject.
class _RegisterLink extends StatefulWidget {
  const _RegisterLink();

  @override
  State<_RegisterLink> createState() => _RegisterLinkState();
}

class _RegisterLinkState extends State<_RegisterLink> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await getIt<AuthRepository>().authConfig();
    if (!mounted) return;
    res.when(
      ok: (c) => setState(() => _open = c.openRegistration),
      err: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    return TextButton(
      onPressed: () => context.goNamed('register'),
      child: Text(t.linkCreateAccount),
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
