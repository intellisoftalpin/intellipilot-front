import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/auth/presentation/auth_validators.dart';
import 'package:intellipilot/features/auth/presentation/cubits/reset_password_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:reactive_forms/reactive_forms.dart';

class ResetPasswordPage extends StatelessWidget {
  const ResetPasswordPage({super.key, this.initialToken});

  /// Token pre-filled from the email link (`/reset?token=...`).
  final String? initialToken;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ResetPasswordCubit>(
      create: (_) => ResetPasswordCubit(getIt<AuthRepository>()),
      child: _ResetPasswordView(initialToken: initialToken),
    );
  }
}

class _ResetPasswordView extends StatefulWidget {
  const _ResetPasswordView({this.initialToken});
  final String? initialToken;

  @override
  State<_ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<_ResetPasswordView> {
  late final FormGroup _form;

  @override
  void initState() {
    super.initState();
    _form = FormGroup({
      'token': FormControl<String>(
        value: widget.initialToken,
        validators: AuthValidators.resetToken,
      ),
      'password': FormControl<String>(validators: AuthValidators.password),
    });
  }

  void _submit() {
    if (!_form.valid) {
      _form.markAllAsTouched();
      return;
    }
    unawaited(
      context.read<ResetPasswordCubit>().submit(
        token: (_form.control('token').value as String).trim(),
        newPassword: _form.control('password').value as String,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.resetPasswordTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: BlocConsumer<ResetPasswordCubit, ResetPasswordState>(
              listener: (context, state) {
                if (state is ResetPasswordSucceeded) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t.resetPasswordSuccessSnack)),
                  );
                  context.goNamed('login');
                }
              },
              builder: (context, state) {
                final busy = state is ResetPasswordSubmitting;
                return ReactiveForm(
                  formGroup: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t.resetPasswordBody),
                      const SizedBox(height: 16),
                      ReactiveTextField<String>(
                        formControlName: 'token',
                        decoration: InputDecoration(
                          labelText: t.fieldResetToken,
                          prefixIcon: const Icon(Icons.vpn_key_outlined),
                        ),
                        validationMessages: {
                          ValidationMessage.required: (_) => t.errFieldRequired,
                        },
                      ),
                      const SizedBox(height: 12),
                      ReactiveTextField<String>(
                        formControlName: 'password',
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: t.fieldNewPassword,
                          prefixIcon: const Icon(Icons.lock_outline),
                          helperText: t.fieldPasswordHint,
                        ),
                        validationMessages: {
                          ValidationMessage.required: (_) => t.errFieldRequired,
                          ValidationMessage.minLength: (_) =>
                              t.errPasswordMinLength,
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
                            : Text(t.actionResetPassword),
                      ),
                      if (state is ResetPasswordFailed) ...[
                        const SizedBox(height: 16),
                        _ResetErrorBanner(failure: state.failure),
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

class _ResetErrorBanner extends StatelessWidget {
  const _ResetErrorBanner({required this.failure});
  final AppFailure failure;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context).colorScheme;
    final message = switch (failure) {
      ValidationFailure() => t.errWeakPassword,
      NetworkFailure() => t.errNetwork,
      ServerFailure() => t.errServer,
      _ => t.errResetTokenInvalid,
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
