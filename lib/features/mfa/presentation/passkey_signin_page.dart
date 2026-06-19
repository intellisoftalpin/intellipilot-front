import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/auth/presentation/auth_validators.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';
import 'package:intellipilot/features/mfa/presentation/cubits/passkey_signin_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:reactive_forms/reactive_forms.dart';

class PasskeySignInPage extends StatelessWidget {
  const PasskeySignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PasskeySignInCubit>(
      create: (_) => PasskeySignInCubit(
        repo: getIt<MfaRepository>(),
        passkeys: getIt<PasskeyService>(),
        session: getIt<SessionBloc>(),
      ),
      child: const _PasskeySignInView(),
    );
  }
}

class _PasskeySignInView extends StatefulWidget {
  const _PasskeySignInView();

  @override
  State<_PasskeySignInView> createState() => _PasskeySignInViewState();
}

class _PasskeySignInViewState extends State<_PasskeySignInView> {
  late final FormGroup _form;

  @override
  void initState() {
    super.initState();
    _form = FormGroup({
      'email': FormControl<String>(validators: AuthValidators.email),
    });
  }

  void _submit() {
    if (!_form.valid) {
      _form.markAllAsTouched();
      return;
    }
    unawaited(
      context.read<PasskeySignInCubit>().signIn(
        _form.control('email').value as String,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.passkeySignInTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: BlocBuilder<PasskeySignInCubit, PasskeySignInState>(
              builder: (context, state) {
                final cubit = context.read<PasskeySignInCubit>();
                if (!cubit.isSupported) {
                  return _UnsupportedNotice();
                }
                final busy = state is PasskeySignInRunning;
                return ReactiveForm(
                  formGroup: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t.passkeySignInBody),
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
                          ValidationMessage.email: (_) => t.errEmailInvalid,
                        },
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.fingerprint),
                        onPressed: busy ? null : _submit,
                        label: busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(t.actionContinueWithPasskey),
                      ),
                      if (state is PasskeySignInFailed) ...[
                        const SizedBox(height: 16),
                        Text(
                          switch (state.failure) {
                            UnauthorizedFailure() => t.passkeySignInUnauthorized,
                            NetworkFailure() => t.errNetwork,
                            ServerFailure() => t.errServer,
                            _ => t.passkeyCeremonyFailed,
                          },
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

class _UnsupportedNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.warning_amber,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 8),
        Text(t.passkeysUnsupportedPlatform, textAlign: TextAlign.center),
      ],
    );
  }
}
