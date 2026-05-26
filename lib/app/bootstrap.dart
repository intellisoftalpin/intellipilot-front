import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intellipilot/app/app.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/app/session/session_bloc.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:logger/logger.dart';

/// Single entry-point shared by every flavor (`main_dev.dart`, `main_prod.dart`).
///
/// Wraps `runApp` in a [runZonedGuarded] so uncaught async errors are routed
/// through the logger instead of crashing silently. Phase 18 will replace
/// the catch-all with a real crash reporter (Sentry).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await runZonedGuarded<Future<void>>(
    () async {
      await HiveBoxes.init();
      await configureDependencies();

      FlutterError.onError = (details) {
        getIt<Logger>().e(
          'Flutter error',
          error: details.exception,
          stackTrace: details.stack,
        );
      };

      // Kick the session state machine. Phase 2 will wire real restoration.
      getIt<SessionBloc>().add(const SessionRestored());

      runApp(const IntelliPilotApp());
    },
    (error, stack) {
      getIt<Logger>().e('Uncaught zone error', error: error, stackTrace: stack);
    },
  );
}
