import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';
import 'package:intellipilot/features/mfa/presentation/cubits/totp_setup_cubit.dart';
import 'package:intellipilot/features/mfa/presentation/widgets/recovery_codes_card.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class TotpSetupPage extends StatelessWidget {
  const TotpSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TotpSetupCubit>(
      create: (_) {
        final c = TotpSetupCubit(getIt<MfaRepository>());
        unawaited(c.start());
        return c;
      },
      child: const _TotpSetupView(),
    );
  }
}

class _TotpSetupView extends StatefulWidget {
  const _TotpSetupView();

  @override
  State<_TotpSetupView> createState() => _TotpSetupViewState();
}

class _TotpSetupViewState extends State<_TotpSetupView> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.totpSetupTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: BlocBuilder<TotpSetupCubit, TotpSetupState>(
              builder: (context, state) => switch (state) {
                TotpIdle() || TotpStarting() => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
                TotpAwaitingCode(:final start) => _SetupForm(
                  qrPngBase64: start.qrPngBase64,
                  secret: start.secretBase32,
                  codeController: _codeController,
                  busy: false,
                  failure: null,
                ),
                TotpConfirming(:final start) => _SetupForm(
                  qrPngBase64: start.qrPngBase64,
                  secret: start.secretBase32,
                  codeController: _codeController,
                  busy: true,
                  failure: null,
                ),
                TotpFailed(:final failure, :final start) =>
                  start == null
                      ? _SetupError(failure: failure)
                      : _SetupForm(
                          qrPngBase64: start.qrPngBase64,
                          secret: start.secretBase32,
                          codeController: _codeController,
                          busy: false,
                          failure: failure,
                        ),
                TotpEnabled(:final recoveryCodes) => _SetupDone(
                  codes: recoveryCodes,
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupForm extends StatelessWidget {
  const _SetupForm({
    required this.qrPngBase64,
    required this.secret,
    required this.codeController,
    required this.busy,
    required this.failure,
  });
  final String qrPngBase64;
  final String secret;
  final TextEditingController codeController;
  final bool busy;
  final AppFailure? failure;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final pngBytes = base64Decode(qrPngBase64);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.totpStep1),
        const SizedBox(height: 16),
        Center(
          child: Image.memory(
            pngBytes,
            width: 220,
            height: 220,
            gaplessPlayback: true,
          ),
        ),
        const SizedBox(height: 12),
        Text(t.totpManualEntry),
        const SizedBox(height: 4),
        _SecretBlock(secret: secret),
        const SizedBox(height: 24),
        Text(t.totpStep2),
        const SizedBox(height: 8),
        TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: t.totpCodeLabel,
            counterText: '',
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy
              ? null
              : () => context.read<TotpSetupCubit>().confirm(
                  codeController.text,
                ),
          child: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t.totpConfirmCta),
        ),
        if (failure != null) ...[
          const SizedBox(height: 12),
          Text(
            switch (failure!) {
              ValidationFailure() => t.totpInvalidCode,
              _ => t.errUnknown,
            },
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _SecretBlock extends StatelessWidget {
  const _SecretBlock({required this.secret});
  final String secret;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              secret,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: t.actionCopy,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: secret));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t.copiedToClipboard)),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SetupError extends StatelessWidget {
  const _SetupError({required this.failure});
  final AppFailure failure;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.error_outline,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 8),
        Text(t.totpStartFailed),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => context.read<TotpSetupCubit>().start(),
          child: Text(t.actionRetry),
        ),
      ],
    );
  }
}

class _SetupDone extends StatelessWidget {
  const _SetupDone({required this.codes});
  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.verified_user,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.totpEnabledTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(t.totpEnabledBody),
        const SizedBox(height: 16),
        RecoveryCodesCard(codes: codes),
        const SizedBox(height: 16),
        FilledButton.tonal(
          onPressed: () => context.goNamed('security'),
          child: Text(t.actionDone),
        ),
      ],
    );
  }
}
