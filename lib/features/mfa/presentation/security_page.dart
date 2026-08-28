import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/l10n/locale_cubit.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/ui/full_page_navigation.dart';
import 'package:intellipilot/features/auth/data/dtos/sso_dtos.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/auth/domain/sso_repository.dart';
import 'package:intellipilot/features/auth/presentation/sso_device_dialog.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/personal_token_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/profile/presentation/cubits/password_change_cubit.dart';
import 'package:intellipilot/features/profile/presentation/cubits/personal_token_cubit.dart';
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
        BlocProvider<PersonalTokenCubit>(
          create: (_) {
            final c = PersonalTokenCubit(profileRepo);
            unawaited(c.load());
            return c;
          },
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
                const SizedBox(height: 16),
                const _SsoSection(),
                const SizedBox(height: 16),
                const _PersonalTokenSection(),
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

/// Password card + "change password" dialog.
///
/// Local accounts only. An LDAP user's password lives in the directory and a
/// single-sign-on account has none at all, so for both the section is hidden —
/// the server refuses the endpoint for either, and offering a form that can
/// only fail helps nobody.
class _PasswordSection extends StatelessWidget {
  const _PasswordSection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, profileState) {
        if (profileState is! ProfileLoaded ||
            profileState.profile.isExternallyAuthenticated) {
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

/// Personal app token card: generate / reset / disable / enable / delete, with
/// the one-time secret shown in a copy dialog after generate/reset.
class _PersonalTokenSection extends StatelessWidget {
  const _PersonalTokenSection();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocConsumer<PersonalTokenCubit, PersonalTokenState>(
      listenWhen: (prev, next) =>
          next is PersonalTokenLoaded && next.lastError != null,
      listener: (context, state) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.errUnknown)));
      },
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.personalTokenSection,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(child: _body(context, t, state)),
          ],
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations t,
    PersonalTokenState state,
  ) {
    switch (state) {
      case PersonalTokenLoading():
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case PersonalTokenFailed():
        return ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(t.personalTokenLoadFailed),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<PersonalTokenCubit>().load(),
          ),
        );
      case PersonalTokenLoaded(:final token, :final busy):
        if (token == null) {
          return ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text(t.personalTokenTitle),
            subtitle: Text(t.personalTokenSubtitle),
            trailing: FilledButton.tonal(
              onPressed: busy ? null : () => _create(context),
              child: Text(t.personalTokenGenerate),
            ),
          );
        }
        return _TokenTile(token: token, busy: busy);
    }
  }

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<PersonalTokenCubit>();
    final result = await cubit.create();
    if (result != null && context.mounted) {
      await _showTokenSecret(context, result.secret);
    }
  }
}

class _TokenTile extends StatelessWidget {
  const _TokenTile({required this.token, required this.busy});
  final PersonalTokenDto token;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dates = MaterialLocalizations.of(context);
    final lastUsed = token.lastUsedAt == null
        ? t.personalTokenNeverUsed
        : t.personalTokenLastUsed(dates.formatShortDate(token.lastUsedAt!));
    return ListTile(
      leading: Icon(
        token.isDisabled ? Icons.key_off_outlined : Icons.vpn_key_outlined,
      ),
      title: Row(
        children: [
          Text(token.masked, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: token.isDisabled
                  ? scheme.errorContainer
                  : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              token.isDisabled ? t.personalTokenDisabled : t.appTokenActive,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
      subtitle: Text(
        '${t.personalTokenCreated(dates.formatShortDate(token.createdAt))}'
        ' · $lastUsed',
      ),
      trailing: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<String>(
              onSelected: (action) => _onAction(context, action),
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'reset',
                  child: Text(t.personalTokenReset),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(
                    token.isDisabled ? t.actionEnable : t.actionDisable,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(t.actionDelete),
                ),
              ],
            ),
    );
  }

  Future<void> _onAction(BuildContext context, String action) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<PersonalTokenCubit>();
    switch (action) {
      case 'reset':
        final ok = await _confirm(
          context,
          title: t.personalTokenReset,
          body: t.personalTokenResetConfirm,
          confirmLabel: t.personalTokenReset,
        );
        if (!ok) return;
        final result = await cubit.reset();
        if (result != null && context.mounted) {
          await _showTokenSecret(context, result.secret);
        }
      case 'toggle':
        await cubit.setDisabled(disabled: !token.isDisabled);
      case 'delete':
        final ok = await _confirm(
          context,
          title: t.actionDelete,
          body: t.personalTokenDeleteConfirm,
          confirmLabel: t.actionDelete,
        );
        if (!ok) return;
        await cubit.delete();
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}

/// Shows the one-time raw secret with a copy button.
Future<void> _showTokenSecret(BuildContext context, String secret) {
  final t = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(t.appTokenSecretTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.appTokenSecretWarning),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              secret,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: Text(t.appTokenCopy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: secret));
            if (ctx.mounted) {
              ScaffoldMessenger.of(
                ctx,
              ).showSnackBar(SnackBar(content: Text(t.appTokenCopied)));
            }
          },
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(t.actionDone),
        ),
      ],
    ),
  );
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

