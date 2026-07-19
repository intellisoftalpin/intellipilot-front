import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Non-web stub: inline HTML/PDF previews need a browser engine, so native
/// targets fall back to download (see `inlineBlobPreviewSupported`).
const bool inlineBlobPreviewSupported = false;

/// Never called on non-web targets (guarded by the flag above).
Widget buildBlobView({
  required Uint8List bytes,
  required String mime,
  required bool sandboxed,
}) => const SizedBox.shrink();
