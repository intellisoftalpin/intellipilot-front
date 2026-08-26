import 'package:intellipilot/core/network/server_endpoint.dart';

/// Configuration for the HTTP layer, consumed by [ApiClient].
///
/// Every field except [baseUrl] is resolved once at bootstrap from compile-time
/// `--dart-define`s. [baseUrl] is a *getter* rather than a field because on
/// desktop and mobile the server is chosen at runtime — see [ServerEndpoint]
/// for why that indirection has to live here and not at the call sites.
class ApiConfig {
  const ApiConfig({
    required String baseUrl,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.enableRequestLogging = false,
    this.withCredentials = false,
  }) : _configuredBaseUrl = baseUrl;

  /// Read from `--dart-define=INTELLIPILOT_API_BASE=https://api.example.com`.
  /// Defaults to localhost for local dev runs.
  factory ApiConfig.fromEnvironment() {
    const base = String.fromEnvironment(
      'INTELLIPILOT_API_BASE',
      defaultValue: devFallbackBaseUrl,
    );
    const logging = bool.fromEnvironment(
      'INTELLIPILOT_LOG_HTTP',
      defaultValue: false,
    );
    return const ApiConfig(
      baseUrl: base,
      enableRequestLogging: logging,
      withCredentials: true,
    );
  }

  /// Whether `--dart-define=INTELLIPILOT_API_BASE` was supplied at all.
  ///
  /// Distinct from "supplied but empty": the web release build passes it
  /// deliberately empty so requests stay relative to the page origin, and that
  /// must not be confused with a build that simply forgot it.
  static const hasBaseUrlDefine = bool.hasEnvironment('INTELLIPILOT_API_BASE');

  /// The raw define, or `''` when absent.
  static const baseUrlDefine = String.fromEnvironment('INTELLIPILOT_API_BASE');

  /// Historical default for local development. Applied only in debug builds:
  /// a *release* desktop build that silently pointed at localhost is the bug
  /// the connect wizard exists to fix.
  static const devFallbackBaseUrl = 'http://localhost:8080';

  /// The base URL this config was constructed with: the compile-time define
  /// in production, an explicit value in tests and demo mode.
  final String _configuredBaseUrl;

  /// Where requests actually go.
  ///
  /// Prefers the runtime-selected server ([ServerEndpoint]) when one is active,
  /// which is the case on desktop and mobile once the user has completed the
  /// connect wizard. On web `ServerEndpoint.active` is never set, so this is
  /// the compile-time value — empty in release, making every request relative
  /// to the page origin.
  String get baseUrl =>
      ServerEndpoint.active?.resolveOr(_configuredBaseUrl) ??
      _configuredBaseUrl;

  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;
  final bool enableRequestLogging;

  /// Send cookies on cross-origin requests (web only — relevant for the
  /// HttpOnly refresh-token cookie set by the backend).
  final bool withCredentials;
}
