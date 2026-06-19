import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/profile/presentation/cubits/password_change_cubit.dart';
import 'package:intellipilot/features/profile/presentation/cubits/profile_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Landing page for security-related sub-pages: password, TOTP, recovery
/// codes, passkeys, plus a destructive "disable 2FA" action.
class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final passkeysSupported = getIt<PasskeyService>().isSupported;
    final profileRepo = getIt<ProfileRepository>();
    return MultiBlocProvider(
      providers: [
        // Loaded so the password card can tell local accounts from LDAP ones.
        BlocProvider<ProfileCubit>(
          create: (_) {
            final c = ProfileCubit(
              repo: profileRepo,
              locale: getIt<LocaleCubit>(),
            );
            unawaited(c.load());
            return c;
          },
        ),
        BlocProvider<PasswordChangeCubit>(
          create: (_) => PasswordChangeCubit(
            repo: profileRepo,
            session: getIt<SessionBloc>(),
          ),
        ),
      ],
      child: Scaffold(
        appBar: AppBar(title: Text(t.securityTitle)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const _PasswordSection(),
                Text(
                  t.securitySection2fa,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(t.securityTotpTitle),
                    subtitle: Text(t.securityTotpSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(Routes.totpSetup),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: Text(t.securityRecoveryTitle),
                    subtitle: Text(t.securityRecoverySubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(Routes.recoveryCodes),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_open_outlined),
                    title: Text(t.securityDisableTotpTitle),
                    subtitle: Text(t.securityDisableTotpSubtitle),
                    onTap: () => _confirmDisable(context),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t.securitySectionPasskeys,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.fingerprint),
                    title: Text(t.securityPasskeysTitle),
                    subtitle: Text(
                      passkeysSupported
                          ? t.securityPasskeysSubtitle
                          : t.passkeysUnsupportedPlatform,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(Routes.passkeys),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDisable(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.securityDisableTotpTitle),
        content: Text(t.securityDisableTotpConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDisable),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final res = await getIt<MfaRepository>().disableTotp();
    if (!context.mounted) return;
    res.when(
      ok: (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.securityDisableTotpSnack)));
      },
      err: (_) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.errUnknown)));
      },
    );
  }
}

/// Password card + "change password" dialog. Local accounts only — LDAP users
/// authenticate against the directory, so the section is hidden for them.
class _PasswordSection extends StatelessWidget {
  const _PasswordSection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, profileState) {
        if (profileState is! ProfileLoaded || profileState.profile.isLdap) {
          return const SizedBox.shrink();
        }
        return BlocConsumer<PasswordChangeCubit, PasswordChangeState>(
          listenWhen: (prev, next) =>
              next is PasswordChangeSucceeded || next is PasswordChangeFailed,
          listener: (context, state) {
            final messenger = ScaffoldMessenger.of(context);
            if (state is PasswordChangeSucceeded) {
              messenger.showSnackBar(
                SnackBar(content: Text(t.changePasswordSuccessSnack)),
              );
            } else if (state is PasswordChangeFailed) {
              messenger.showSnackBar(
                SnackBar(content: Text(_messageFor(t, state.failure))),
              );
            }
          },
          builder: (context, state) {
            final busy = state is PasswordChangeRunning;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.securitySectionPassword,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.password),
                    title: Text(t.changePasswordTitle),
                    subtitle: Text(t.changePasswordBody),
                    trailing: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: busy ? null : () => _open(context),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        );
      },
    );
  }

  String _messageFor(AppLocalizations t, AppFailure failure) {
    if (failure is ValidationFailure) {
      final wrongCurrent = failure.fieldErrors.any(
        (e) => e.field == 'current_password',
      );
      return wrongCurrent ? t.errCurrentPasswordIncorrect : t.errWeakPassword;
    }
    return t.errUnknown;
  }

  Future<void> _open(BuildContext context) async {
    final cubit = context.read<PasswordChangeCubit>();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (result == null) return;
    await cubit.submit(currentPassword: result.$1, newPassword: result.$2);
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _confirmError;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final t = AppLocalizations.of(context);
    if (_current.text.isEmpty || _next.text.isEmpty) return;
    if (_next.text != _confirm.text) {
      setState(() => _confirmError = t.errPasswordsDoNotMatch);
      return;
    }
    Navigator.of(context).pop((_current.text, _next.text));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.changePasswordTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(labelText: t.fieldCurrentPassword),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _next,
            obscureText: true,
            decoration: InputDecoration(
              labelText: t.fieldNewPassword,
              helperText: t.fieldPasswordHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: t.fieldConfirmPassword,
              errorText: _confirmError,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(t.actionChangePassword)),
      ],
    );
  }
}
