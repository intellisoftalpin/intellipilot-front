/// Wire shape of `intellipilot_core::user::User`. The backend exposes profile
/// info as a flat JSON object; everything not in this list is server-internal.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.fullName,
    required this.lang,
    required this.timezone,
    required this.isActive,
    required this.isSuperadmin,
    required this.mustChangePassword,
    required this.createdAt,
    this.authSource = 'local',
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      username: json['username'] as String,
      fullName: (json['full_name'] as String?) ?? '',
      lang: (json['lang'] as String?) ?? 'en',
      timezone: (json['timezone'] as String?) ?? 'UTC',
      isActive: json['is_active'] as bool? ?? true,
      isSuperadmin: json['is_superadmin'] as bool? ?? false,
      mustChangePassword: json['must_change_password'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      authSource: (json['auth_source'] as String?) ?? 'local',
    );
  }

  /// `'local'` (password) or `'ldap'` (directory). LDAP accounts manage their
  /// password in the directory, not in IntelliPilot.
  bool get isLdap => authSource == 'ldap';

  final String id;
  final String email;
  final String username;
  final String fullName;
  final String lang;
  final String timezone;
  final bool isActive;

  /// Platform-wide admin flag (V011). Distinct from project-level admin —
  /// gates the `/admin/*` surface in the SPA.
  final bool isSuperadmin;

  /// True when the account was created or reset by an admin and a fresh
  /// password is required before any other navigation.
  final bool mustChangePassword;
  final DateTime createdAt;
  final String authSource;

  UserProfile copyWith({
    String? fullName,
    String? lang,
    String? timezone,
    bool? mustChangePassword,
    bool? isSuperadmin,
  }) => UserProfile(
    id: id,
    email: email,
    username: username,
    fullName: fullName ?? this.fullName,
    lang: lang ?? this.lang,
    timezone: timezone ?? this.timezone,
    isActive: isActive,
    isSuperadmin: isSuperadmin ?? this.isSuperadmin,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    createdAt: createdAt,
    authSource: authSource,
  );
}

class ProfileUpdateRequest {
  const ProfileUpdateRequest({this.fullName, this.lang, this.timezone});

  final String? fullName;
  final String? lang;
  final String? timezone;

  Map<String, dynamic> toJson() => {
    if (fullName != null) 'full_name': fullName,
    if (lang != null) 'lang': lang,
    if (timezone != null) 'timezone': timezone,
  };
}

class AccountErasureResponse {
  const AccountErasureResponse({
    required this.status,
    required this.graceUntil,
  });

  factory AccountErasureResponse.fromJson(Map<String, dynamic> json) {
    return AccountErasureResponse(
      status: json['status'] as String? ?? 'scheduled_for_erasure',
      graceUntil: DateTime.parse(json['grace_until'] as String),
    );
  }

  final String status;
  final DateTime graceUntil;
}
