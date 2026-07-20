import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intellipilot/core/network/sse/sse_frame.dart';

/// Native (mobile/desktop) SSE transport over `dart:io`.
///
/// The Bearer token goes in the `Authorization` header. The whole stream is
/// wrapped in a 60s inactivity timeout: the server heartbeats every ~25s (a
/// comment line, surfaced below as a `heartbeat` frame), so a full minute of
/// silence means the connection is dead behind a proxy — close it and let the
/// caller reconnect.
Stream<SseFrame> connectSse(Uri url, {String? bearerToken}) {
  const idleTimeout = Duration(seconds: 60);
  return _connect(
    url,
    bearerToken: bearerToken,
  ).timeout(idleTimeout, onTimeout: (sink) => sink.close());
}

Stream<SseFrame> _connect(Uri url, {String? bearerToken}) async* {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    if (bearerToken != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    }
    final res = await req.close();
    if (res.statusCode != HttpStatus.ok) {
      throw HttpException('SSE handshake failed: ${res.statusCode}', uri: url);
    }
    var event = '';
    final dataLines = <String>[];
    await for (final line
        in res.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (event.isNotEmpty || dataLines.isNotEmpty) {
          yield SseFrame(
            event: event.isEmpty ? 'message' : event,
            data: dataLines.join('\n'),
          );
        }
        event = '';
        dataLines.clear();
      } else if (line.startsWith(':')) {
        yield const SseFrame(event: 'heartbeat', data: '');
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
  } finally {
    client.close(force: true);
  }
}
