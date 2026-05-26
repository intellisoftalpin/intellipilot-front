/// Immutable configuration for the HTTP layer. Resolved once at bootstrap
/// from compile-time `--dart-define`s; consumed by [ApiClient].
class ApiConfig {
  const ApiConfig({
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.enableRequestLogging = false,
    this.withCredentials = false,
  });

  /// Read from `--dart-define=INTELLIPILOT_API_BASE=https://api.example.com`.
  /// Defaults to localhost for local dev runs.
  factory ApiConfig.fromEnvironment() {
    const base = String.fromEnvironment(
      'INTELLIPILOT_API_BASE',
      defaultValue: 'http://localhost:8080',
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

  final String baseUrl;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;
  final bool enableRequestLogging;

  /// Send cookies on cross-origin requests (web only — relevant for the
  /// HttpOnly refresh-token cookie set by the backend).
  final bool withCredentials;
}
