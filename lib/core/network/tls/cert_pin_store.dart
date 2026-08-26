import 'package:intellipilot/core/storage/hive_boxes.dart';

/// Certificates the user has explicitly chosen to trust, per host and port.
///
/// **There is deliberately no "trust everything" mode.** A pin authorises one
/// exact certificate for one exact `host:port`, matched on its full SHA-256.
/// Anything else — a different host, a different certificate on the same host,
/// a renewed certificate — is rejected and has to be confirmed again. That last
/// case is mildly annoying and entirely intentional: a certificate changing
/// under you is exactly when you want to be asked.
class CertPinStore {
  CertPinStore(this._storage);

  final KeyValueStorage _storage;

  static String _key(String host, int port) => 'tls.pin:$host:$port';

  /// The pinned fingerprint for `host:port`, if the user trusted one.
  String? pinFor(String host, int port) {
    final v = _storage.get<String>(_key(host, port));
    return (v == null || v.isEmpty) ? null : v;
  }

  bool hasPinFor(String host, int port) => pinFor(host, port) != null;

  /// Whether `sha256` is the exact certificate the user trusted for this
  /// host:port. Case-insensitive because fingerprint formatting varies.
  bool isTrusted(String host, int port, String sha256) {
    final pinned = pinFor(host, port);
    if (pinned == null) return false;
    return pinned.toLowerCase() == sha256.toLowerCase();
  }

  Future<void> pin(String host, int port, String sha256) =>
      _storage.set<String>(_key(host, port), sha256.toLowerCase());

  Future<void> unpin(String host, int port) =>
      _storage.remove(_key(host, port));
}
