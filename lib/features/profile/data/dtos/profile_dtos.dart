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
    required this.createdAt,
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
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String email;
  final String username;
  final String fullName;
  final String lang;
  final String timezone;
  final bool isActive;
  final DateTime createdAt;

  UserProfile copyWith({
    String? fullName,
    String? lang,
    String? timezone,
  }) => UserProfile(
    id: id,
    email: email,
    username: username,
    fullName: fullName ?? this.fullName,
    lang: lang ?? this.lang,
    timezone: timezone ?? this.timezone,
    isActive: isActive,
    createdAt: createdAt,
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
  const AccountErasureResponse({required this.status, required this.graceUntil});

  factory AccountErasureResponse.fromJson(Map<String, dynamic> json) {
    return AccountErasureResponse(
      status: json['status'] as String? ?? 'scheduled_for_erasure',
      graceUntil: DateTime.parse(json['grace_until'] as String),
    );
  }

  final String status;
  final DateTime graceUntil;
}
