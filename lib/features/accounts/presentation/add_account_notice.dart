import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/features/accounts/domain/account_switcher.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Header shown on both wizard steps while adding a second account: what is
/// happening, which account it came from, and a way to abandon the attempt.
///
/// Shared by the connect and login pages because the interesting part is the
/// cancel path, which has to undo whatever the run has already done — and
/// having two copies of that is how one of them ends up wrong.
class AddAccountNotice extends StatelessWidget {
  const AddAccountNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final switcher = getIt<AccountSwitcher>();
    // Once step ① has adopted the new server the previous account is suspended
    // rather than active, so name whichever of the two exists.
    final from = switcher.active ?? switcher.suspendedAccount;

    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Icon(
              Icons.person_add_alt,
              size: 16,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.accountsAddTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  if (from != null)
                    Text(
                      t.accountsAddHint(from.userLabel),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_cancel(context)),
              child: Text(t.accountsAddCancel),
            ),
          ],
        ),
      ),
    );
  }

  /// Restore the account the run stood down, then return to wherever it was.
  ///
  /// Cancelling at step ① usually has nothing to restore — no server was
  /// adopted, so the account is still live and this is pure navigation. After
  /// step ① it is a real switch back: server, token and session.
  Future<void> _cancel(BuildContext context) async {
    final router = GoRouter.of(context);
    final switcher = getIt<AccountSwitcher>();
    await switcher.cancelAddAccount();
    final active = switcher.active;
    final back = active == null
        ? null
        : await switcher.restoredRouteFor(active);
    router.go(back ?? Routes.projects);
  }
}
