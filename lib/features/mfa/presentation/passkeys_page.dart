import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/mfa/data/dtos/mfa_dtos.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';
import 'package:intellipilot/features/mfa/presentation/cubits/passkeys_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class PasskeysPage extends StatelessWidget {
  const PasskeysPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PasskeysCubit>(
      create: (_) => PasskeysCubit(
        repo: getIt<MfaRepository>(),
        passkeys: getIt<PasskeyService>(),
      )..load(),
      child: const _PasskeysView(),
    );
  }
}

class _PasskeysView extends StatelessWidget {
  const _PasskeysView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.passkeysPageTitle)),
      body: BlocBuilder<PasskeysCubit, PasskeysState>(
        builder: (context, state) {
          final cubit = context.read<PasskeysCubit>();
          if (state is PasskeysLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is PasskeysLoadFailed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.passkeysLoadFailed),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: cubit.load,
                    child: Text(t.actionRetry),
                  ),
                ],
              ),
            );
          }
          if (state is PasskeysLoaded) {
            return _Loaded(state: state, cubit: cubit);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.state, required this.cubit});
  final PasskeysLoaded state;
  final PasskeysCubit cubit;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(t.passkeysIntro),
            const SizedBox(height: 12),
            if (!cubit.isSupported)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.passkeysUnsupportedPlatform)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (state.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  t.passkeysEmpty,
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...state.items.map(
                (p) => _PasskeyTile(item: p, onDelete: () => cubit.remove(p.id)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (state.busy || !cubit.isSupported)
                  ? null
                  : () => _promptAdd(context, cubit),
              icon: const Icon(Icons.add_moderator),
              label: Text(t.actionAddPasskey),
            ),
            if (state.lastError != null) ...[
              const SizedBox(height: 12),
              Text(
                t.passkeyCeremonyFailed,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _promptAdd(BuildContext context, PasskeysCubit cubit) async {
    final t = AppLocalizations.of(context);
    final controller = TextEditingController();
    final nickname = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.passkeysAddDialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: t.passkeysNicknameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(t.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(t.actionContinue),
          ),
        ],
      ),
    );
    if (nickname == null) return;
    await cubit.add(nickname: nickname.isEmpty ? null : nickname);
  }
}

class _PasskeyTile extends StatelessWidget {
  const _PasskeyTile({required this.item, required this.onDelete});
  final PasskeyListItem item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.fingerprint),
        title: Text(item.nickname.isEmpty ? t.passkeyNoNickname : item.nickname),
        subtitle: Text(
          item.lastUsedAt == null
              ? t.passkeyNeverUsed
              : t.passkeyLastUsed(item.lastUsedAt!.toLocal().toString()),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: t.actionDelete,
          onPressed: onDelete,
        ),
      ),
    );
  }
}
