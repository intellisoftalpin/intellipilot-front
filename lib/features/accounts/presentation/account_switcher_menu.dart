import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/accounts/data/account_store.dart';
import 'package:intellipilot/features/accounts/domain/account.dart';
import 'package:intellipilot/features/accounts/domain/account_switcher.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Account switcher for the top bar: server on the first line, user on the
/// second, on both the trigger and every item.
///
/// The server leads because it is what distinguishes accounts. The same
/// username routinely exists on several instances, so a user-first list would
/// show two identical-looking rows; the host (or bare IP, for a LAN install) is
/// always unambiguous.
///
/// Desktop and mobile only — web is served by its own instance and holds a
/// single cookie-backed session.
class AccountSwitcherMenu extends StatefulWidget {
  const AccountSwitcherMenu({this.compact = false, super.key});

  /// Below the top bar's 900px breakpoint, show only the server line.
  final bool compact;

  @override
  State<AccountSwitcherMenu> createState() => _AccountSwitcherMenuState();
}

class _AccountSwitcherMenuState extends State<AccountSwitcherMenu> {
  List<Account> _accounts = const [];
  Account? _active;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final accounts = await getIt<AccountStore>().list();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _active = getIt<AccountSwitcher>().active;
    });
  }

  Future<void> _switch(Account account) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final here = router.routerDelegate.currentConfiguration.uri.toString();

    final ok = await getIt<AccountSwitcher>().switchTo(
      account,
      currentRoute: here,
    );
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(t.accountsSwitchFailed)));
      await _load();
      return;
    }
    // Land where this account left off; fall back silently when the remembered
    // route no longer resolves for it (project gone, access revoked, or it
    // belonged to a different server).
    final restored = await getIt<AccountSwitcher>().restoredRouteFor(account);
    if (!mounted) return;
    router.go(restored ?? Routes.projects);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    // Never on web, and pointless with a single account — one account needs no
    // switcher, and "Add account" already lives in the profile menu.
    if (kIsWeb || _accounts.length < 2) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final active = _active;

    return MenuAnchor(
      menuChildren: [
        for (final a in _accounts)
          MenuItemButton(
            leadingIcon: Icon(
              a == active
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color: a == active ? theme.colorScheme.primary : null,
            ),
            onPressed: a == active ? null : () => unawaited(_switch(a)),
            child: _TwoLine(
              first: a.serverLabel,
              second: a.userLabel,
              emphasise: a == active,
            ),
          ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.person_add_alt, size: 16),
          onPressed: () => context.go(Routes.login),
          child: Text(t.accountsAddAnother),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: t.accountsSwitchTooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active != null)
                  ConstrainedBox(
                    // Bounded so a long host cannot push the top bar's other
                    // controls off the edge.
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: widget.compact
                        ? Text(
                            active.serverLabel,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          )
                        : _TwoLine(
                            first: active.serverLabel,
                            second: active.userLabel,
                            emphasise: true,
                          ),
                  ),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Server above, user below. Kept tight enough to sit inside the top bar's
/// fixed 52px — the project rail's header aligns to that exact height, so
/// growing the bar would break the two dividers' pixel alignment.
class _TwoLine extends StatelessWidget {
  const _TwoLine({
    required this.first,
    required this.second,
    this.emphasise = false,
  });

  final String first;
  final String second;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          first,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.15,
            fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        Text(
          second,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            height: 1.15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
