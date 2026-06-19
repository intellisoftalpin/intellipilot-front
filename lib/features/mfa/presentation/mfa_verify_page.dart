import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/mfa/presentation/cubits/mfa_verify_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

class MfaVerifyPage extends StatelessWidget {
  const MfaVerifyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MfaVerifyCubit>(
      create: (_) => MfaVerifyCubit(
        repo: getIt<AuthRepository>(),
        session: getIt<SessionBloc>(),
      ),
      child: const _MfaVerifyView(),
    );
  }
}

class _MfaVerifyView extends StatefulWidget {
  const _MfaVerifyView();

  @override
  State<_MfaVerifyView> createState() => _MfaVerifyViewState();
}

class _MfaVerifyViewState extends State<_MfaVerifyView> {
  final _codeController = TextEditingController();
  String _method = 'totp';

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit(SessionState session) {
    if (session is! SessionMfaRequired) return;
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    unawaited(
      context.read<MfaVerifyCubit>().submit(
        mfaToken: session.mfaToken,
        method: _method,
        code: code,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = context.watch<SessionBloc>().state;
    if (session is! SessionMfaRequired) {
      return Scaffold(
        body: Center(child: Text(t.mfaContextLost)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(t.mfaVerifyTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: BlocBuilder<MfaVerifyCubit, MfaVerifyState>(
              builder: (context, state) {
                final busy = state is MfaSubmitting;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t.mfaVerifyBody),
                    const SizedBox(height: 16),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'totp',
                          label: Text(t.mfaMethodTotp),
                          icon: const Icon(Icons.timer_outlined),
                        ),
                        ButtonSegment(
                          value: 'recovery',
                          label: Text(t.mfaMethodRecovery),
                          icon: const Icon(Icons.key_outlined),
                        ),
                      ],
                      selected: {_method},
                      onSelectionChanged: (s) {
                        setState(() {
                          _method = s.first;
                          _codeController.clear();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _codeController,
                      keyboardType: _method == 'totp'
                          ? TextInputType.number
                          : TextInputType.text,
                      maxLength: _method == 'totp' ? 6 : 32,
                      decoration: InputDecoration(
                        labelText: _method == 'totp'
                            ? t.totpCodeLabel
                            : t.mfaRecoveryCodeLabel,
                        counterText: '',
                      ),
                      inputFormatters: _method == 'totp'
                          ? [FilteringTextInputFormatter.digitsOnly]
                          : null,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : () => _submit(session),
                      child: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(t.actionVerify),
                    ),
                    if (state is MfaFailed) ...[
                      const SizedBox(height: 16),
                      Text(
                        switch (state.failure) {
                          UnauthorizedFailure() => t.mfaInvalidCode,
                          NetworkFailure() => t.errNetwork,
                          ServerFailure() => t.errServer,
                          _ => t.errUnknown,
                        },
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => getIt<SessionBloc>().add(
                        const SessionLogoutRequested(callBackend: false),
                      ),
                      child: Text(t.actionCancelMfa),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
