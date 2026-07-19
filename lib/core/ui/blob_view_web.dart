import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// Web: inline HTML/PDF previews render in a real browser frame.
const bool inlineBlobPreviewSupported = true;

var _viewSeq = 0;

/// Renders [bytes] of [mime] inside an `<iframe>` fed by a blob URL.
///
/// With [sandboxed] the frame gets an empty `sandbox` attribute — scripts,
/// forms, and same-origin access are all disabled, so an attached HTML file
/// renders faithfully but cannot touch the app session. PDFs use the
/// browser's built-in viewer and need no sandbox.
Widget buildBlobView({
  required Uint8List bytes,
  required String mime,
  required bool sandboxed,
}) => _BlobFrame(bytes: bytes, mime: mime, sandboxed: sandboxed);

class _BlobFrame extends StatefulWidget {
  const _BlobFrame({
    required this.bytes,
    required this.mime,
    required this.sandboxed,
  });

  final Uint8List bytes;
  final String mime;
  final bool sandboxed;

  @override
  State<_BlobFrame> createState() => _BlobFrameState();
}

class _BlobFrameState extends State<_BlobFrame> {
  late final String _viewType;
  late final String _url;

  @override
  void initState() {
    super.initState();
    final blob = web.Blob(
      [widget.bytes.toJS].toJS,
      web.BlobPropertyBag(type: widget.mime),
    );
    _url = web.URL.createObjectURL(blob);
    _viewType = 'blob-frame-${_viewSeq++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final frame = web.HTMLIFrameElement()
        ..src = _url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      if (widget.sandboxed) {
        // Empty sandbox: no scripts, no forms, opaque origin.
        frame.setAttribute('sandbox', '');
      }
      return frame;
    });
  }

  @override
  void dispose() {
    web.URL.revokeObjectURL(_url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
