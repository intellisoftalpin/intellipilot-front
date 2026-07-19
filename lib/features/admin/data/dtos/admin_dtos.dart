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

/// A single auth/activity event from `GET /admin/activity`.
class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.action,
    required this.metadata,
    required this.createdAt,
    this.actorId,
    this.actorEmail,
    this.actorUsername,
    this.ip,
    this.userAgent,
  });

  factory ActivityEvent.fromJson(Map<String, dynamic> json) {
    return ActivityEvent(
      id: json['id'] as String,
      action: json['action'] as String? ?? '',
      actorId: json['actor_id'] as String?,
      actorEmail: json['actor_email'] as String?,
      actorUsername: json['actor_username'] as String?,
      ip: json['ip'] as String?,
      userAgent: json['user_agent'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String action;
  final String? actorId;
  final String? actorEmail;
  final String? actorUsername;
  final String? ip;
  final String? userAgent;

  /// Free-form, action-specific JSON (commonly `reason`, `identifier`, `via`).
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
}

/// Envelope for `GET /admin/activity`.
class ActivityList {
  const ActivityList({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory ActivityList.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map((e) => ActivityEvent.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return ActivityList(
      items: items,
      total: (json['total'] as num?)?.toInt() ?? items.length,
      limit: (json['limit'] as num?)?.toInt() ?? items.length,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }

  final List<ActivityEvent> items;
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
    this.appName,
    this.appMessage,
    this.hasCustomIcon = false,
    this.appIconUpdatedAt,
  });

  factory PlatformSettings.fromJson(Map<String, dynamic> json) {
    return PlatformSettings(
      openRegistration: json['open_registration'] as bool? ?? false,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      updatedBy: json['updated_by'] as String?,
      appName: json['app_name'] as String?,
      appMessage: json['app_message'] as String?,
      hasCustomIcon: json['has_custom_icon'] as bool? ?? false,
      appIconUpdatedAt: json['app_icon_updated_at'] as String?,
    );
  }

  final bool openRegistration;
  final DateTime updatedAt;
  final String? updatedBy;

  /// White-label name override; null means the bundled default is in use.
  final String? appName;

  /// Optional login-screen notice.
  final String? appMessage;

  /// Whether a custom app icon is stored.
  final bool hasCustomIcon;

  /// Opaque cache-busting token (RFC3339) for the custom icon URL.
  final String? appIconUpdatedAt;
}

// ---------------------------------------------------------------------------
// LDAP settings — mirror `crate::admin::dto::*Ldap*`.
// ---------------------------------------------------------------------------

/// Current LDAP configuration as returned by `GET /admin/ldap-settings`.
class LdapSettings {
  const LdapSettings({
    required this.enabled,
    required this.serverUrl,
    required this.useStartTls,
    required this.skipTlsVerify,
    required this.baseDn,
    required this.defaultDomain,
    required this.bindDnFormat,
    required this.userSearchFilter,
    required this.superadminGroup,
    required this.attrEmail,
    required this.attrDisplayName,
    required this.attrUsername,
    required this.connectionTimeoutSecs,
    required this.updatedAt,
    this.updatedBy,
    this.bindMode = 'direct',
    this.serviceBindDn = '',
    this.serviceBindPasswordSet = false,
    this.userSearchBase = '',
    this.groupSearchBase = '',
    this.groupSearchFilter = '(member=%s)',
  });

  factory LdapSettings.fromJson(Map<String, dynamic> j) => LdapSettings(
    enabled: j['enabled'] as bool? ?? false,
    serverUrl: j['server_url'] as String? ?? '',
    useStartTls: j['use_start_tls'] as bool? ?? false,
    skipTlsVerify: j['skip_tls_verify'] as bool? ?? false,
    baseDn: j['base_dn'] as String? ?? '',
    defaultDomain: j['default_domain'] as String? ?? '',
    bindDnFormat: j['bind_dn_format'] as String? ?? '%s',
    userSearchFilter:
        j['user_search_filter'] as String? ?? '(sAMAccountName=%s)',
    superadminGroup: j['superadmin_group'] as String? ?? '',
    attrEmail: j['attr_email'] as String? ?? 'mail',
    attrDisplayName: j['attr_display_name'] as String? ?? 'displayName',
    attrUsername: j['attr_username'] as String? ?? 'sAMAccountName',
    connectionTimeoutSecs:
        (j['connection_timeout_secs'] as num?)?.toInt() ?? 10,
    updatedAt: DateTime.parse(j['updated_at'] as String),
    updatedBy: j['updated_by'] as String?,
    bindMode: j['bind_mode'] as String? ?? 'direct',
    serviceBindDn: j['service_bind_dn'] as String? ?? '',
    serviceBindPasswordSet: j['service_bind_password_set'] as bool? ?? false,
    userSearchBase: j['user_search_base'] as String? ?? '',
    groupSearchBase: j['group_search_base'] as String? ?? '',
    groupSearchFilter: j['group_search_filter'] as String? ?? '(member=%s)',
  );

  final bool enabled;
  final String serverUrl;
  final bool useStartTls;
  final bool skipTlsVerify;
  final String baseDn;
  final String defaultDomain;
  final String bindDnFormat;
  final String userSearchFilter;
  final String superadminGroup;
  final String attrEmail;
  final String attrDisplayName;
  final String attrUsername;
  final int connectionTimeoutSecs;
  final DateTime updatedAt;
  final String? updatedBy;

  /// `direct` or `search`.
  final String bindMode;
  final String serviceBindDn;

  /// Whether a service-account password is stored (the value is never returned).
  final bool serviceBindPasswordSet;
  final String userSearchBase;
  final String groupSearchBase;
  final String groupSearchFilter;

  UpdateLdapSettingsRequest toUpdate() => UpdateLdapSettingsRequest(
    enabled: enabled,
    serverUrl: serverUrl,
    useStartTls: useStartTls,
    skipTlsVerify: skipTlsVerify,
    baseDn: baseDn,
    defaultDomain: defaultDomain,
    bindDnFormat: bindDnFormat,
    userSearchFilter: userSearchFilter,
    superadminGroup: superadminGroup,
    attrEmail: attrEmail,
    attrDisplayName: attrDisplayName,
    attrUsername: attrUsername,
    connectionTimeoutSecs: connectionTimeoutSecs,
    bindMode: bindMode,
    serviceBindDn: serviceBindDn,
    userSearchBase: userSearchBase,
    groupSearchBase: groupSearchBase,
    groupSearchFilter: groupSearchFilter,
  );
}

/// Body for `PUT /admin/ldap-settings` (and embedded in the test request).
class UpdateLdapSettingsRequest {
  const UpdateLdapSettingsRequest({
    required this.enabled,
    required this.serverUrl,
    required this.useStartTls,
    required this.skipTlsVerify,
    required this.baseDn,
    required this.defaultDomain,
    required this.bindDnFormat,
    required this.userSearchFilter,
    required this.superadminGroup,
    required this.attrEmail,
    required this.attrDisplayName,
    required this.attrUsername,
    required this.connectionTimeoutSecs,
    this.bindMode = 'direct',
    this.serviceBindDn = '',
    this.serviceBindPassword,
    this.userSearchBase = '',
    this.groupSearchBase = '',
    this.groupSearchFilter = '(member=%s)',
  });

  final bool enabled;
  final String serverUrl;
  final bool useStartTls;
  final bool skipTlsVerify;
  final String baseDn;
  final String defaultDomain;
  final String bindDnFormat;
  final String userSearchFilter;
  final String superadminGroup;
  final String attrEmail;
  final String attrDisplayName;
  final String attrUsername;
  final int connectionTimeoutSecs;

  /// `direct` (bind as the user) or `search` (service-account search then bind).
  final String bindMode;
  final String serviceBindDn;

  /// `null` keeps the stored service password; a non-null value replaces it.
  final String? serviceBindPassword;
  final String userSearchBase;
  final String groupSearchBase;
  final String groupSearchFilter;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'server_url': serverUrl,
    'use_start_tls': useStartTls,
    'skip_tls_verify': skipTlsVerify,
    'base_dn': baseDn,
    'default_domain': defaultDomain,
    'bind_dn_format': bindDnFormat,
    'user_search_filter': userSearchFilter,
    'superadmin_group': superadminGroup,
    'attr_email': attrEmail,
    'attr_display_name': attrDisplayName,
    'attr_username': attrUsername,
    'connection_timeout_secs': connectionTimeoutSecs,
    'bind_mode': bindMode,
    'service_bind_dn': serviceBindDn,
    if (serviceBindPassword != null)
      'service_bind_password': serviceBindPassword,
    'user_search_base': userSearchBase,
    'group_search_base': groupSearchBase,
    'group_search_filter': groupSearchFilter,
  };
}

/// Result of `POST /admin/ldap-settings/test`.
class LdapTestResult {
  const LdapTestResult({
    required this.ok,
    required this.message,
    this.email,
    this.username,
    this.displayName,
    this.wouldBeSuperadmin,
  });

  factory LdapTestResult.fromJson(Map<String, dynamic> j) => LdapTestResult(
    ok: j['ok'] as bool? ?? false,
    message: j['message'] as String? ?? '',
    email: j['email'] as String?,
    username: j['username'] as String?,
    displayName: j['display_name'] as String?,
    wouldBeSuperadmin: j['would_be_superadmin'] as bool?,
  );

  final bool ok;
  final String message;
  final String? email;
  final String? username;
  final String? displayName;
  final bool? wouldBeSuperadmin;
}

// ---------------------------------------------------------------------------
// Notification settings
// ---------------------------------------------------------------------------

/// Current notification config. Secrets are never returned by the API — only
/// the `*Set` booleans indicate whether a value is stored.
class NotificationSettings {
  const NotificationSettings({
    required this.mailEnabled,
    required this.mailProvider,
    required this.mailFromAddress,
    required this.mailFromName,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUsername,
    required this.smtpPasswordSet,
    required this.smtpUseStarttls,
    required this.smtpSkipTlsVerify,
    required this.mailgunApiKeySet,
    required this.mailgunDomain,
    required this.mailgunBaseUrl,
    required this.matrixEnabled,
    required this.matrixHomeserver,
    required this.matrixRoomId,
    required this.matrixAccessTokenSet,
    required this.telegramEnabled,
    required this.telegramBotTokenSet,
    required this.telegramChatId,
    required this.mailOnLogin,
    required this.mailOnIssueCreated,
    required this.mailOnIssueResolved,
    required this.mailOnDailyReport,
    required this.msgOnLogin,
    required this.msgOnIssueCreated,
    required this.msgOnIssueResolved,
    required this.msgOnDailyReport,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> j) {
    bool b(String k) => j[k] as bool? ?? false;
    String s(String k) => j[k] as String? ?? '';
    return NotificationSettings(
      mailEnabled: b('mail_enabled'),
      mailProvider: j['mail_provider'] as String? ?? 'smtp',
      mailFromAddress: s('mail_from_address'),
      mailFromName: s('mail_from_name'),
      smtpHost: s('smtp_host'),
      smtpPort: (j['smtp_port'] as num?)?.toInt() ?? 587,
      smtpUsername: s('smtp_username'),
      smtpPasswordSet: b('smtp_password_set'),
      smtpUseStarttls: j['smtp_use_starttls'] as bool? ?? true,
      smtpSkipTlsVerify: b('smtp_skip_tls_verify'),
      mailgunApiKeySet: b('mailgun_api_key_set'),
      mailgunDomain: s('mailgun_domain'),
      mailgunBaseUrl: s('mailgun_base_url'),
      matrixEnabled: b('matrix_enabled'),
      matrixHomeserver: s('matrix_homeserver'),
      matrixRoomId: s('matrix_room_id'),
      matrixAccessTokenSet: b('matrix_access_token_set'),
      telegramEnabled: b('telegram_enabled'),
      telegramBotTokenSet: b('telegram_bot_token_set'),
      telegramChatId: s('telegram_chat_id'),
      mailOnLogin: b('mail_on_login'),
      mailOnIssueCreated: b('mail_on_issue_created'),
      mailOnIssueResolved: b('mail_on_issue_resolved'),
      mailOnDailyReport: b('mail_on_daily_report'),
      msgOnLogin: b('msg_on_login'),
      msgOnIssueCreated: b('msg_on_issue_created'),
      msgOnIssueResolved: b('msg_on_issue_resolved'),
      msgOnDailyReport: b('msg_on_daily_report'),
    );
  }

  final bool mailEnabled;
  final String mailProvider;
  final String mailFromAddress;
  final String mailFromName;
  final String smtpHost;
  final int smtpPort;
  final String smtpUsername;
  final bool smtpPasswordSet;
  final bool smtpUseStarttls;
  final bool smtpSkipTlsVerify;
  final bool mailgunApiKeySet;
  final String mailgunDomain;
  final String mailgunBaseUrl;
  final bool matrixEnabled;
  final String matrixHomeserver;
  final String matrixRoomId;
  final bool matrixAccessTokenSet;
  final bool telegramEnabled;
  final bool telegramBotTokenSet;
  final String telegramChatId;
  final bool mailOnLogin;
  final bool mailOnIssueCreated;
  final bool mailOnIssueResolved;
  final bool mailOnDailyReport;
  final bool msgOnLogin;
  final bool msgOnIssueCreated;
  final bool msgOnIssueResolved;
  final bool msgOnDailyReport;
}

/// Update payload. Secret fields carry the raw value the admin typed; an empty
/// string means "keep the stored secret" (the backend treats blank as unchanged).
class NotificationSettingsUpdate {
  const NotificationSettingsUpdate({
    required this.mailEnabled,
    required this.mailProvider,
    required this.mailFromAddress,
    required this.mailFromName,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUsername,
    required this.smtpPassword,
    required this.smtpUseStarttls,
    required this.smtpSkipTlsVerify,
    required this.mailgunApiKey,
    required this.mailgunDomain,
    required this.mailgunBaseUrl,
    required this.matrixEnabled,
    required this.matrixHomeserver,
    required this.matrixRoomId,
    required this.matrixAccessToken,
    required this.telegramEnabled,
    required this.telegramBotToken,
    required this.telegramChatId,
    required this.mailOnLogin,
    required this.mailOnIssueCreated,
    required this.mailOnIssueResolved,
    required this.mailOnDailyReport,
    required this.msgOnLogin,
    required this.msgOnIssueCreated,
    required this.msgOnIssueResolved,
    required this.msgOnDailyReport,
  });

  final bool mailEnabled;
  final String mailProvider;
  final String mailFromAddress;
  final String mailFromName;
  final String smtpHost;
  final int smtpPort;
  final String smtpUsername;
  final String smtpPassword;
  final bool smtpUseStarttls;
  final bool smtpSkipTlsVerify;
  final String mailgunApiKey;
  final String mailgunDomain;
  final String mailgunBaseUrl;
  final bool matrixEnabled;
  final String matrixHomeserver;
  final String matrixRoomId;
  final String matrixAccessToken;
  final bool telegramEnabled;
  final String telegramBotToken;
  final String telegramChatId;
  final bool mailOnLogin;
  final bool mailOnIssueCreated;
  final bool mailOnIssueResolved;
  final bool mailOnDailyReport;
  final bool msgOnLogin;
  final bool msgOnIssueCreated;
  final bool msgOnIssueResolved;
  final bool msgOnDailyReport;

  Map<String, dynamic> toJson() => {
    'mail_enabled': mailEnabled,
    'mail_provider': mailProvider,
    'mail_from_address': mailFromAddress,
    'mail_from_name': mailFromName,
    'smtp_host': smtpHost,
    'smtp_port': smtpPort,
    'smtp_username': smtpUsername,
    'smtp_password': smtpPassword,
    'smtp_use_starttls': smtpUseStarttls,
    'smtp_skip_tls_verify': smtpSkipTlsVerify,
    'mailgun_api_key': mailgunApiKey,
    'mailgun_domain': mailgunDomain,
    'mailgun_base_url': mailgunBaseUrl,
    'matrix_enabled': matrixEnabled,
    'matrix_homeserver': matrixHomeserver,
    'matrix_room_id': matrixRoomId,
    'matrix_access_token': matrixAccessToken,
    'telegram_enabled': telegramEnabled,
    'telegram_bot_token': telegramBotToken,
    'telegram_chat_id': telegramChatId,
    'mail_on_login': mailOnLogin,
    'mail_on_issue_created': mailOnIssueCreated,
    'mail_on_issue_resolved': mailOnIssueResolved,
    'mail_on_daily_report': mailOnDailyReport,
    'msg_on_login': msgOnLogin,
    'msg_on_issue_created': msgOnIssueCreated,
    'msg_on_issue_resolved': msgOnIssueResolved,
    'msg_on_daily_report': msgOnDailyReport,
  };
}

/// One remembered renamed-away project prefix (short-link history).
class ProjectPrefixHistoryEntry {
  const ProjectPrefixHistoryEntry({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.prefix,
    required this.replacedAt,
  });

  factory ProjectPrefixHistoryEntry.fromJson(Map<String, dynamic> j) =>
      ProjectPrefixHistoryEntry(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        projectName: j['project_name'] as String? ?? '',
        prefix: j['prefix'] as String,
        replacedAt: DateTime.parse(j['replaced_at'] as String),
      );

  final String id;
  final String projectId;
  final String projectName;
  final String prefix;
  final DateTime replacedAt;
}

/// One remembered renamed-away board key (short-link history).
class BoardKeyHistoryEntry {
  const BoardKeyHistoryEntry({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.boardId,
    required this.boardName,
    required this.boardKey,
    required this.replacedAt,
  });

  factory BoardKeyHistoryEntry.fromJson(Map<String, dynamic> j) =>
      BoardKeyHistoryEntry(
        id: j['id'] as String,
        projectId: j['project_id'] as String,
        projectName: j['project_name'] as String? ?? '',
        boardId: j['board_id'] as String,
        boardName: j['board_name'] as String? ?? '',
        boardKey: j['key'] as String,
        replacedAt: DateTime.parse(j['replaced_at'] as String),
      );

  final String id;
  final String projectId;
  final String projectName;
  final String boardId;
  final String boardName;
  final String boardKey;
  final DateTime replacedAt;
}

/// Both halves of the short-link rename history.
class ShortLinkHistory {
  const ShortLinkHistory({required this.projects, required this.boards});

  factory ShortLinkHistory.fromJson(Map<String, dynamic> j) => ShortLinkHistory(
    projects: [
      for (final e in j['projects'] as List<dynamic>? ?? const [])
        ProjectPrefixHistoryEntry.fromJson(e as Map<String, dynamic>),
    ],
    boards: [
      for (final e in j['boards'] as List<dynamic>? ?? const [])
        BoardKeyHistoryEntry.fromJson(e as Map<String, dynamic>),
    ],
  );

  final List<ProjectPrefixHistoryEntry> projects;
  final List<BoardKeyHistoryEntry> boards;

  bool get isEmpty => projects.isEmpty && boards.isEmpty;
}

/// Result of a "send test" action.
class NotificationTestResult {
  const NotificationTestResult({required this.ok, required this.message});

  factory NotificationTestResult.fromJson(Map<String, dynamic> j) =>
      NotificationTestResult(
        ok: j['ok'] as bool? ?? false,
        message: j['message'] as String? ?? '',
      );

  final bool ok;
  final String message;
}
