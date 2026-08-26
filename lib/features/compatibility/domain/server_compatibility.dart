import 'package:flutter/foundation.dart';

/// How the client's version compares to the server's.
enum CompatibilityStatus {
  /// Same `major.minor`, or the client is ahead. Usable.
  ok,

  /// The client's `major.minor` is behind the server's. Blocked.
  clientTooOld,

  /// Not established yet, or the probe failed. Treated as usable — a network
  /// blip must never lock a working app out.
  unknown,
}

/// A `major.minor` pair, which is the granularity compatibility is judged at.
///
/// Patch releases are deliberately ignored: an installed app cannot track a
/// customer's server patch-for-patch, and blocking on every patch would break
/// every client for days while an app store review runs.
@immutable
class VersionPair {
  const VersionPair(this.major, this.minor);

  /// Parse a leading `major.minor` from a semver-ish string. Returns null for
  /// anything unrecognisable, which callers treat as "cannot judge".
  static VersionPair? parse(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^\s*v?(\d+)\.(\d+)').firstMatch(raw);
    if (m == null) return null;
    final major = int.tryParse(m.group(1)!);
    final minor = int.tryParse(m.group(2)!);
    if (major == null || minor == null) return null;
    return VersionPair(major, minor);
  }

  final int major;
  final int minor;

  /// Negative when this is older than [other], 0 when equal.
  int compareTo(VersionPair other) => major != other.major
      ? major.compareTo(other.major)
      : minor.compareTo(other.minor);

  bool isOlderThan(VersionPair other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is VersionPair && other.major == major && other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}

/// Decide whether a client build may talk to a server build.
///
/// Only one case blocks: the client's `major.minor` being **behind** the
/// server's. A client that is ahead keeps working, and anything unparseable or
/// missing is treated as usable — refusing to run because a version string
/// looked odd would be worse than the mismatch it guards against.
CompatibilityStatus judge({
  required String? clientVersion,
  required String? serverVersion,
}) {
  final client = VersionPair.parse(clientVersion);
  final server = VersionPair.parse(serverVersion);
  if (client == null || server == null) return CompatibilityStatus.unknown;
  return client.isOlderThan(server)
      ? CompatibilityStatus.clientTooOld
      : CompatibilityStatus.ok;
}
