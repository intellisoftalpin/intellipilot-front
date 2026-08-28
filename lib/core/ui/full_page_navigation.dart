import 'package:intellipilot/core/ui/full_page_navigation_stub.dart'
    if (dart.library.js_interop) 'package:intellipilot/core/ui/full_page_navigation_web.dart'
    as impl;

/// Navigate the whole browser page to [url], leaving the Flutter app.
///
/// Exists for the single-sign-on redirect flow, which is not something the
/// in-app router can do: the browser has to physically visit the identity
/// provider and come back to the server's callback, which sets the session
/// cookie before handing control back to the app. Pushing a route would keep
/// us inside the SPA and never leave the origin.
///
/// A no-op off the web, where the device-code flow is used instead.
void navigateWholePage(String url) => impl.navigateWholePage(url);
