// The `_`-prefixed fields are intentionally private while the constructor
// keeps public parameter names.
// ignore_for_file: prefer_initializing_formals

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/cookie_setup.dart';
import 'package:intellipilot/core/network/server_endpoint.dart';
import 'package:intellipilot/core/network/tls/cert_trust.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';

/// Why a connect attempt did or did not succeed.
enum ConnectOutcome {
  ok,

  /// Not a usable server address at all.
  invalidUrl,

  /// DNS failure, refused, timeout — nothing answered.
  unreachable,

  /// TLS certificate rejected by the platform. The user may pin it.
  untrustedCertificate,

  /// Something answered, but it is not an IntelliPilot API.
  notIntelliPilot,
}

class ConnectResult {
  const ConnectResult(this.outcome, {this.cert, this.message, this.url});

  final ConnectOutcome outcome;

  /// Present for [ConnectOutcome.untrustedCertificate].
  final CertInfo? cert;
  final String? message;

  /// The normalised URL that was tried.
  final String? url;

  bool get isOk => outcome == ConnectOutcome.ok;
}

/// Validates a user-supplied server address, then makes it the app's endpoint.
///
/// Only reachable on desktop and mobile — web is served by its own instance and
/// never calls this.
class ServerConnectionService {
  ServerConnectionService({
    required ServerEndpoint endpoint,
    required ApiClient apiClient,
    required CertPinStore certPins,
    required CookieSetup cookies,
    required KeyValueStorage Function(String box) storage,
    @visibleForTesting Dio Function(String baseUrl)? probeDioFactory,
  }) : _endpoint = endpoint,
       _apiClient = apiClient,
       _certPins = certPins,
       _cookies = cookies,
       _storage = storage,
       _probeDioFactory = probeDioFactory;

  final ServerEndpoint _endpoint;
  final ApiClient _apiClient;
  final CertPinStore _certPins;
  final CookieSetup _cookies;
  final KeyValueStorage Function(String box) _storage;

  /// Lets tests drive the validation probe without a live server.
  final Dio Function(String baseUrl)? _probeDioFactory;

  Dio _makeProbeDio(String url) {
    final factory = _probeDioFactory;
    if (factory != null) return factory(url);
    final dio = Dio(
      BaseOptions(
        baseUrl: url,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    installCertPinning(dio, _certPins);
    return dio;
  }

  /// Turn what a human typed into a base URL, or null if it cannot be one.
  ///
  /// Accepts `pilot.example.com`, `https://pilot.example.com`,
  /// `http://192.168.1.10:8080`. Rejects anything carrying a path, query or
  /// fragment: the base URL is a server, not a page, and silently discarding
  /// part of what someone typed is worse than telling them.
  static String? normalise(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'https://$text';

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.hasQuery || uri.hasFragment) return null;
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.isNotEmpty) return null;

    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  /// True when this address would send credentials in the clear.
  static bool isCleartext(String normalisedUrl) =>
      Uri.parse(normalisedUrl).scheme == 'http';

  /// Validate [raw] and, on success, adopt it as the app's server.
  ///
  /// [trustCertificate] re-runs an attempt that previously reported
  /// [ConnectOutcome.untrustedCertificate], pinning the certificate the user
  /// was shown. Never set it without having shown them the fingerprint.
  Future<ConnectResult> connect(
    String raw, {
    bool trustCertificate = false,
  }) async {
    final url = normalise(raw);
    if (url == null) return const ConnectResult(ConnectOutcome.invalidUrl);
    final uri = Uri.parse(url);

    // TLS first: a rejected certificate must be surfaced as its own decision,
    // not buried in a generic "couldn't connect".
    if (uri.scheme == 'https') {
      final probe = await probeTls(uri);
      if (probe.status == CertProbeStatus.untrusted) {
        final cert = probe.cert;
        if (!trustCertificate || cert == null) {
          return ConnectResult(
            ConnectOutcome.untrustedCertificate,
            cert: cert,
            url: url,
          );
        }
        await _certPins.pin(
          uri.host,
          uri.hasPort ? uri.port : 443,
          cert.sha256,
        );
      }
    }

    // Then: is an IntelliPilot actually there? `/auth/config` is public, so
    // this works before any credentials exist, and it is what the login screen
    // needs next anyway.
    final probeDio = _makeProbeDio(url);
    try {
      final res = await probeDio.get<dynamic>('/api/v1/auth/config');
      final body = res.data;
      if (res.statusCode != 200 || body is! Map) {
        return ConnectResult(
          ConnectOutcome.notIntelliPilot,
          url: url,
          message: 'HTTP ${res.statusCode}',
        );
      }
      // Marker fields every IntelliPilot returns here. Checking shape rather
      // than a version string keeps this working across releases.
      if (!body.containsKey('open_registration') ||
          !body.containsKey('password_reset_enabled')) {
        return ConnectResult(ConnectOutcome.notIntelliPilot, url: url);
      }
    } on DioException catch (e) {
      return ConnectResult(
        ConnectOutcome.unreachable,
        url: url,
        message: e.message ?? e.type.name,
      );
    } on Object catch (e) {
      return ConnectResult(
        ConnectOutcome.unreachable,
        url: url,
        message: e.toString(),
      );
    } finally {
      probeDio.close(force: true);
    }

    // Adopt it. A *changed* server invalidates everything cached for the old
    // one, so that goes first — see [_wipePerServerState].
    final changed = await _endpoint.save(url);
    if (changed) await _wipePerServerState();
    _apiClient.baseUrl = url;
    return ConnectResult(ConnectOutcome.ok, url: url);
  }

  /// Drop everything that belonged to the previous server.
  ///
  /// Board snapshots, filters, column layouts and rail preferences are keyed by
  /// `(userId, projectId)` with no notion of *which* server, so carrying them
  /// across instances risks showing one server's data under another. Cookies go
  /// too: the old refresh cookie is useless and must not linger.
  ///
  /// `settings` deliberately survives — theme, locale and week-start are the
  /// user's global preferences, not the server's data.
  Future<void> _wipePerServerState() async {
    await _storage(HiveBoxes.boards).clear();
    await _storage(HiveBoxes.ui).clear();
    await _storage(HiveBoxes.drafts).clear();
    await _cookies.clear();
  }
}
