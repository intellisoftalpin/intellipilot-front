import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/network/server_connection_service.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/network/tls/cert_trust.dart';
import 'package:intellipilot/features/accounts/domain/account_switcher.dart';
import 'package:intellipilot/features/accounts/presentation/add_account_notice.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Step ① of the sign-in wizard on desktop and mobile: which server?
///
/// Web never reaches this — it is served by its own instance, so there is
/// nothing to choose. The route is not even registered there.
///
/// Nothing is persisted until the address has been validated against a live
/// `/api/v1/auth/config`, so a typo cannot leave the app pointing at a host
/// that will only fail later, at the login screen, with a worse error.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _prefilled = false;
  ConnectResult? _result;

  /// Whether this is step ① of adding a *second* account rather than changing
  /// the server for the only one.
  ///
  /// Read from the route rather than passed in, so a deep link or a restored
  /// location behaves the same as the menu item. Tolerates the absence of a
  /// GoRouter ancestor for the benefit of widget tests that pump the page bare.
  bool get _addingAccount {
    final router = GoRouter.maybeOf(context);
    if (router == null) return false;
    return Routes.isAddAccount(router.routerDelegate.currentConfiguration.uri);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    // Prefill with the current server so "change server" is an edit, not a
    // retype — but NOT when adding an account: that server is the one the user
    // is already on, and the whole reason for this step is entering a
    // different one. Prefilling it invited exactly the mistake of signing in
    // to the same place twice.
    //
    // In `didChangeDependencies` rather than `initState` because reading the
    // router needs an inherited-widget lookup.
    if (!_addingAccount) {
      _controller.text = getIt<ServerEndpoint>().stored ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit({bool trustCertificate = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (!trustCertificate) _result = null;
    });
    final adding = _addingAccount;
    final router = GoRouter.of(context);
    final res = await getIt<ServerConnectionService>().connect(
      _controller.text,
      trustCertificate: trustCertificate,
      addingAccount: adding,
      // Only runs once the address is known good. Stands the current account
      // down so the app never holds its token while pointed at the new server.
      suspendActive: adding
          ? () => getIt<AccountSwitcher>().beginAddAccount(
              currentRoute: router.routerDelegate.currentConfiguration.uri
                  .toString(),
            )
          : null,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = res;
    });
    if (res.isOk) {
      // Branding and the compatibility verdict are invalidated by the service's
      // own server-changed hook — see `invalidateServerDerivedState` in the DI
      // wiring. Doing it here too meant an account switch, which does not go
      // through this page, silently skipped it.
      context.go(adding ? Routes.addAccountLogin() : Routes.login);
    }
  }

  String? _errorFor(AppLocalizations t) => switch (_result?.outcome) {
    ConnectOutcome.invalidUrl => t.connectErrInvalid,
    ConnectOutcome.unreachable => t.connectErrUnreachable,
    ConnectOutcome.notIntelliPilot => t.connectErrNotIntellipilot,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final normalised = ServerConnectionService.normalise(_controller.text);
    final cleartext =
        normalised != null && ServerConnectionService.isCleartext(normalised);
    final cert = _result?.outcome == ConnectOutcome.untrustedCertificate
        ? _result?.cert
        : null;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Adding a second account: say so, and give a way out. The
                  // user is still signed in, so a wizard with no exit is a trap.
                  if (_addingAccount) ...[
                    const AddAccountNotice(),
                    const SizedBox(height: 24),
                  ],
                  Icon(
                    Icons.dns_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.connectTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.connectSubtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: t.connectFieldLabel,
                      hintText: t.connectFieldHint,
                      prefixIcon: const Icon(Icons.link),
                      errorText: _errorFor(t),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => unawaited(_submit()),
                  ),
                  if (cleartext) ...[
                    const SizedBox(height: 12),
                    _Notice(
                      icon: Icons.lock_open_outlined,
                      text: t.connectCleartextWarning,
                      tone: theme.colorScheme.error,
                    ),
                  ],
                  if (cert != null) ...[
                    const SizedBox(height: 16),
                    _CertCard(
                      cert: cert,
                      onTrust: () => _submit(trustCertificate: true),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : () => unawaited(_submit()),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(t.connectAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.tone});
  final IconData icon;
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tone),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: tone),
          ),
        ),
      ],
    );
  }
}

/// The certificate the platform refused, with everything needed to decide
/// whether to trust it. Trusting pins this exact certificate for this exact
/// host — see [CertPinStore].
class _CertCard extends StatelessWidget {
  const _CertCard({required this.cert, required this.onTrust});
  final CertInfo cert;
  final VoidCallback onTrust;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.gpp_maybe_outlined,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  t.connectCertTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t.connectCertBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            if (cert.isExpired) ...[
              const SizedBox(height: 6),
              Text(
                t.connectCertExpired,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _Field(label: t.connectCertSubject, value: cert.subject),
            _Field(label: t.connectCertIssuer, value: cert.issuer),
            _Field(
              label: t.connectCertValid,
              value:
                  '${cert.validFrom.toIso8601String().split('T').first}'
                  ' — ${cert.validTo.toIso8601String().split('T').first}',
            ),
            _Field(
              label: t.connectCertFingerprint,
              value: cert.sha256,
              mono: true,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onTrust,
              icon: const Icon(Icons.verified_user_outlined, size: 18),
              label: Text(t.connectCertTrust),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.mono = false});
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onErrorContainer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg.withValues(alpha: 0.7),
            ),
          ),
          SelectableText(
            value,
            style:
                (mono
                        ? theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'JetBrains Mono',
                          )
                        : theme.textTheme.bodySmall)
                    ?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
