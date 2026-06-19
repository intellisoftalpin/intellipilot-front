import 'dart:async';

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
          create: (_) {
            final c = ProfileCubit(
              repo: profileRepo,
              locale: getIt<LocaleCubit>(),
            );
            unawaited(c.load());
            return c;
          },
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

class _ExportSection extends StatelessWidget {
  const _ExportSection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocConsumer<GdprExportCubit, GdprExportState>(
      listenWhen: (prev, next) => next is GdprDownloaded || next is GdprFailed,
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t.gdprExportFailed)));
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
                  icon: Icon(cubit.canDownload ? Icons.download : Icons.copy),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colors.onErrorContainer),
            ),
            const SizedBox(height: 8),
            Text(t.accountDeleteBody),
            const SizedBox(height: 12),
            BlocConsumer<AccountDeletionCubit, AccountDeletionState>(
              listenWhen: (prev, next) => next is AccountDeletionScheduled,
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
              decoration: InputDecoration(hintText: username),
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
