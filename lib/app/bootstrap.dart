import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intellipilot/app/app.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/ui/path_strategy.dart';
import 'package:intellipilot/demo/configure_demo.dart';
import 'package:intellipilot/features/accounts/domain/account_switcher.dart';
import 'package:intellipilot/features/compatibility/domain/compatibility_cubit.dart';
import 'package:logger/logger.dart';

/// Single entry-point shared by every flavor (`main_dev.dart`, `main_prod.dart`).
///
/// Wraps `runApp` in a [runZonedGuarded] so uncaught async errors are routed
/// through the logger instead of crashing silently. Phase 18 will replace
/// the catch-all with a real crash reporter (Sentry).
Future<void> bootstrap() async {
  await runZonedGuarded<Future<void>>(
    () async {
      // Binding init MUST live in the same zone as `runApp` — otherwise
      // Flutter logs a "Zone mismatch" warning at every microtask and any
      // zone-specific config (timers, error hooks) is silently unreliable.
      WidgetsFlutterBinding.ensureInitialized();
      applyPathUrlStrategy();

      await HiveBoxes.init();
      if (isDemoMode) {
        await configureDemoDependencies();
      } else {
        await configureDependencies();
      }

      FlutterError.onError = (details) {
        getIt<Logger>().e(
          'Flutter error',
          error: details.exception,
          stackTrace: details.stack,
        );
      };

      // Try restoring a session from the persisted refresh cookie. The bloc
      // settles into SessionAuthenticated on success or SessionUnauthenticated
      // on failure — the router guard reacts on the next stream tick.
      //
      // Skipped when no server is configured yet (a fresh desktop/mobile
      // install): there is nowhere to send the request, and attempting it would
      // probe the dev localhost default on every cold start. The router sends
      // the user to the connect wizard instead.
      // Desktop/mobile: bring back the account that was last active, which
      // also restores its server, cache namespace and refresh token. Must
      // happen before the startup refresh, which needs that token.
      if (!kIsWeb && !isDemoMode) {
        await getIt<AccountSwitcher>().restore();
      }
      if (isDemoMode || getIt<ServerEndpoint>().isConfigured) {
        getIt<SessionBloc>().add(const SessionStartupRequested());
        // Version handshake against the server. Unauthenticated, so it does not
        // wait on the session; a failure leaves the app usable.
        if (!isDemoMode) {
          unawaited(getIt<CompatibilityCubit>().check());
        }
      }

      runApp(const IntelliPilotApp());
    },
    (error, stack) {
      getIt<Logger>().e('Uncaught zone error', error: error, stackTrace: stack);
    },
  );
}
