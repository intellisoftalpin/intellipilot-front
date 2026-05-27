import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Landing page for security-related sub-pages: TOTP, recovery codes,
/// passkeys, plus a destructive "disable 2FA" action.
class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final passkeysSupported = getIt<PasskeyService>().isSupported;
    return Scaffold(
      appBar: AppBar(title: Text(t.securityTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.securityDisableTotpSnack)),
        );
      },
      err: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.errUnknown)),
        );
      },
    );
  }
}
