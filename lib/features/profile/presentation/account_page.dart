import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/io/file_downloader.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/profile/presentation/cubits/account_deletion_cubit.dart';
import 'package:intellipilot/features/profile/presentation/cubits/gdpr_export_cubit.dart';
import 'package:intellipilot/features/profile/presentation/cubits/password_change_cubit.dart';
import 'package:intellipilot/features/profile/presentation/cubits/profile_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final profileRepo = getIt<ProfileRepository>();
    return MultiBlocProvider(
      providers: [
        // Reuse ProfileCubit so we have the username available for the
        // delete confirmation; loads on entry.
        BlocProvider<ProfileCubit>(
          create: (_) =>
              ProfileCubit(repo: profileRepo, locale: getIt<LocaleCubit>())
                ..load(),
        ),
        BlocProvider<PasswordChangeCubit>(
          create: (_) => PasswordChangeCubit(
            repo: profileRepo,
            session: getIt<SessionBloc>(),
          ),
        ),
        BlocProvider<AccountDeletionCubit>(
          create: (_) => AccountDeletionCubit(
            repo: profileRepo,
            session: getIt<SessionBloc>(),
          ),
        ),
        BlocProvider<GdprExportCubit>(
          create: (_) => GdprExportCubit(
            repo: profileRepo,
            downloader: getIt<FileDownloader>(),
          ),
        ),
      ],
      child: const _AccountView(),
    );
  }
}

class _AccountView extends StatelessWidget {
  const _AccountView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.accountTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: const [
              _ChangePasswordSection(),
              _ExportSection(),
              SizedBox(height: 24),
              _DeleteSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordSection extends StatelessWidget {
  const _ChangePasswordSection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, profileState) {
        // Local accounts only. LDAP users authenticate against the directory,
        // so there's no local password to change — hide the section for them.
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t.changePasswordTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(t.changePasswordBody),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: busy ? null : () => _open(context),
                          icon: const Icon(Icons.password),
                          label: busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(t.actionChangePassword),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
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
        FilledButton(
          onPressed: _submit,
          child: Text(t.actionChangePassword),
        ),
      ],
    );
  }
}

class _ExportSection extends StatelessWidget {
  const _ExportSection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocConsumer<GdprExportCubit, GdprExportState>(
      listenWhen: (prev, next) =>
          next is GdprDownloaded || next is GdprFailed,
      listener: (context, state) {
        if (state is GdprDownloaded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.viaClipboard
                    ? t.gdprExportClipboardSnack
                    : t.gdprExportDownloadedSnack,
              ),
            ),
          );
        } else if (state is GdprFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.gdprExportFailed)),
          );
        }
      },
      builder: (context, state) {
        final busy = state is GdprRunning;
        final cubit = context.read<GdprExportCubit>();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.gdprExportTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  cubit.canDownload
                      ? t.gdprExportBodyWeb
                      : t.gdprExportBodyNative,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy ? null : cubit.run,
                  icon: Icon(
                    cubit.canDownload ? Icons.download : Icons.copy,
                  ),
                  label: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(t.gdprExportCta),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DeleteSection extends StatelessWidget {
  const _DeleteSection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.accountDangerZoneTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.onErrorContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(t.accountDeleteBody),
            const SizedBox(height: 12),
            BlocConsumer<AccountDeletionCubit, AccountDeletionState>(
              listenWhen: (prev, next) =>
                  next is AccountDeletionScheduled,
              listener: (context, state) {
                if (state is AccountDeletionScheduled) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        t.accountDeletedSnack(
                          state.graceUntil.toLocal().toString(),
                        ),
                      ),
                    ),
                  );
                }
              },
              builder: (context, state) {
                final busy = state is AccountDeletionRunning;
                return FilledButton.tonalIcon(
                  icon: const Icon(Icons.delete_forever),
                  onPressed: busy ? null : () => _confirm(context),
                  label: Text(t.actionDeleteAccount),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final profileState = context.read<ProfileCubit>().state;
    if (profileState is! ProfileLoaded) return;
    final username = profileState.profile.username;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.accountDeleteDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.accountDeleteDialogBody),
            const SizedBox(height: 12),
            Text(
              t.accountDeleteDialogTypeUsername(username),
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: username,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDeleteAccount),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AccountDeletionCubit>().deleteAccount(
      typedConfirmation: controller.text,
      expectedUsername: username,
    );

    if (!context.mounted) return;
    final state = context.read<AccountDeletionCubit>().state;
    if (state is AccountDeletionFailed) {
      final failure = state.failure;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failure is ValidationFailure
                ? t.accountDeleteUsernameMismatch
                : t.errUnknown,
          ),
        ),
      );
    }
  }
}
