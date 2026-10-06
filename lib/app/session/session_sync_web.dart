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
  if (navigator.has('locks')) return PatientTabLock(_WebLockRequester());
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

class _WebLockRequester implements LockRequester {
  @override
  Future<bool> request(
    Future<void> Function() onGranted, {
    Future<void>? abandonWhen,
    bool steal = false,
  }) async {
    final options = web.LockOptions();
    web.AbortController? abort;
    if (steal) {
      options.steal = true;
    } else if (abandonWhen != null) {
      final controller = abort = web.AbortController();
      options.signal = controller.signal;
      unawaited(abandonWhen.then((_) => controller.abort()));
    }

    // The lock is held until the promise this callback returns settles, so
    // the body's whole lifetime runs inside it.
    Future<JSAny?> hold() async {
      await onGranted();
      return null;
    }

    // A closure, never a tear-off: dart2js rejects tear-offs of external
    // interop members.
    JSPromise<JSAny?> granted(JSAny? lock) => hold().toJS;

    try {
      await web.window.navigator.locks
          .request(_lockName, options, granted.toJS)
          .toDart;
      return true;
    } on Object {
      // Withdrawn before the grant: the caller decides what comes next.
      if (abort?.signal.aborted ?? false) return false;
      rethrow;
    }
  }
}
