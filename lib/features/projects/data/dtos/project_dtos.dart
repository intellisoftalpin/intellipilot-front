import 'package:intellipilot/features/projects/domain/permission.dart';

enum ProjectVisibility {
  private('private'),
  internal('internal'),
  publicReadonly('public_readonly');

  const ProjectVisibility(this.wire);
  final String wire;

  static ProjectVisibility fromWire(String wire) {
    for (final v in ProjectVisibility.values) {
      if (v.wire == wire) return v;
    }
    return ProjectVisibility.private;
  }
}

class Project {
  const Project({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.visibility,
    required this.kanbanEnabled,
    required this.backlogEnabled,
    required this.wikiEnabled,
    required this.epicsEnabled,
    required this.createdAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      ownerId: json['owner_id'] as String,
      visibility: ProjectVisibility.fromWire(
        (json['visibility'] as String?) ?? 'private',
      ),
      kanbanEnabled: json['kanban_enabled'] as bool? ?? true,
      backlogEnabled: json['backlog_enabled'] as bool? ?? true,
      wikiEnabled: json['wiki_enabled'] as bool? ?? true,
      epicsEnabled: json['epics_enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String slug;
  final String name;
  final String description;
  final String ownerId;
  final ProjectVisibility visibility;
  final bool kanbanEnabled;
  final bool backlogEnabled;
  final bool wikiEnabled;
  final bool epicsEnabled;
  final DateTime createdAt;
}

class Role {
  const Role({
    required this.id,
    required this.projectId,
    required this.slug,
    required this.name,
    required this.order,
    required this.isAdmin,
    required this.permissions,
  });

  factory Role.fromJson(Map<String, dynamic> json) {
    final raw = (json['permissions'] as List<dynamic>? ?? const [])
        .map((p) => Permission.fromWire(p as String))
        .whereType<Permission>()
        .toSet();
    return Role(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      order: (json['order'] as num?)?.toInt() ?? 0,
      isAdmin: json['is_admin'] as bool? ?? false,
      permissions: raw,
    );
  }

  final String id;
  final String projectId;
  final String slug;
  final String name;
  final int order;
  final bool isAdmin;
  final Set<Permission> permissions;
}

class Membership {
  const Membership({
    required this.id,
    required this.projectId,
    required this.userId,
    required this.roleId,
    required this.roleSlug,
    required this.createdAt,
    this.username = '',
    this.fullName = '',
    this.email = '',
  });

  factory Membership.fromJson(Map<String, dynamic> json) {
    return Membership(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      roleId: json['role_id'] as String,
      roleSlug: json['role_slug'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Best human-readable label: full name, else username, else email, else id.
  String get displayName {
    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    if (email.isNotEmpty) return email;
    return userId;
  }

  final String id;
  final String projectId;
  final String userId;
  final String username;
  final String fullName;
  final String email;
  final String roleId;
  final String roleSlug;
  final DateTime createdAt;
}

class Invitation {
  const Invitation({
    required this.id,
    required this.projectId,
    required this.email,
    required this.roleId,
    required this.createdAt,
  });

  factory Invitation.fromJson(Map<String, dynamic> json) {
    return Invitation(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      email: json['email'] as String,
      roleId: json['role_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String projectId;
  final String email;
  final String roleId;
  final DateTime createdAt;
}

class InviteResponse {
  const InviteResponse({required this.invitationId, this.inviteToken});

  factory InviteResponse.fromJson(Map<String, dynamic> json) {
    return InviteResponse(
      invitationId: json['invitation_id'] as String,
      inviteToken: json['invite_token'] as String?,
    );
  }

  final String invitationId;

  /// Dev-only raw token surfaced when no mailer is configured.
  final String? inviteToken;
}

// ---- request bodies ----

class CreateProjectRequest {
  const CreateProjectRequest({
    required this.name,
    this.slug,
    this.description = '',
    this.visibility,
  });

  final String name;
  final String? slug;
  final String description;
  final ProjectVisibility? visibility;

  Map<String, dynamic> toJson() => {
    'name': name,
    if (slug != null) 'slug': slug,
    'description': description,
    if (visibility != null) 'visibility': visibility!.wire,
  };
}

class UpdateProjectRequest {
  const UpdateProjectRequest({
    this.name,
    this.description,
    this.visibility,
    this.kanbanEnabled,
    this.backlogEnabled,
    this.wikiEnabled,
    this.epicsEnabled,
  });

  final String? name;
  final String? description;
  final ProjectVisibility? visibility;
  final bool? kanbanEnabled;
  final bool? backlogEnabled;
  final bool? wikiEnabled;
  final bool? epicsEnabled;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    if (visibility != null) 'visibility': visibility!.wire,
    if (kanbanEnabled != null) 'kanban_enabled': kanbanEnabled,
    if (backlogEnabled != null) 'backlog_enabled': backlogEnabled,
    if (wikiEnabled != null) 'wiki_enabled': wikiEnabled,
    if (epicsEnabled != null) 'epics_enabled': epicsEnabled,
  };
}

class CreateRoleRequest {
  const CreateRoleRequest({
    required this.name,
    required this.slug,
    this.permissions = const {},
  });

  final String name;
  final String slug;
  final Set<Permission> permissions;

  Map<String, dynamic> toJson() => {
    'name': name,
    'slug': slug,
    'permissions': permissions.map((p) => p.wire).toList(),
  };
}

class UpdateRoleRequest {
  const UpdateRoleRequest({this.name, this.permissions});

  final String? name;
  final Set<Permission>? permissions;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (permissions != null)
      'permissions': permissions!.map((p) => p.wire).toList(),
  };
}

class InviteRequest {
  const InviteRequest({required this.email, required this.role});

  final String email;

  /// Role slug.
  final String role;

  Map<String, dynamic> toJson() => {'email': email, 'role': role};
}

class ChangeMemberRoleRequest {
  const ChangeMemberRoleRequest(this.role);

  /// New role slug.
  final String role;

  Map<String, dynamic> toJson() => {'role': role};
}
