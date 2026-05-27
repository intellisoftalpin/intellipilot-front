import 'package:intellipilot/features/mfa/data/passkey_service.dart';

/// Native stub. Until per-platform WebAuthn bindings land we expose a no-op
/// service whose `isSupported` is false; callers gate UI on that flag.
class _NativePasskeyService implements PasskeyService {
  const _NativePasskeyService();

  @override
  bool get isSupported => false;

  @override
  Future<Map<String, dynamic>> register(
    Map<String, dynamic> creationOptions,
  ) async {
    throw PasskeyCeremonyError(
      'Passkeys are not yet supported on this platform.',
    );
  }

  @override
  Future<Map<String, dynamic>> authenticate(
    Map<String, dynamic> requestOptions,
  ) async {
    throw PasskeyCeremonyError(
      'Passkeys are not yet supported on this platform.',
    );
  }
}

PasskeyService createPasskeyService() => const _NativePasskeyService();
