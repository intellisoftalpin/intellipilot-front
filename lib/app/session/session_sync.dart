import 'dart:async';
import 'dart:math' as math;

import 'package:intellipilot/app/session/session_sync_stub.dart'
    if (dart.library.js_interop) 'package:intellipilot/app/session/session_sync_web.dart'
    as impl;

/// An access token one browser tab hands to the others.
class SharedAccessToken {
  const SharedAccessToken({required this.accessToken, required this.expiresAt});

  final String accessToken;
  final DateTime expiresAt;

  /// Seconds of life left, never negative.
  int secondsLeft(DateTime now) =>
      math.max(0, expiresAt.difference(now).inSeconds);
}

/// What another tab told us.
sealed class SessionSyncMessage {
  const SessionSyncMessage();
}

/// Another tab now holds a fresh access token.
final class PeerTokenMessage extends SessionSyncMessage {
  const PeerTokenMessage(this.token);
  final SharedAccessToken token;
}

/// Another tab signed the user out.
final class PeerSignedOutMessage extends SessionSyncMessage {
  const PeerSignedOutMessage();
}

/// Keeps the tabs of one browser from fighting over a single refresh cookie.
///
/// Every tab of the web app shares one HttpOnly refresh cookie, and the server
/// rotates that token on each use. Two tabs refreshing at once used to present
/// the same token twice, which the server read as theft and answered by
/// signing the user out everywhere. This coordinates them: refreshes run one
/// at a time across tabs, a tab that refreshes tells the others the new access
/// token so they adopt it instead of refreshing themselves, and a freshly
/// opened tab asks the existing ones before touching the cookie at all.
///
/// Desktop and mobile run one window with their own token store, so they get
/// [SessionSync.none], which does nothing.
abstract interface class SessionSync {
  /// The platform's implementation: cross-tab on web, inert elsewhere.
  factory SessionSync.platform() => impl.platformSessionSync();

  /// An implementation that coordinates nothing.
  factory SessionSync.none() => const _NoSessionSync();

  /// Runs [body] while no other tab runs one — the refresh critical section.
  Future<T> exclusive<T>(Future<T> Function() body);

  /// Messages from other tabs.
  Stream<SessionSyncMessage> get incoming;

  /// Tell the other tabs about a freshly obtained access token.
  void announceToken(SharedAccessToken token);

  /// Tell the other tabs the user signed out.
  void announceSignedOut();

  /// Ask the other tabs for a current access token; null when none answers
  /// within [timeout].
  Future<SharedAccessToken?> askPeers({Duration timeout});

  /// Where answers to other tabs' [askPeers] come from.
  void answerWith(SharedAccessToken? Function() source);

  Future<void> dispose();
}

class _NoSessionSync implements SessionSync {
  const _NoSessionSync();

  @override
  Future<T> exclusive<T>(Future<T> Function() body) => body();

  @override
  Stream<SessionSyncMessage> get incoming => const Stream.empty();

  @override
  void announceToken(SharedAccessToken token) {}

  @override
  void announceSignedOut() {}

  @override
  Future<SharedAccessToken?> askPeers({
    Duration timeout = const Duration(milliseconds: 150),
  }) async => null;

  @override
  void answerWith(SharedAccessToken? Function() source) {}

  @override
  Future<void> dispose() async {}
}

/// A message bus between tabs — BroadcastChannel on web, an in-memory fake in
/// tests. Messages are plain JSON-able maps; a tab never receives its own.
abstract interface class TabChannel {
  void post(Map<String, Object?> message);
  Stream<Map<String, Object?>> get messages;
  void close();
}

/// A lock shared by every tab — the Web Locks API on web.
abstract interface class TabLock {
  Future<T> run<T>(Future<T> Function() body);
}

/// The raw cross-tab lock primitive — the Web Locks API on web.
abstract interface class LockRequester {
  /// Requests the lock and runs [onGranted] while holding it, completing once
  /// the lock is released again with true.
  ///
  /// When [abandonWhen] completes before the lock is granted, the request is
  /// withdrawn and this completes with false; after the grant it has no
  /// effect. [steal] takes the lock away from whoever holds it instead of
  /// queueing behind them.
  Future<bool> request(
    Future<void> Function() onGranted, {
    Future<void>? abandonWhen,
    bool steal = false,
  });
}

/// A cross-tab lock that never waits forever.
///
/// Another tab can hold the lock without ever letting go: a background tab
/// the browser froze mid-refresh keeps it for as long as it stays frozen.
/// Queueing behind it indefinitely left every other tab — and every reload —
/// on the startup spinner. So a request that is not granted within [maxWait]
/// steals the lock and runs anyway. At worst that lets two refreshes overlap,
/// which the server's rotation grace window absorbs; the alternative was a
/// user locked out of the app until they found and closed the frozen tab.
class PatientTabLock implements TabLock {
  PatientTabLock(this._requester, {this.maxWait = const Duration(seconds: 5)});

  final LockRequester _requester;
  final Duration maxWait;

