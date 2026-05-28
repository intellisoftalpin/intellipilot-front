import 'package:intellipilot/core/ui/path_strategy_stub.dart'
    if (dart.library.js_interop) 'package:intellipilot/core/ui/path_strategy_web.dart'
    as impl;

/// Apply the "clean URL" path strategy on web (no `#/…` prefix). No-op on
/// every other target.
void applyPathUrlStrategy() => impl.applyPathUrlStrategy();
