import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const bool isSupported = true;

/// View types are global and permanent, so one is registered per distinct URL
/// and reused. A documentation project has a handful of web links, so this set
/// stays tiny for the life of the session.
final Set<String> _registered = <String>{};

String _viewTypeFor(String url) => 'embedded-page-${url.hashCode}';

/// Register a factory that builds the `<iframe>` for [url].
void _ensureRegistered(String url) {
  final viewType = _viewTypeFor(url);
  if (!_registered.add(viewType)) return;
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
    final frame = web.document.createElement('iframe') as web.HTMLIFrameElement
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      // Deliberately WITHOUT `allow-top-navigation`: a framed page must not
      // be able to navigate the tab out from under the app. Scripts,
      // same-origin (its own origin) and forms are allowed so ordinary
      // documentation sites work; popups open in a new tab, which is the
      // behaviour a reader expects from a link anyway.
      ..setAttribute(
        'sandbox',
        'allow-scripts allow-same-origin allow-forms allow-popups '
            'allow-popups-to-escape-sandbox allow-downloads',
      )
      // Don't leak the IntelliPilot URL (which contains project ids) to the
      // embedded site.
      ..setAttribute('referrerpolicy', 'no-referrer')
      ..setAttribute('loading', 'lazy');
    return frame;
  });
}

Widget buildEmbeddedPage(String url) {
  _ensureRegistered(url);
  return HtmlElementView(viewType: _viewTypeFor(url));
}
