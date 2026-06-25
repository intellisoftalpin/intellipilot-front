/// Build-time identity for the IntelliPilot client.
///
/// Values come from compile-time `--dart-define` flags so a single source
/// (`pubspec.yaml`) feeds the About dialog, the `X-Client-Version` header,
/// and the flavor-driven theming / API base. Defaults match `pubspec.yaml`
/// so a bare `flutter run` still surfaces sensible values during local
/// development.
///
/// To override at build time:
/// ```shell
/// flutter build web \
///   --dart-define=INTELLIPILOT_VERSION=0.2.0 \
///   --dart-define=INTELLIPILOT_BUILD=42 \
///   --dart-define=INTELLIPILOT_FLAVOR=prod
/// ```
class BuildInfo {
  const BuildInfo._();

  /// Semver string, e.g. `0.1.0`. Keep in lockstep with `pubspec.yaml`.
  static const String version = String.fromEnvironment(
    'INTELLIPILOT_VERSION',
    defaultValue: '0.1.0',
  );

  /// Build identifier (`+N` suffix in pubspec). Often a CI build number.
  static const String build = String.fromEnvironment(
    'INTELLIPILOT_BUILD',
    defaultValue: '1',
  );

  /// Flavor — drives flavor-specific UI accents and API base resolution.
  /// Values: `dev`, `staging`, `prod`. Defaults to `dev`.
  static const String flavor = String.fromEnvironment(
    'INTELLIPILOT_FLAVOR',
    defaultValue: 'dev',
  );

  /// `version+build`, matching the pubspec.yaml `version:` field shape.
  static String get fullVersion => '$version+$build';

  /// Stable client identifier sent on every request via
  /// `X-Client-Version` so server logs can correlate frontend builds with
  /// problem reports.
  static String get clientIdentifier =>
      'intellipilot-front/$version+$build ($flavor)';

  static bool get isProd => flavor == 'prod';
  static bool get isStaging => flavor == 'staging';
  static bool get isDev => flavor == 'dev';
}
