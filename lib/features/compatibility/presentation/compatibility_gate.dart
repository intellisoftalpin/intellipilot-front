import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intellipilot/app/build_info.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/router/app_router.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/features/compatibility/domain/compatibility_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Wraps the whole app and replaces it with a blocking notice when the client
/// build is older than the server it is talking to.
///
/// Deliberately above the router rather than inside a page: an incompatible
/// client must not be able to reach *any* screen, and a per-page banner would
/// leave every other route reachable by deep link.
class CompatibilityGate extends StatelessWidget {
  const CompatibilityGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CompatibilityCubit, CompatibilityState>(
      bloc: getIt<CompatibilityCubit>(),
      builder: (context, state) =>
          state.isBlocked ? _BlockedScreen(state: state) : child,
    );
  }
}

class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen({required this.state});

  final CompatibilityState state;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final server = state.serverVersion ?? '?';

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.system_update_alt,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  t.compatBlockedTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  // On web the client IS served by the server, so a mismatch
                  // means a stale cached bundle — reloading fixes it, and
                  // telling the user to call an administrator would be wrong.
                  kIsWeb
                      ? t.compatBlockedWebBody(BuildInfo.version, server)
                      : t.compatBlockedBody(BuildInfo.version, server),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () =>
                      unawaited(getIt<CompatibilityCubit>().check()),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(kIsWeb ? t.compatReload : t.compatRetry),
                ),
                // Desktop/mobile only, and only when the server is the user's
                // to choose: without this the app is a dead end, since the one
                // action that could resolve the mismatch — pointing at a
                // different server — would be unreachable.
                if (!kIsWeb &&
                    !getIt<ServerEndpoint>().isPinnedAtBuildTime) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      getIt<CompatibilityCubit>().reset();
                      GoRouter.of(context).go(Routes.connect);
                    },
                    child: Text(t.connectChange),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
