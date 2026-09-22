import 'package:intellipilot/app/session/session_sync.dart';

/// Desktop and mobile: one window, nothing to coordinate.
SessionSync platformSessionSync() => SessionSync.none();
