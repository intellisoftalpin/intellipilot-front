import 'dart:async';

import 'package:flutter/foundation.dart';

/// Adapts a [Stream] of state changes to a [Listenable] so it can drive
/// `GoRouter.refreshListenable`. Single-subscription friendly: closes its
/// subscription on dispose.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
