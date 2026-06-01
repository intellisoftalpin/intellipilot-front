import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/auth/presentation/auth_validators.dart';
import 'package:intellipilot/features/auth/presentation/cubits/register_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:reactive_forms/reactive_forms.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key, this.invitationToken});

  /// Optional `?token=` query param from a platform invitation link.
  final String? invitationToken;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RegisterCubit>(
      create: (_) => RegisterCubit(getIt<AuthRepository>()),
      child: _RegisterView(invitationToken: invitationToken),
    );
  }
}

class _RegisterView extends StatefulWidget {
  const _RegisterView({this.invitationToken});

  final String? invitationToken;

  @override
  State<_RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<_RegisterView> {
  late final FormGroup _form;

  @override
  void initState() {
    super.initState();
    _form = FormGroup({
      'email': FormControl<String>(validators: AuthValidators.email),
      'username': FormControl<String>(validators: AuthValidators.username),
      'fullName': FormControl<String>(validators: AuthValidators.fullName),
      'password': FormControl<String>(validators: AuthValidators.password),
    });
  }

  void _submit() {
    if (!_form.valid) {
      _form.markAllAsTouched();
      return;
    }
    context.read<RegisterCubit>().submit(
      email: _form.control('email').value as String,
      username: _form.control('username').value as String,
      fullName: (_form.control('fullName').value as String?) ?? '',
      password: _form.control('password').value as String,
      invitationToken: widget.invitationToken,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.registerTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: BlocConsumer<RegisterCubit, RegisterState>(
              listener: (context, state) {
                if (state is RegisterSucceeded) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t.registerSuccessSnack)),
                  );
                  context.goNamed('login');
                }
              },
              builder: (context, state) {
                final busy = state is RegisterSubmitting;
                return ReactiveForm(
                  formGroup: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ReactiveTextField<String>(
                        formControlName: 'email',
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: t.fieldEmail,
                          prefixIcon: const Icon(Icons.alternate_email),
                        ),
                        validationMessages: _emailMessages(t),
                      ),
                      const SizedBox(height: 12),
                      ReactiveTextField<String>(
                        formControlName: 'username',
                        decoration: InputDecoration(
                          labelText: t.fieldUsername,
                          prefixIcon: const Icon(Icons.person_outline),
                          helperText: t.fieldUsernameHint,
                        ),
                        validationMessages: _usernameMessages(t),
                      ),
                      const SizedBox(height: 12),
                      ReactiveTextField<String>(
                        formControlName: 'fullName',
                        decoration: InputDecoration(
                          labelText: t.fieldFullName,
                          prefixIcon: const Icon(Icons.badge_outlined),
                        ),
                        validationMessages: {
                          ValidationMessage.maxLength: (_) => t.errTooLong,
                        },
                      ),
                      const SizedBox(height: 12),
                      ReactiveTextField<String>(
                        formControlName: 'password',
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: t.fieldPassword,
                          prefixIcon: const Icon(Icons.lock_outline),
                          helperText: t.fieldPasswordHint,
                        ),
                        validationMessages: _passwordMessages(t),
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
                            : Text(t.actionRegister),
                      ),
                      const SizedBox(height: 16),
                      if (state is RegisterFailed)
                        _RegisterErrorBanner(failure: state.failure),
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

  Map<String, ValidationMessageFunction> _emailMessages(AppLocalizations t) => {
    ValidationMessage.required: (_) => t.errFieldRequired,
    ValidationMessage.email: (_) => t.errEmailInvalid,
    ValidationMessage.maxLength: (_) => t.errTooLong,
  };

  Map<String, ValidationMessageFunction> _usernameMessages(
    AppLocalizations t,
  ) => {
    ValidationMessage.required: (_) => t.errFieldRequired,
    ValidationMessage.minLength: (_) => t.errUsernameTooShort,
    ValidationMessage.maxLength: (_) => t.errTooLong,
    ValidationMessage.pattern: (_) => t.errUsernamePattern,
  };

  Map<String, ValidationMessageFunction> _passwordMessages(
    AppLocalizations t,
  ) => {
    ValidationMessage.required: (_) => t.errFieldRequired,
    ValidationMessage.minLength: (_) => t.errPasswordMinLength,
    ValidationMessage.maxLength: (_) => t.errTooLong,
  };
}

class _RegisterErrorBanner extends StatelessWidget {
  const _RegisterErrorBanner({required this.failure});
  final AppFailure failure;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context).colorScheme;
    // Some platform-invite / closed-registration cases come back as
    // ForbiddenFailure with a problem.type slug; surface a precise message.
    final problemType = failure.problem?.type;
    final message = switch (problemType) {
      'registration_closed' =>
        'Registration is invite-only. Ask your administrator for an invitation link.',
      'invitation_invalid' =>
        'This invitation link is not recognised. Ask your administrator for a new one.',
      'invitation_consumed' =>
        'This invitation has already been used or has expired. Ask your administrator for a new one.',
      'invitation_email_mismatch' =>
        'The email you entered does not match the invitation. Use the email the invitation was sent to.',
      _ => switch (failure) {
        ConflictFailure() => t.errEmailOrUsernameTaken,
        ValidationFailure() => t.errWeakPassword,
        NetworkFailure() => t.errNetwork,
        ServerFailure() => t.errServer,
        _ => t.errUnknown,
      },
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
