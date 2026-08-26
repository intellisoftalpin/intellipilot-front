// The private fields are set from public named parameters, which initializing
// formals cannot express.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:intellipilot/core/network/sse/sse_transport_stub.dart'
    if (dart.library.io) 'package:intellipilot/core/network/sse/sse_transport_io.dart'
    if (dart.library.js_interop) 'package:intellipilot/core/network/sse/sse_transport_web.dart';

/// A live event from a project's change feed.
///
/// `change` events carry the backend payload (`event`, `actor_id`, `issue`,
/// `issue_id`, `board_id`). `connected` and `resync` are control markers: both
/// mean "state may have gaps — run a delta sync". The stream is strictly a
/// latency optimization; consumers must stay correct if it never emits.
class LiveEvent {
  const LiveEvent.control(this.type) : payload = const {};
  const LiveEvent.change(this.payload) : type = 'change';
  final String type;
  final Map<String, dynamic> payload;

  bool get isControl => type != 'change';
}

typedef AccessTokenProvider = String? Function();

/// Manages one SSE connection per watched project with reconnect/backoff and
/// app-lifecycle awareness (the stream closes while the app is backgrounded
/// and resumes — emitting `connected` so watchers catch up via delta — on
/// foreground). Feeds are ref-counted: the connection opens on the first
/// listener and closes when the last one cancels.
class ProjectEventsService with WidgetsBindingObserver {
  ProjectEventsService({
    required String Function() baseUrl,
    required AccessTokenProvider tokenProvider,
  }) : _baseUrl = baseUrl,
       _tokenProvider = tokenProvider {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Resolved per connection rather than captured once: on desktop the server
  /// can change at runtime, and a stream still pointing at the previous host is
  /// the kind of half-switch that is hard to notice and harder to debug.
  final String Function() _baseUrl;
  final AccessTokenProvider _tokenProvider;
  final Map<String, _ProjectFeed> _feeds = {};
  bool _suspended = false;

  Stream<LiveEvent> watch(String projectId) {
    final feed = _feeds.putIfAbsent(
      projectId,
      () => _ProjectFeed(
        uri: Uri.parse('${_baseUrl()}/api/v1/projects/$projectId/events'),
        tokenProvider: _tokenProvider,
        isSuspended: () => _suspended,
        onIdle: () => _feeds.remove(projectId),
      ),
    );
    return feed.stream;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final suspend = switch (state) {
      AppLifecycleState.resumed || AppLifecycleState.inactive => false,
      AppLifecycleState.paused ||
      AppLifecycleState.hidden ||
      AppLifecycleState.detached => true,
    };
    if (suspend == _suspended) return;
    _suspended = suspend;
    for (final feed in _feeds.values) {
      if (suspend) {
        feed.dropConnection();
      } else {
        feed.wake();
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    shutdownAll();
  }

  /// Close every live feed without retiring the service.
  ///
  /// Used when the app changes account or server: the streams carry the old
  /// identity's authorisation and point at the old host, so they must be gone
  /// before anything reconnects. Watchers re-subscribe on the next `watch`.
  void shutdownAll() {
    for (final feed in _feeds.values.toList()) {
      feed.shutdown();
    }
    _feeds.clear();
  }
}

class _ProjectFeed {
  _ProjectFeed({
    required this.uri,
    required this.tokenProvider,
    required this.isSuspended,
    required this.onIdle,
  }) {
    _controller = StreamController<LiveEvent>.broadcast(
      onListen: _start,
      onCancel: _maybeStop,
    );
  }

  final Uri uri;
  final AccessTokenProvider tokenProvider;
  final bool Function() isSuspended;
  final void Function() onIdle;

  late final StreamController<LiveEvent> _controller;
  StreamSubscription<dynamic>? _connection;
  Completer<void>? _wake;
  bool _active = false;

  Stream<LiveEvent> get stream => _controller.stream;

  void _start() {
    if (_active) return;
    _active = true;
    unawaited(_loop());
  }

  void _maybeStop() {
    if (!_controller.hasListener) shutdown();
  }

  void shutdown() {
    _active = false;
    dropConnection();
    wake();
    onIdle();
    unawaited(_controller.close());
  }

  /// Abort the current connection (backgrounding / shutdown).
  void dropConnection() {
    unawaited(_connection?.cancel());
    _connection = null;
  }

  /// Interrupt the backoff/suspend wait so the loop re-evaluates now.
  void wake() {
    final w = _wake;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> _delay(Duration d) async {
    final w = _wake = Completer<void>();
    unawaited(
      Future<void>.delayed(d).then((_) {
        if (!w.isCompleted) w.complete();
      }),
    );
    await w.future;
  }

  Future<void> _loop() async {
    var backoffSecs = 2;
    while (_active) {
      if (isSuspended()) {
        await _delay(const Duration(seconds: 3600));
        continue;
      }
      var sawFrame = false;
      try {
        final frames = connectSse(uri, bearerToken: tokenProvider());
        final done = Completer<void>();
        _connection = frames.listen(
          (frame) {
            sawFrame = true;
            switch (frame.event) {
              case 'change':
                try {
                  final payload =
                      jsonDecode(frame.data) as Map<String, dynamic>;
                  _emit(LiveEvent.change(payload));
                } on Object {
                  // Malformed payload → treat as a gap.
                  _emit(const LiveEvent.control('resync'));
                }
              case 'resync':
                _emit(const LiveEvent.control('resync'));
              default:
                break; // heartbeats keep the transport's watchdog fed
            }
          },
          onError: (Object _) {
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
        _emit(const LiveEvent.control('connected'));
        await done.future;
      } on Object {
        // Connect failed — fall through to backoff.
      }
      dropConnection();
      if (!_active) break;
      // A connection that produced frames was healthy: the server caps
      // streams at the token lifetime, so reconnect promptly. Otherwise
      // back off (server down / unauthorized).
      if (sawFrame) {
        backoffSecs = 2;
        await _delay(const Duration(seconds: 1));
      } else {
        await _delay(Duration(seconds: backoffSecs));
        backoffSecs = math.min(backoffSecs * 2, 30);
      }
    }
  }

  void _emit(LiveEvent e) {
    if (!_controller.isClosed) _controller.add(e);
  }
}
