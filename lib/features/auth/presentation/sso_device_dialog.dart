import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/data/dtos/sso_dtos.dart';
import 'package:intellipilot/features/auth/domain/sso_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// How this dialog ended.
sealed class SsoDeviceOutcome {
  const SsoDeviceOutcome();
}

/// Signed in — the caller establishes the session.
final class SsoDeviceOutcomeSignedIn extends SsoDeviceOutcome {
  const SsoDeviceOutcomeSignedIn(this.tokens);
  final TokenResponse tokens;
}

/// An identity was connected to the already-signed-in account.
final class SsoDeviceOutcomeLinked extends SsoDeviceOutcome {
  const SsoDeviceOutcomeLinked();
}

/// The user closed the dialog, or the attempt failed.
final class SsoDeviceOutcomeAbandoned extends SsoDeviceOutcome {
  const SsoDeviceOutcomeAbandoned({this.failure});
  final AppFailure? failure;
}

/// Runs the device-code flow for desktop and mobile.
///
/// The whole exchange is brokered by the server: this dialog only shows the
/// code the human must type at their identity provider and polls one endpoint
/// until the server says the sign-in completed. It never holds a credential
/// that is valid at the provider.
///
/// [link] switches from signing in to connecting a provider to the account
/// that is already signed in.
Future<SsoDeviceOutcome?> showSsoDeviceDialog(
  BuildContext context, {
  required SsoProvider provider,
  bool link = false,
}) => showDialog<SsoDeviceOutcome>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SsoDeviceDialog(provider: provider, link: link),
);

class _SsoDeviceDialog extends StatefulWidget {
  const _SsoDeviceDialog({required this.provider, required this.link});

  final SsoProvider provider;
  final bool link;

  @override
  State<_SsoDeviceDialog> createState() => _SsoDeviceDialogState();
}

class _SsoDeviceDialogState extends State<_SsoDeviceDialog> {
  final _repo = getIt<SsoRepository>();

  SsoDeviceStart? _start;
  AppFailure? _failure;
  Timer? _poller;
  Timer? _countdown;
  int _secondsLeft = 0;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_begin());
  }

  @override
  void dispose() {
    _closed = true;
    _poller?.cancel();
    _countdown?.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    final result = widget.link
        ? await _repo.startDeviceLink(widget.provider.slug)
        : await _repo.startDeviceSignIn(widget.provider.slug);
    if (_closed) return;
    result.when(
      ok: (start) {
        setState(() {
          _start = start;
          _secondsLeft = start.expiresIn;
        });
        _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
          if (_closed) return;
          setState(
            () => _secondsLeft = _secondsLeft > 0 ? _secondsLeft - 1 : 0,
          );
          if (_secondsLeft == 0) {
            t.cancel();
            _poller?.cancel();
          }
        });
        // The server enforces this interval and answers 429 if we ignore it,
        // so it is honoured rather than chosen here.
        _poller = Timer.periodic(
          Duration(seconds: start.interval),
          (_) => unawaited(_poll(start.pollToken)),
        );
      },
      err: (f) => setState(() => _failure = f),
    );
  }

  Future<void> _poll(String pollToken) async {
    if (_closed) return;
    final result = await _repo.pollDevice(pollToken);
    if (_closed || !mounted) return;
    result.when(
      ok: (poll) {
        switch (poll) {
          case SsoDevicePending():
            // Still waiting on the human. Nothing to do.
            break;
          case SsoDeviceSignedIn(:final tokens):
            _finish(SsoDeviceOutcomeSignedIn(tokens));
          case SsoDeviceLinked():
            _finish(const SsoDeviceOutcomeLinked());
        }
      },
      err: (f) {
        // A rate-limit answer means we polled early; keep waiting rather than
        // tearing down a sign-in the user may be halfway through.
        if (f.problem?.status == 429) return;
        _poller?.cancel();
        setState(() => _failure = f);
      },
    );
  }

  void _finish(SsoDeviceOutcome outcome) {
    _poller?.cancel();
    _countdown?.cancel();
    _closed = true;
    Navigator.of(context).pop(outcome);
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // Best effort: the code and URL are on screen either way.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final start = _start;

    return AlertDialog(
      title: Text(
        widget.link
            ? t.ssoConnectDialogTitle(widget.provider.displayName)
            : t.ssoSignInDialogTitle(widget.provider.displayName),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_failure != null)
              Text(
                _failure!.serverMessage ?? t.errUnknown,
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (start == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Text(t.ssoDeviceInstructions, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              _CodeBlock(code: start.userCode),
              const SizedBox(height: 16),
              Text(t.ssoDeviceOpenThisPage, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(
                start.verificationUri,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(t.ssoDeviceOpenBrowser),
                      onPressed: () => unawaited(
                        _open(
                          start.verificationUriComplete ??
                              start.verificationUri,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: t.actionCopy,
                    icon: const Icon(Icons.copy_all_outlined),
                    onPressed: () => unawaited(
                      Clipboard.setData(
                        ClipboardData(text: start.verificationUri),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _secondsLeft > 0
                          ? t.ssoDeviceWaiting(_formatRemaining(_secondsLeft))
                          : t.ssoDeviceExpired,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(SsoDeviceOutcomeAbandoned(failure: _failure)),
          child: Text(t.actionCancel),
        ),
      ],
    );
  }
}

String _formatRemaining(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The user code, spaced out and monospaced so it can be read aloud or typed
/// without transcription errors.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: SelectableText(
          code,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontFamily: 'monospace',
            letterSpacing: 4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
