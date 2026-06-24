import 'package:intellipilot/features/projects/domain/permission.dart';

/// Mirrors `intellipilot_core::app_token::AppToken`. Never carries the secret —
/// only the [prefix] + [last4] display hints.
class AppTokenDto {
  const AppTokenDto({
    required this.id,
    required this.name,
    required this.prefix,
    required this.last4,
    required this.permissions,
    required this.projectIds,
    required this.createdBy,
    required this.expiresAt,
    required this.revokedAt,
    required this.lastUsedAt,
    required this.createdAt,
  });

  factory AppTokenDto.fromJson(Map<String, dynamic> json) {
    final perms = ((json['permissions'] as List<dynamic>?) ?? const [])
        .map((e) => Permission.fromWire(e as String))
        .whereType<Permission>()
        .toSet();
    DateTime? date(String key) {
      final v = json[key] as String?;
      return v == null ? null : DateTime.tryParse(v);
    }

    return AppTokenDto(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      prefix: json['prefix'] as String? ?? '',
      last4: json['last4'] as String? ?? '',
      permissions: perms,
      projectIds: ((json['project_ids'] as List<dynamic>?) ?? const [])
          .map((e) => e as String)
          .toList(),
      createdBy: json['created_by'] as String?,
      expiresAt: date('expires_at'),
      revokedAt: date('revoked_at'),
      lastUsedAt: date('last_used_at'),
      createdAt: date('created_at') ?? DateTime.now(),
    );
  }

  final String id;
  final String name;
  final String prefix;
  final String last4;
  final Set<Permission> permissions;
  final List<String> projectIds;
  final String? createdBy;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final DateTime? lastUsedAt;
  final DateTime createdAt;

  bool get isRevoked => revokedAt != null;
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isActive => !isRevoked && !isExpired;

  /// Masked identifier, e.g. `ipat_Ab12cd…wx90`.
  String get masked => '$prefix…$last4';
}

class CreateAppTokenRequest {
  const CreateAppTokenRequest({
    required this.name,
    required this.permissions,
    required this.projectIds,
    this.expiresAt,
  });

  final String name;
  final Set<Permission> permissions;
  final List<String> projectIds;
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() => {
    'name': name,
    'permissions': permissions.map((p) => p.wire).toList(),
    'project_ids': projectIds,
    if (expiresAt != null)
      'expires_at': expiresAt!.toUtc().toIso8601String(),
  };
}

/// One-time create response: the raw [secret] is shown once and never stored.
class CreateAppTokenResult {
  const CreateAppTokenResult({required this.token, required this.secret});

  factory CreateAppTokenResult.fromJson(Map<String, dynamic> json) =>
      CreateAppTokenResult(
        token: AppTokenDto.fromJson(json['token'] as Map<String, dynamic>),
        secret: json['secret'] as String,
      );

  final AppTokenDto token;
  final String secret;
}

class UpdateAppTokenRequest {
  const UpdateAppTokenRequest({this.name, this.permissions, this.projectIds});

  final String? name;
  final Set<Permission>? permissions;
  final List<String>? projectIds;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (permissions != null)
      'permissions': permissions!.map((p) => p.wire).toList(),
    if (projectIds != null) 'project_ids': projectIds,
  };
}