  @override
  Future<T> run<T>(Future<T> Function() body) async {
    final done = Completer<T>();
    // The body may fail before the caller gets `done.future` below; that is
    // not an unhandled error — the caller still receives it.
    unawaited(done.future.then<void>((_) {}, onError: (Object _) {}));
    var started = false;

    Future<void> hold() async {
      if (started) return;
      started = true;
      try {
        done.complete(await body());
      } on Object catch (e, s) {
        done.completeError(e, s);
      }
    }

    final giveUp = Completer<void>();
    final timer = Timer(maxWait, () {
      if (!started) giveUp.complete();
    });
    try {
      final granted = await _requester.request(
        hold,
        abandonWhen: giveUp.future,
      );
      if (!granted) await _requester.request(hold, steal: true);
    } on Object {
      // The lock itself failed (or was stolen from us mid-body, which the
      // body survives): run unguarded rather than never.
      if (!started) unawaited(hold());
    } finally {
      timer.cancel();
    }
    return done.future;
  }
}

/// A lock that only serialises within this tab. The fallback where the Web
/// Locks API is missing (insecure origins, old browsers); the server's grace
/// window still keeps a cross-tab collision from signing anyone out.
class LocalTabLock implements TabLock {
  Future<void> _tail = Future<void>.value();

  @override
  Future<T> run<T>(Future<T> Function() body) {
    final result = _tail.then((_) => body());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

/// [SessionSync] over a [TabChannel] and a [TabLock].
class ChannelSessionSync implements SessionSync {
  ChannelSessionSync(this._channel, this._lock, {String? tabId})
    : _tabId = tabId ?? _randomId() {
    _sub = _channel.messages.listen(_onMessage);
  }

  final TabChannel _channel;
  final TabLock _lock;
  final String _tabId;
  late final StreamSubscription<Map<String, Object?>> _sub;
  final _incoming = StreamController<SessionSyncMessage>.broadcast();
  final _pendingAsks = <String, Completer<SharedAccessToken?>>{};
  SharedAccessToken? Function() _tokenSource = _noToken;

  static SharedAccessToken? _noToken() => null;

  static String _randomId() {
    final r = math.Random();
    return List.generate(
      4,
      (_) => r.nextInt(0x7fffffff).toRadixString(36),
    ).join();
  }

  @override
  Future<T> exclusive<T>(Future<T> Function() body) => _lock.run(body);

  @override
  Stream<SessionSyncMessage> get incoming => _incoming.stream;

  @override
  void answerWith(SharedAccessToken? Function() source) =>
      _tokenSource = source;

  /// The last token this tab announced. Answers asks even while this tab's
  /// session state has not caught up with its own refresh yet.
  SharedAccessToken? _lastAnnounced;

  @override
  void announceToken(SharedAccessToken token) {
    _lastAnnounced = token;
    _channel.post({'t': 'token', 'from': _tabId, ..._encode(token)});
  }

  @override
  void announceSignedOut() {
    _lastAnnounced = null;
    _channel.post({'t': 'signed_out', 'from': _tabId});
  }

  @override
  Future<SharedAccessToken?> askPeers({
    Duration timeout = const Duration(milliseconds: 150),
  }) {
    final q = _randomId();
    final answer = Completer<SharedAccessToken?>();
    _pendingAsks[q] = answer;
    _channel.post({'t': 'ask', 'from': _tabId, 'q': q});
    return answer.future
        .timeout(timeout, onTimeout: () => null)
        .whenComplete(() => _pendingAsks.remove(q));
  }

  void _onMessage(Map<String, Object?> m) {
    if (m['from'] == _tabId) return;
    switch (m['t']) {
      case 'token':
        final token = _decode(m);
        if (token != null) _incoming.add(PeerTokenMessage(token));
      case 'signed_out':
        _incoming.add(const PeerSignedOutMessage());
      case 'ask':
        final token = _freshest(_tokenSource(), _lastAnnounced);
        final q = m['q'];
        if (token != null && q is String) {
          _channel.post({
            't': 'answer',
            'from': _tabId,
            'q': q,
            ..._encode(token),
          });
        }
      case 'answer':
        final pending = _pendingAsks[m['q']];
        final token = _decode(m);
        if (pending != null && !pending.isCompleted && token != null) {
          pending.complete(token);
        }
    }
  }

  static SharedAccessToken? _freshest(
    SharedAccessToken? a,
    SharedAccessToken? b,
  ) {
    final now = DateTime.now();
    final candidates = [a, b].whereType<SharedAccessToken>().where(
      (t) => t.expiresAt.isAfter(now),
    );
    if (candidates.isEmpty) return null;
    return candidates.reduce(
      (x, y) => x.expiresAt.isAfter(y.expiresAt) ? x : y,
    );
  }

  static Map<String, Object?> _encode(SharedAccessToken t) => {
    'a': t.accessToken,
    'e': t.expiresAt.millisecondsSinceEpoch,
  };

  static SharedAccessToken? _decode(Map<String, Object?> m) {
    final a = m['a'];
    final e = m['e'];
    if (a is! String || a.isEmpty || e is! num) return null;
    return SharedAccessToken(
      accessToken: a,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(e.toInt()),
    );
  }

  @override
  Future<void> dispose() async {
    await _sub.cancel();
    _channel.close();
    await _incoming.close();
  }
}
