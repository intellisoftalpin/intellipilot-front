import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intellipilot/core/ui/blob_view_stub.dart'
    if (dart.library.js_interop) 'package:intellipilot/core/ui/blob_view_web.dart'
    as impl;

/// Whether the platform can render HTML/PDF bytes inline (web only).
bool get inlineBlobPreviewSupported => impl.inlineBlobPreviewSupported;

/// Inline browser frame over in-memory bytes; see the web impl for the
/// sandboxing contract. Only build this when [inlineBlobPreviewSupported].
Widget buildBlobView({
  required Uint8List bytes,
  required String mime,
  required bool sandboxed,
}) => impl.buildBlobView(bytes: bytes, mime: mime, sandboxed: sandboxed);
