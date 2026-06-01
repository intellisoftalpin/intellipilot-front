import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';

/// Mirrors `crate::admin::dto::UserListResponse`.
class AdminUserList {
  const AdminUserList({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory AdminUserList.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map((e) => UserProfile.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return AdminUserList(
      items: items,
      total: (json['total'] as num?)?.toInt() ?? items.length,
      limit: (json['limit'] as num?)?.toInt() ?? items.length,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }

  final List<UserProfile> items;
  final int total;
  final int limit;
  final int offset;
}

class CreateUserRequest {
  const CreateUserRequest({
    required this.email,
    required this.username,
    this.fullName = '',
    this.password,
    this.isSuperadmin = false,
  });

  final String email;
  final String username;
  final String fullName;
  /// When null, the server generates a 24-char temporary password and returns
  /// it ONCE in [CreateUserResponse.generatedPassword].
  final String? password;
  final bool isSuperadmin;

  Map<String, dynamic> toJson() => {
    'email': email,
    'username': username,
    'full_name': fullName,
    if (password != null && password!.isNotEmpty) 'password': password,
    'is_superadmin': isSuperadmin,
  };
}

class CreateUserResponse {
  const CreateUserResponse({required this.user, this.generatedPassword});

  factory CreateUserResponse.fromJson(Map<String, dynamic> json) {
    return CreateUserResponse(
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
      generatedPassword: json['generated_password'] as String?,
    );
  }

  final UserProfile user;
  /// Present only when the server generated the password — display once.
  final String? generatedPassword;
}

class UpdateUserRequest {
  const UpdateUserRequest({this.isActive, this.isSuperadmin, this.fullName});

  final bool? isActive;
  final bool? isSuperadmin;
  final String? fullName;

  Map<String, dynamic> toJson() => {
    if (isActive != null) 'is_active': isActive,
    if (isSuperadmin != null) 'is_superadmin': isSuperadmin,
    if (fullName != null) 'full_name': fullName,
  };
}

class PasswordResetIssued {
  const PasswordResetIssued({required this.expiresAt, this.resetToken});

  factory PasswordResetIssued.fromJson(Map<String, dynamic> json) {
    return PasswordResetIssued(
      resetToken: json['reset_token'] as String?,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final String? resetToken;
  final DateTime expiresAt;
}

class CreateInvitationRequest {
  const CreateInvitationRequest({required this.email, this.role = 'user'});

  final String email;
  final String role; // 'user' or 'superadmin'

  Map<String, dynamic> toJson() => {'email': email, 'role': role};
}

class CreateInvitationResponse {
  const CreateInvitationResponse({
    required this.invitationId,
    required this.email,
    required this.role,
    required this.expiresAt,
    this.inviteToken,
  });

  factory CreateInvitationResponse.fromJson(Map<String, dynamic> json) {
    return CreateInvitationResponse(
      invitationId: json['invitation_id'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      inviteToken: json['invite_token'] as String?,
    );
  }

  final String invitationId;
  final String email;
  final String role;
  final DateTime expiresAt;
  /// Raw token, present only when the mailer is not configured (dev). Display
  /// to the admin so they can copy-paste an invite link.
  final String? inviteToken;
}

class PendingInvitation {
  const PendingInvitation({
    required this.id,
    required this.email,
    required this.role,
    required this.expiresAt,
    required this.createdAt,
    this.invitedBy,
  });

  factory PendingInvitation.fromJson(Map<String, dynamic> json) {
    return PendingInvitation(
      id: json['id'] as String,
      email: json['email'] as String,
      role: (json['role'] as String?) ?? 'user',
      invitedBy: json['invited_by'] as String?,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String email;
  final String role;
  final String? invitedBy;
  final DateTime expiresAt;
  final DateTime createdAt;
}

class PlatformSettings {
  const PlatformSettings({
    required this.openRegistration,
    required this.updatedAt,
    this.updatedBy,
  });

  factory PlatformSettings.fromJson(Map<String, dynamic> json) {
    return PlatformSettings(
      openRegistration: json['open_registration'] as bool? ?? false,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      updatedBy: json['updated_by'] as String?,
    );
  }

  final bool openRegistration;
  final DateTime updatedAt;
  final String? updatedBy;
}
