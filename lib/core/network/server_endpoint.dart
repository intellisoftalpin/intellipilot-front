// `_storage` / `_compileTimeBase` are intentionally private fields.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';

/// Which IntelliPilot server the app talks to.
///
/// **Web never uses this.** The web app is served *by* its own instance, so its
/// base URL is deliberately empty and every request resolves against the page
/// origin. There is nothing for a user to choose, and letting them choose would
/// only break CORS.
///
/// **Desktop and mobile have no origin to infer from**, so the server is picked
/// in the connect wizard and persisted here. A compile-time
/// `--dart-define=INTELLIPILOT_API_BASE` still wins, which keeps dev runs and
/// pre-configured builds behaving exactly as they did before this existed.
class ServerEndpoint extends ChangeNotifier {
  ServerEndpoint({
    required KeyValueStorage storage,
    required String compileTimeBase,
    @visibleForTesting bool? isWeb,
  }) : _storage = storage,
       _isWeb = isWeb ?? kIsWeb,
       _compileTimeBase = compileTimeBase.trim();

  /// The endpoint a desktop/mobile build is pinned to at compile time, if any.
  ///
  /// An explicit `--dart-define=INTELLIPILOT_API_BASE=…` wins and skips the
  /// wizard. Otherwise there is no pin and the user picks a server — in debug
  /// exactly as in release.
  ///
  /// Debug deliberately gets no localhost shortcut. It would mean the wizard
  /// could not be reached by `flutter run` at all, so the one path that ships
  /// would be the one never exercised in development. The shortcut also buys
  /// very little: the wizard persists its answer, so a developer types
  /// `localhost:8080` once per machine and every later run goes straight to
  /// login regardless.
  static String compileTimePin() =>
      ApiConfig.hasBaseUrlDefine && ApiConfig.baseUrlDefine.trim().isNotEmpty
      ? ApiConfig.baseUrlDefine.trim()
      : '';

  /// The app-wide instance consulted by `ApiConfig.baseUrl`.
  ///
  /// Static on purpose. Around a dozen widgets build image URLs from
  /// `ApiConfig.baseUrl` at paint time (avatars, attachments, epic covers,
  /// markdown images, the branding icon) and the SSE service builds its stream
  /// URL the same way. Funnelling every one of them through a single lookup is
  /// what stops a server switch from applying to API calls but not to images —
  /// a half-switched app is worse than one that refuses to switch.
  ///
  /// Left null on web, so `ApiConfig` falls back to its compile-time value.
  static ServerEndpoint? active;

  static const _key = 'server.base_url';

  final KeyValueStorage _storage;
  final String _compileTimeBase;

  /// Injectable so both platform branches are reachable from a VM test.
  ///
  /// A bare `kIsWeb` is a compile-time constant, so under `flutter test` the
  /// web side of every branch is dead code that no test can enter — which is
  /// precisely how the web app shipped unable to start.
  final bool _isWeb;

  /// True when the endpoint is fixed at build time and the wizard must be
  /// skipped entirely.
  bool get isPinnedAtBuildTime => _compileTimeBase.isNotEmpty;

  /// The user-chosen server, or null if they have not chosen one.
  String? get stored {
    final v = _storage.get<String>(_key);
    return (v == null || v.isEmpty) ? null : v;
  }

  /// The URL requests should actually go to: build-time override first, then
  /// the user's choice, then empty (meaning "not configured").
  String get effective =>
      isPinnedAtBuildTime ? _compileTimeBase : (stored ?? '');

  /// Whether a non-empty base URL is set. Prefer [canReachServer] or
  /// [needsServerChoice] for "can the app work?" — on web an empty base URL
  /// means *same origin*, not *unknown*, and this getter cannot tell them
  /// apart.
  bool get isConfigured => effective.isNotEmpty;

  /// Whether the app knows where to send requests.
  ///
  /// True on web whatever [isConfigured] says: the web app is served by its own
  /// instance, so an empty base URL resolves against the page origin. Only
  /// desktop and mobile can be genuinely unconfigured.
  ///
  /// This distinction lives here, in one place, because it was previously
  /// spelled out at each call site — and the two sites disagreed. The router
  /// guarded its check with `!kIsWeb`; bootstrap did not, so on web it never
  /// started session restoration, the session never left its initial state, and
  /// the guard waited for a restoration that was never going to happen.
  bool get canReachServer => _isWeb || isConfigured;

  /// Whether the user must be sent to the connect wizard before anything else.
  bool get needsServerChoice => !canReachServer;

  /// Resolve for a caller holding its own fallback (an [ApiConfig] built with
  /// an explicit base, as tests and demo mode do).
  String resolveOr(String fallback) => isConfigured ? effective : fallback;

  /// Persist a new server. Returns true when it differs from the previous one,
  /// which is the caller's signal to wipe per-server state.
  Future<bool> save(String url) async {
    final previous = stored;
    await _storage.set<String>(_key, url);
    notifyListeners();
    return previous != null && previous != url;
  }

  Future<void> clear() async {
    await _storage.remove(_key);
    notifyListeners();
  }
}
