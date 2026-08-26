import 'package:flutter/foundation.dart';

/// One signed-in account: a user **on a particular server**.
///
/// Identity is the `(serverUrl, userId)` pair, not the user alone. The same
/// person can hold accounts on several instances, and two different people can
/// share a username across instances — so neither half identifies an account by
/// itself. This is also why the switcher shows the server first: it is the
/// distinguishing value.
@immutable
class Account {
  const Account({
    required this.serverUrl,
    required this.userId,
    required this.username,
    required this.email,
    this.fullName = '',
    this.avatarUpdatedAt,
    this.lastUsedAt,
    this.lastRoute,
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    serverUrl: j['server_url'] as String,
    userId: j['user_id'] as String,
    username: (j['username'] as String?) ?? '',
    email: (j['email'] as String?) ?? '',
    fullName: (j['full_name'] as String?) ?? '',
    avatarUpdatedAt: j['avatar_updated_at'] as String?,
    lastUsedAt: j['last_used_at'] == null
        ? null
        : DateTime.tryParse(j['last_used_at'] as String),
    lastRoute: j['last_route'] as String?,
  );

  final String serverUrl;
  final String userId;
  final String username;
  final String email;
  final String fullName;
  final String? avatarUpdatedAt;

  /// Drives "switch to the next account" after a logout.
  final DateTime? lastUsedAt;

  /// The route this account was last on, restored when switching back. Route
  /// only — no scroll position, no open dialogs.
  final String? lastRoute;

  /// Stable key for this account, used for cache namespacing and storage keys.
  ///
  /// Hashed rather than concatenated so it stays short and free of characters
  /// that would need escaping in a storage key, and so a server URL change
  /// cannot silently alias two accounts together.
  String get key => '${_slug(serverUrl)}~$userId';

  /// What the switcher shows on its first line: the host, plus the port when it
  /// is not the scheme default. An IP address renders as-is, which is the point
  /// — a LAN instance has no domain to show.
  String get serverLabel {
    final uri = Uri.tryParse(serverUrl);
    if (uri == null || uri.host.isEmpty) return serverUrl;
    final isDefaultPort =
        !uri.hasPort ||
        (uri.scheme == 'https' && uri.port == 443) ||
        (uri.scheme == 'http' && uri.port == 80);
    return isDefaultPort ? uri.host : '${uri.host}:${uri.port}';
  }

  /// Second line: whatever best identifies the person.
  String get userLabel =>
      username.isNotEmpty ? username : (email.isNotEmpty ? email : userId);

  Map<String, dynamic> toJson() => {
    'server_url': serverUrl,
    'user_id': userId,
    'username': username,
    'email': email,
    'full_name': fullName,
    if (avatarUpdatedAt != null) 'avatar_updated_at': avatarUpdatedAt,
    if (lastUsedAt != null) 'last_used_at': lastUsedAt!.toIso8601String(),
    if (lastRoute != null) 'last_route': lastRoute,
  };

  Account copyWith({
    String? username,
    String? email,
    String? fullName,
    String? avatarUpdatedAt,
    DateTime? lastUsedAt,
    Object? lastRoute = _keep,
  }) => Account(
    serverUrl: serverUrl,
    userId: userId,
    username: username ?? this.username,
    email: email ?? this.email,
    fullName: fullName ?? this.fullName,
    avatarUpdatedAt: avatarUpdatedAt ?? this.avatarUpdatedAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    lastRoute: lastRoute == _keep ? this.lastRoute : lastRoute as String?,
  );

  static const _keep = Object();

  /// Lowercase, punctuation-free form of a URL, safe inside a storage key.
  static String _slug(String url) =>
      url.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.serverUrl == serverUrl &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(serverUrl, userId);

  @override
  String toString() => 'Account($serverLabel / $userLabel)';
}
