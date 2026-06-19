import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/auth/presentation/auth_validators.dart';
import 'package:intellipilot/features/auth/presentation/cubits/forgot_password_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:reactive_forms/reactive_forms.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ForgotPasswordCubit>(
      create: (_) => ForgotPasswordCubit(getIt<AuthRepository>()),
      child: const _ForgotPasswordView(),
    );
  }
}

class _ForgotPasswordView extends StatefulWidget {
  const _ForgotPasswordView();

  @override
  State<_ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<_ForgotPasswordView> {
  late final FormGroup _form;

  /// null = still loading the server config; true/false once known. Email reset
  /// is only offered when a mailer is configured server-side.
  bool? _resetEnabled;

  @override
  void initState() {
    super.initState();
    _form = FormGroup({
      'email': FormControl<String>(validators: AuthValidators.email),
    });
    unawaited(_loadConfig());
  }

  Future<void> _loadConfig() async {
    final res = await getIt<AuthRepository>().authConfig();
    if (!mounted) return;
    res.when(
      // On error, fall back to showing the form rather than blocking reset.
      ok: (c) => setState(() => _resetEnabled = c.passwordResetEnabled),
      err: (_) => setState(() => _resetEnabled = true),
    );
  }

  void _submit() {
    if (!_form.valid) {
      _form.markAllAsTouched();
      return;
    }
    unawaited(
      context.read<ForgotPasswordCubit>().submit(
        _form.control('email').value as String,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.forgotPasswordTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _resetEnabled == null
                ? const Center(child: CircularProgressIndicator())
                : !_resetEnabled!
                ? const _ResetUnavailablePanel()
                : BlocBuilder<ForgotPasswordCubit, ForgotPasswordState>(
                    builder: (context, state) {
                      final busy = state is ForgotPasswordSubmitting;
                      if (state is ForgotPasswordSucceeded) {
                        return _SuccessPanel(devToken: state.devToken);
                      }
                      return ReactiveForm(
                        formGroup: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              t.forgotPasswordBody,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            ReactiveTextField<String>(
                              formControlName: 'email',
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: t.fieldEmail,
                                prefixIcon: const Icon(Icons.alternate_email),
                              ),
                              validationMessages: {
                                ValidationMessage.required: (_) =>
                                    t.errFieldRequired,
                                ValidationMessage.email: (_) =>
                                    t.errEmailInvalid,
                              },
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: busy ? null : _submit,
                              child: busy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(t.actionSendResetLink),
                            ),
                            if (state is ForgotPasswordFailed) ...[
                              const SizedBox(height: 16),
                              Text(
                                t.errUnknown,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the server has no mailer configured: there's no way to send a
/// reset link, so direct the user to an administrator instead of a dead form.
class _ResetUnavailablePanel extends StatelessWidget {
  const _ResetUnavailablePanel();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_unread_outlined, size: 56),
        const SizedBox(height: 16),
        Text(
          t.passwordResetUnavailableTitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(t.passwordResetUnavailableBody, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => context.goNamed('login'),
          child: Text(t.actionBackToLogin),
        ),
      ],
    );
  }
}

class _SuccessPanel extends StatelessWidget {
  const _SuccessPanel({this.devToken});
  final String? devToken;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 56),
        const SizedBox(height: 16),
        Text(
          t.forgotPasswordSuccessTitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(t.forgotPasswordSuccessBody, textAlign: TextAlign.center),
        if (devToken != null) ...[
          const SizedBox(height: 24),
          _DevTokenCard(token: devToken!),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            final params = devToken == null
                ? <String, String>{}
                : {'token': devToken!};
            context.goNamed('reset_password', queryParameters: params);
          },
          child: Text(t.actionContinueToReset),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.goNamed('login'),
          child: Text(t.actionBackToLogin),
        ),
      ],
    );
  }
}

class _DevTokenCard extends StatelessWidget {
  const _DevTokenCard({required this.token});
  final String token;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.bug_report_outlined,
                color: colors.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.devTokenBannerTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            token,
            style: TextStyle(
              fontFamily: 'monospace',
              color: colors.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: Text(t.actionCopy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(t.copiedToClipboard)));
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
