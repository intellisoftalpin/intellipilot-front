import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The three operations account storage needs from a secrets backend.
///
/// Deliberately narrow, and deliberately ours: `FlutterSecureStorage`'s method
/// signatures carry per-platform option types that have been renamed across
/// major versions, so depending on them directly would make every fake and
/// every call site a hostage to the plugin's next release.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Platform keychain: Keychain on Apple targets, Keystore-backed on Android.
class KeychainSecretStore implements SecretStore {
  KeychainSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Test double. Never used in the app: a refresh token must not live in memory
/// only, or a restart would sign every account out.
class InMemorySecretStore implements SecretStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}
