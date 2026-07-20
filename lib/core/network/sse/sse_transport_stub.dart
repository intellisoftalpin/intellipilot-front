import 'package:intellipilot/core/network/sse/sse_frame.dart';

/// Fallback for platforms with neither `dart:io` nor `dart:js_interop`.
Stream<SseFrame> connectSse(Uri url, {String? bearerToken}) =>
    const Stream.empty();
