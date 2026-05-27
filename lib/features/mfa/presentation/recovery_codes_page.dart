import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';
import 'package:intellipilot/features/mfa/presentation/cubits/recovery_codes_cubit.dart';
import 'package:intellipilot/features/mfa/presentation/widgets/recovery_codes_card.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class RecoveryCodesPage extends StatelessWidget {
  const RecoveryCodesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RecoveryCodesCubit>(
      create: (_) => RecoveryCodesCubit(getIt<MfaRepository>()),
      child: const _RecoveryView(),
    );
  }
}

class _RecoveryView extends StatelessWidget {
  const _RecoveryView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.recoveryCodesPageTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: BlocBuilder<RecoveryCodesCubit, RecoveryCodesState>(
              builder: (context, state) => switch (state) {
                RecoveryIdle() => const _RegenerateCta(busy: false),
                RecoveryRegenerating() => const _RegenerateCta(busy: true),
                RecoveryRevealed(:final codes) => RecoveryCodesCard(
                  codes: codes,
                ),
                RecoveryFailed() => Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      t.recoveryRegenerateFailed,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () =>
                          context.read<RecoveryCodesCubit>().regenerate(),
                      child: Text(t.actionRetry),
                    ),
                  ],
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RegenerateCta extends StatelessWidget {
  const _RegenerateCta({required this.busy});
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.recoveryRegenerateBody),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy
              ? null
              : () => context.read<RecoveryCodesCubit>().regenerate(),
          child: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t.actionRegenerateCodes),
        ),
      ],
    );
  }
}
