import 'package:flutter/widgets.dart';
import 'package:intellipilot/core/io/embedded_page_stub.dart'
    if (dart.library.js_interop) 'package:intellipilot/core/io/embedded_page_web.dart'
    as impl;

/// An external page embedded in the app.
///
/// On web this is a sandboxed `<iframe>`; on other targets it is a placeholder,
/// since there is no frame to put a foreign page in. Callers always pair it
/// with a visible "open in a new tab" affordance, which is the only thing that
/// works when the remote site refuses to be framed — many do, via
/// `X-Frame-Options` or a `frame-ancestors` policy, and a cross-origin frame
/// gives us no way to detect that.
class EmbeddedPage extends StatelessWidget {
  const EmbeddedPage({required this.url, super.key});

  final String url;

  /// Whether this platform can actually embed a page at all.
  static bool get isSupported => impl.isSupported;

  @override
  Widget build(BuildContext context) => impl.buildEmbeddedPage(url);
}
