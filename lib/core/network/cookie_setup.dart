import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Cookie setup is platform-conditional.
///
/// **Web** — the browser owns the HttpOnly refresh-token cookie; JS code can't
/// read it. `withCredentials: true` on Dio plus a CORS-allowed backend is all
/// we need. We return a stub jar so callers can hold a non-null reference.
///
/// **Native** — Dart manages cookies via [PersistCookieJar] backed by
/// `<app-docs>/.cookies`. Persisting in app private storage is sufficient for
/// MVP; we can layer secure storage on top in a later phase if threat-modelled.
class CookieSetup {
  CookieSetup({required this.jar, required this.manager});

  factory CookieSetup.inMemory() {
    final jar = CookieJar();
    // The dio cookie manager asserts !kIsWeb in its constructor — on web,
    // browser-owned cookies are used instead.
    return CookieSetup(
      jar: jar,
      manager: kIsWeb ? null : CookieManager(jar),
    );
  }

  final CookieJar jar;
  final CookieManager? manager;

  static Future<CookieSetup> create() async {
    if (kIsWeb) {
      return CookieSetup(jar: CookieJar(), manager: null);
    }
    final dir = await getApplicationDocumentsDirectory();
    final jar = PersistCookieJar(
      ignoreExpires: false,
      storage: FileStorage('${dir.path}/.cookies'),
    );
    return CookieSetup(jar: jar, manager: CookieManager(jar));
  }

  Future<void> clear() async => jar.deleteAll();
}
