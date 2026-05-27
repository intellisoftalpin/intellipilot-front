import 'package:intellipilot/features/mfa/data/passkey_service_stub.dart'
    if (dart.library.js_interop) 'package:intellipilot/features/mfa/data/passkey_service_web.dart'
    as impl;

/// Platform abstraction over the WebAuthn ceremonies. Web has a real
/// `navigator.credentials` implementation; native targets currently throw
/// [UnsupportedError] until per-platform WebAuthn bindings land in a later
/// phase. Callers should guard CTAs with [PasskeyService.isSupported].
abstract interface class PasskeyService {
  factory PasskeyService() => impl.createPasskeyService();

  /// Whether WebAuthn is reachable on the current platform.
  bool get isSupported;

  /// Run the registration ceremony. `creationOptions` is the JSON returned by
  /// the backend's `/register/start`; the result is the W3C-shaped JSON the
  /// backend's `/register/finish` expects under the `credential` field.
  Future<Map<String, dynamic>> register(
    Map<String, dynamic> creationOptions,
  );

  /// Run the assertion ceremony — same shape as [register] but for sign-in.
  Future<Map<String, dynamic>> authenticate(
    Map<String, dynamic> requestOptions,
  );
}

/// Thrown when the user cancels the platform-native dialog or the
/// authenticator returns an error.
class PasskeyCeremonyError implements Exception {
  PasskeyCeremonyError(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'PasskeyCeremonyError: $message';
}
