import 'package:intellipilot/core/models/user_ref.dart';

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
    this.excludeFromTimeReports = false,
    this.card = const UserCard(),
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
      excludeFromTimeReports:
          json['exclude_from_time_reports'] as bool? ?? false,
      card: UserCard.fromJson(json),
    );
  }

  /// The shared user descriptor used by the avatar widget + hover card.
  UserRef toRef() => UserRef(
    id: id,
    username: username,
    fullName: fullName,
    email: email,
    card: card,
  );

  /// `'local'` (password) or `'ldap'` (directory). LDAP accounts manage their
  /// password in the directory, not in IntelliPilot.
  bool get isLdap => authSource == 'ldap';

  /// Provisioned by an identity provider on first single sign-on (V025) and
  /// holding no local password.
  ///
  /// A user who *linked* a provider to an account they already had keeps their
  /// original source: linking adds a way in, it does not take the password
  /// away.
  bool get isOidc => authSource == 'oidc';

  /// Whether the password lives somewhere other than IntelliPilot, so the
  /// change-password and reset flows do not apply. The server draws the same
  /// line with `auth_source != "local"`.
  bool get isExternallyAuthenticated => authSource != 'local';

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

  /// Hidden from timesheet reports (team grids, project time lists and
  /// exports) and not warned about unfilled days. Does NOT restrict their
  /// own time tracking.
  final bool excludeFromTimeReports;

  /// True when the account was created or reset by an admin and a fresh
  /// password is required before any other navigation.
  final bool mustChangePassword;
  final DateTime createdAt;
  final String authSource;
  final UserCard card;

  UserProfile copyWith({
    String? fullName,
    String? lang,
    String? timezone,
    bool? mustChangePassword,
    bool? isSuperadmin,
    bool? excludeFromTimeReports,
    UserCard? card,
  }) => UserProfile(
    id: id,
    email: email,
    username: username,
    fullName: fullName ?? this.fullName,
    lang: lang ?? this.lang,
    timezone: timezone ?? this.timezone,
    isActive: isActive,
    isSuperadmin: isSuperadmin ?? this.isSuperadmin,
    excludeFromTimeReports:
        excludeFromTimeReports ?? this.excludeFromTimeReports,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    createdAt: createdAt,
    authSource: authSource,
    card: card ?? this.card,
  );
}

class ProfileUpdateRequest {
  const ProfileUpdateRequest({
    this.fullName,
    this.lang,
    this.timezone,
    this.motto,
    this.moodEmoji,
    this.moodText,
  });

  final String? fullName;
  final String? lang;
  final String? timezone;
  final String? motto;
  final String? moodEmoji;
  final String? moodText;

  Map<String, dynamic> toJson() => {
    if (fullName != null) 'full_name': fullName,
    if (lang != null) 'lang': lang,
    if (timezone != null) 'timezone': timezone,
    if (motto != null) 'motto': motto,
    if (moodEmoji != null) 'mood_emoji': moodEmoji,
    if (moodText != null) 'mood_text': moodText,
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
