import 'dart:async';
import 'dart:js_interop';

import 'package:intellipilot/core/network/sse/sse_frame.dart';
import 'package:web/web.dart' as web;

/// Browser SSE transport over the native `EventSource`.
///
/// `EventSource` cannot set request headers, so the short-lived access token
/// travels as an `access_token` query parameter (the backend promotes it to
/// a Bearer header for this route). Native auto-reconnect is not used: any
/// error closes the stream so the caller reconnects with a fresh token.
Stream<SseFrame> connectSse(Uri url, {String? bearerToken}) {
  final target = bearerToken == null
      ? url
      : url.replace(
          queryParameters: {
            ...url.queryParameters,
            'access_token': bearerToken,
          },
        );
  final controller = StreamController<SseFrame>();
  final source = web.EventSource(target.toString());

  void forward(String name) {
    source.addEventListener(
      name,
      ((web.Event e) {
        final data = (e as web.MessageEvent).data.dartify();
        if (!controller.isClosed) {
          controller.add(SseFrame(event: name, data: data?.toString() ?? ''));
        }
      }).toJS,
    );
  }

  forward('change');
  forward('resync');
  source.onerror = ((web.Event e) {
    source.close();
    if (!controller.isClosed) unawaited(controller.close());
  }).toJS;
  // A tear-off of an external interop member is disallowed by dart2js/wasm —
  // wrap the call in a closure.
  controller.onCancel = () => source.close();
  return controller.stream;
}
