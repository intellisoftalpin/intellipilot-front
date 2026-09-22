import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:intellipilot/app/session/session_sync.dart';
import 'package:web/web.dart' as web;

const _channelName = 'intellipilot-session';
const _lockName = 'intellipilot-session-refresh';

/// Web: coordinate every tab of this origin.
SessionSync platformSessionSync() {
  final TabChannel channel;
  try {
    channel = _BroadcastTabChannel();
  } on Object {
    // No BroadcastChannel (very old browser): behave like a single tab.
    return SessionSync.none();
  }
  return ChannelSessionSync(channel, _webLockOrLocal());
}

TabLock _webLockOrLocal() {
  // `navigator.locks` exists only in secure contexts on current browsers.
  final navigator = web.window.navigator as JSObject;
  if (navigator.has('locks')) return _WebTabLock();
  return LocalTabLock();
}

class _BroadcastTabChannel implements TabChannel {
  _BroadcastTabChannel() : _channel = web.BroadcastChannel(_channelName) {
    // A closure, never a tear-off: dart2js rejects tear-offs of external
    // interop members.
    _channel.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      if (!data.isA<JSString>()) return;
      try {
        final decoded = jsonDecode((data! as JSString).toDart);
        if (decoded is Map<String, Object?>) _messages.add(decoded);
      } on FormatException {
        // Not ours.
      }
    }).toJS;
  }

  final web.BroadcastChannel _channel;
  final _messages = StreamController<Map<String, Object?>>.broadcast();

  @override
  void post(Map<String, Object?> message) =>
      _channel.postMessage(jsonEncode(message).toJS);

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  void close() {
    _channel.close();
    unawaited(_messages.close());
  }
}

class _WebTabLock implements TabLock {
  @override
  Future<T> run<T>(Future<T> Function() body) {
    final done = Completer<T>();

    // The lock is held until the promise this callback returns settles, so
    // the body's whole lifetime runs inside it.
    Future<JSAny?> hold() async {
      try {
        done.complete(await body());
      } on Object catch (e, s) {
        done.completeError(e, s);
      }
      return null;
    }

    JSPromise<JSAny?> granted(JSAny? lock) => hold().toJS;

    try {
      web.window.navigator.locks.request(_lockName, granted.toJS);
    } on Object {
      // The lock request itself failed; run unguarded rather than never.
      return body();
    }
    return done.future;
  }
}
