import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/accounts/domain/account.dart';
import 'package:intellipilot/features/accounts/domain/account_switcher.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// The accounts already signed in on this device, offered on the login screen.
///
/// The login screen is reachable in several states where the top-bar switcher
/// is not on screen at all — part-way through adding an account, after a
/// session expired, after a cold start whose stored token turned out to be
/// dead. In every one of them the other accounts are still usable, and without
/// this the only way to reach them was to complete a login the user had already
/// changed their mind about.
///
/// Server on the first line, user on the second, matching the top-bar switcher:
/// the same username routinely exists on several instances, so the host is what
/// actually distinguishes the rows.
///
/// Desktop and mobile only — web is served by its own instance and holds a
/// single cookie-backed session.
class SignedInAccounts extends StatefulWidget {
  const SignedInAccounts({super.key});

  @override
  State<SignedInAccounts> createState() => _SignedInAccountsState();
}

class _SignedInAccountsState extends State<SignedInAccounts> {
  List<Account> _accounts = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Follow the switcher rather than reading it once: an account is adopted a
    // profile round-trip after login, by which time this widget is already
    // built, so a one-shot read misses the account that was just added.
    getIt<AccountSwitcher>().addListener(_reload);
    unawaited(_load());
  }

  @override
  void dispose() {
    getIt<AccountSwitcher>().removeListener(_reload);
    super.dispose();
  }

  void _reload() => unawaited(_load());

  Future<void> _load() async {
    if (kIsWeb) return;
    final accounts = await getIt<AccountSwitcher>().accounts();
    if (!mounted) return;
    setState(() => _accounts = accounts);
  }

  Future<void> _open(Account account) async {
    if (_busy) return;
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final switcher = getIt<AccountSwitcher>();

    // Already the live identity — nothing to switch, just leave the login
    // screen. Happens when the add-account flow is abandoned at step ②
    // before a new server was ever adopted.
    final ok = account == switcher.active || await switcher.switchTo(account);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      // The stored credential was dead, and the switcher has dropped the
      // account. Re-read the list so the row disappears with the explanation.
      messenger.showSnackBar(SnackBar(content: Text(t.accountsSwitchFailed)));
      await _load();
      return;
    }
    final restored = await switcher.restoredRouteFor(account);
    if (!mounted) return;
    router.go(restored ?? Routes.projects);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || _accounts.isEmpty) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.accountsContinueAs,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          t.accountsContinueAsHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 10),
        for (final a in _accounts) ...[
          _AccountTile(
            account: a,
            enabled: !_busy,
            onTap: () => unawaited(_open(a)),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                t.accountsOrSignIn,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.enabled,
    required this.onTap,
  });

  final Account account;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.account_circle_outlined,
                size: 28,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.serverLabel,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      account.userLabel,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