/// Connected single-sign-on providers.
///
/// This is the self-service half of account linking. An SSO sign-in never
/// links itself to an existing account by email — an identity provider can
/// assert any address, and auto-linking on one would turn that into an account
/// takeover. So the user proves both sides instead: they are signed in here,
/// and they complete a flow at the provider. Nothing else establishes the
/// binding.
///
/// The whole section stays hidden when the deployment has no provider
/// configured, which is every install until an administrator sets one up.
class _SsoSection extends StatefulWidget {
  const _SsoSection();

  @override
  State<_SsoSection> createState() => _SsoSectionState();
}

class _SsoSectionState extends State<_SsoSection> {
  final _repo = getIt<SsoRepository>();

  List<SsoIdentity>? _identities;
  List<SsoProvider> _providers = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final config = await getIt<AuthRepository>().authConfig();
    final identities = await _repo.listIdentities();
    if (!mounted) return;
    setState(() {
      _providers = config.valueOrNull?.ssoProviders ?? const [];
      _identities = identities.valueOrNull ?? const [];
    });
  }

  Future<void> _connect(SsoProvider provider) async {
    final t = AppLocalizations.of(context);
    if (kIsWeb) {
      // Same round trip as signing in: leave the app, come back to the
      // server's callback, which binds the identity and returns us here.
      final base = getIt<ApiConfig>().baseUrl.replaceAll(RegExp(r'/+$'), '');
      final back = Uri.encodeQueryComponent(Routes.security);
      navigateWholePage(
        '$base/api/v1/me/oidc/${provider.slug}/link/start?redirect_to=$back',
      );
      return;
    }
    final outcome = await showSsoDeviceDialog(
      context,
      provider: provider,
      link: true,
    );
    if (!mounted) return;
    if (outcome is SsoDeviceOutcomeLinked) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.ssoLinkedSnack)));
      await _load();
    } else if (outcome is SsoDeviceOutcomeAbandoned &&
        outcome.failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(outcome.failure!.serverMessage ?? t.errUnknown)),
      );
    }
  }

  Future<void> _disconnect(SsoIdentity identity) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.ssoDisconnectTitle),
        content: Text(t.ssoDisconnectConfirm(identity.providerDisplayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.ssoDisconnectAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final res = await _repo.unlinkIdentity(identity.id);
    if (!mounted) return;
    setState(() => _busy = false);
    await res.when(
      ok: (_) async {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.ssoUnlinkedSnack)));
        await _load();
      },
      err: (f) async {
        // The server refuses to leave an account with no way in at all.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(f.serverMessage ?? t.errUnknown)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final identities = _identities;
    if (_providers.isEmpty && (identities == null || identities.isEmpty)) {
      return const SizedBox.shrink();
    }
    final linkedSlugs = {
      for (final i in identities ?? const <SsoIdentity>[]) i.providerSlug,
    };
    // Native clients can only link providers whose device flow is available.
    final connectable = _providers
        .where((p) => !linkedSlugs.contains(p.slug))
        .where((p) => kIsWeb || p.deviceFlowEnabled)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.securitySectionSso,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (identities != null && identities.isEmpty && connectable.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(t.ssoNoneConnected),
            ),
          ),
        for (final identity in identities ?? const <SsoIdentity>[])
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(identity.providerDisplayName),
              subtitle: Text(
                identity.emailAtLink.isEmpty
                    ? identity.subject
                    : identity.emailAtLink,
              ),
              trailing: TextButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(_disconnect(identity)),
                child: Text(t.ssoDisconnectAction),
              ),
            ),
          ),
        for (final provider in connectable)
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_link),
              title: Text(provider.displayName),
              subtitle: Text(t.ssoConnectSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => unawaited(_connect(provider)),
            ),
          ),
      ],
    );
  }
}
