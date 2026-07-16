/// Personal app token DTOs (`/api/v1/me/app-token`).
///
/// Every user can hold exactly one personal token. Reads carry only the
/// masked hints; the raw secret appears once, in the create/reset response.
class PersonalTokenDto {
  const PersonalTokenDto({
    required this.id,
    required this.prefix,
    required this.last4,
    required this.createdAt,
    this.disabledAt,
    this.lastUsedAt,
  });

  factory PersonalTokenDto.fromJson(Map<String, dynamic> json) {
    return PersonalTokenDto(
      id: json['id'] as String,
      prefix: json['prefix'] as String,
      last4: json['last4'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      disabledAt: json['disabled_at'] == null
          ? null
          : DateTime.parse(json['disabled_at'] as String),
      lastUsedAt: json['last_used_at'] == null
          ? null
          : DateTime.parse(json['last_used_at'] as String),
    );
  }

  final String id;
  final String prefix;
  final String last4;
  final DateTime createdAt;
  final DateTime? disabledAt;
  final DateTime? lastUsedAt;

  bool get isDisabled => disabledAt != null;

  /// Masked display form, e.g. `ippt_Ab12cd…wx90`.
  String get masked => '$prefix…$last4';
}

/// Create/reset response: the token plus its one-time raw secret.
class PersonalTokenSecretResult {
  const PersonalTokenSecretResult({required this.token, required this.secret});

  factory PersonalTokenSecretResult.fromJson(Map<String, dynamic> json) {
    return PersonalTokenSecretResult(
      token: PersonalTokenDto.fromJson(json['token'] as Map<String, dynamic>),
      secret: json['secret'] as String,
    );
  }

  final PersonalTokenDto token;

  /// Shown exactly once — never persisted client-side.
  final String secret;
}
