import 'package:intellipilot/core/io/url_opener_stub.dart'
    if (dart.library.js_interop) 'package:intellipilot/core/io/url_opener_web.dart'
    as impl;

/// Cross-platform "open this URL in a new tab/window". Native targets in the
/// Phase-9 deliverable are a no-op (download path lives behind the web
/// build); tests substitute trivially.
void openExternalUrl(String url) => impl.openExternalUrl(url);
