// Demo-mode in-memory implementations of every repository. Backed by a
// shared [DemoStore]. The behaviour aims for "good enough to click through" —
// shape mirrors the real wire DTOs but skips niceties like server-side
// validation.
//
// Update requests that mirror the backend's `_Absent` sentinel are processed
// by inspecting `body.toJson()` keys, so absent-vs-null distinctions stay
// faithful without touching the DTO internals.

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/error/problem.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/core/work_items/work_item_filter.dart';
import 'package:intellipilot/demo/demo_store.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/domain/activity_repository.dart';
import 'package:intellipilot/features/admin/data/dtos/admin_dtos.dart';
import 'package:intellipilot/features/admin/data/dtos/app_token_dtos.dart';
import 'package:intellipilot/features/admin/domain/admin_repository.dart';
import 'package:intellipilot/features/auth/data/dtos/auth_dtos.dart';
import 'package:intellipilot/features/auth/domain/auth_repository.dart';
import 'package:intellipilot/features/backlog/data/dtos/backlog_dtos.dart';
import 'package:intellipilot/features/backlog/domain/backlog_repository.dart';
import 'package:intellipilot/features/board/data/dtos/board_dtos.dart';
import 'package:intellipilot/features/board/domain/board_repository.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';
import 'package:intellipilot/features/links/data/dtos/link_dtos.dart';
import 'package:intellipilot/features/links/domain/links_repository.dart';
import 'package:intellipilot/features/mfa/data/passkey_service.dart';
import 'package:intellipilot/features/mfa/domain/mfa_repository.dart';
import 'package:intellipilot/features/milestones/data/dtos/milestone_dtos.dart';
import 'package:intellipilot/features/milestones/domain/milestones_repository.dart';
import 'package:intellipilot/features/profile/data/dtos/profile_dtos.dart';
import 'package:intellipilot/features/profile/domain/profile_repository.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';
import 'package:intellipilot/features/wiki/data/dtos/wiki_dtos.dart';
import 'package:intellipilot/features/wiki/domain/wiki_repository.dart';

/// Demo data uses a tiny synthetic latency to keep loading spinners
/// honest. Bumping this exercises the staleness banners.
const _kLatency = Duration(milliseconds: 80);

Future<void> _tick() => Future<void>.delayed(_kLatency);

// ---------------------------------------------------------------------------
// Auth + profile
// ---------------------------------------------------------------------------

class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository(DemoStore _);

  TokenResponse _tokens() => const TokenResponse(
    accessToken: 'demo-access-token',
    tokenType: 'Bearer',
    expiresIn: 60 * 60,
    refreshToken: 'demo-refresh-token',
  );

  @override
  Future<Result<AuthConfig, AppFailure>> authConfig() async {
    await _tick();
    return const Ok(
      AuthConfig(openRegistration: true, passwordResetEnabled: true),
    );
  }

  @override
  Future<Result<LoginResult, AppFailure>> login({
    required String email,
    required String password,
  }) async {
    await _tick();
    return Ok(LoginTokens(_tokens()));
  }

  @override
  Future<Result<Unit, AppFailure>> register({
    required String email,
    required String username,
    required String password,
    required String fullName,
    String? invitationToken,
  }) async {
    await _tick();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<TokenResponse, AppFailure>> refresh() async {
    await _tick();
    return Ok(_tokens());
  }

  @override
  Future<Result<Unit, AppFailure>> logout() async {
    await _tick();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<PasswordResetRequestResponse, AppFailure>> requestPasswordReset(
    String email,
  ) async {
    await _tick();
    return const Ok(
      PasswordResetRequestResponse(
        status: 'ok',
        resetToken: 'demo-reset-token',
      ),
    );
  }

  @override
  Future<Result<Unit, AppFailure>> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    await _tick();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<TokenResponse, AppFailure>> verifyMfa({
    required String mfaToken,
    required String method,
    required String code,
  }) async {
    await _tick();
    return Ok(_tokens());
  }
}

class DemoProfileRepository implements ProfileRepository {
  DemoProfileRepository(this._s);
  final DemoStore _s;

  @override
  Future<Result<UserProfile, AppFailure>> getProfile() async {
    await _tick();
    return Ok(_s.currentUser);
  }

  @override
  Future<Result<UserProfile, AppFailure>> updateProfile(
    ProfileUpdateRequest patch,
  ) async {
    await _tick();
    _s.currentUser = _s.currentUser.copyWith(
      fullName: patch.fullName,
      lang: patch.lang,
      timezone: patch.timezone,
    );
    return Ok(_s.currentUser);
  }

  @override
  Future<Result<UserProfile, AppFailure>> uploadAvatar({
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) async {
    await _tick();
    return Ok(_s.currentUser);
  }

  @override
  Future<Result<UserProfile, AppFailure>> setEmojiAvatar(String emoji) async {
    await _tick();
    return Ok(_s.currentUser);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteAvatar() async {
    await _tick();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<AccountErasureResponse, AppFailure>> deleteAccount() async {
    await _tick();
    return Ok(
      AccountErasureResponse(
        status: 'scheduled_for_erasure',
        graceUntil: DateTime.now().add(const Duration(days: 30)),
      ),
    );
  }

  @override
  Future<Result<Unit, AppFailure>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _tick();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<Map<String, dynamic>, AppFailure>> exportData() async {
    await _tick();
    return Ok({
      'profile': {
        'id': _s.currentUser.id,
        'email': _s.currentUser.email,
        'username': _s.currentUser.username,
        'full_name': _s.currentUser.fullName,
      },
      'projects': [
        for (final p in _s.projects)
          {'id': p.id, 'slug': p.slug, 'name': p.name},
      ],
    });
  }
}

class DemoMfaRepository implements MfaRepository {
  DemoMfaRepository(DemoStore _);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'DemoMfaRepository.${invocation.memberName} '
    '(MFA flows are no-op in demo mode)',
  );
}

class DemoPasskeyService implements PasskeyService {
  const DemoPasskeyService();

  @override
  bool get isSupported => false;

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> _) async =>
      throw UnsupportedError('Passkeys are not supported in demo mode.');

  @override
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> _) async =>
      throw UnsupportedError('Passkeys are not supported in demo mode.');
}

// ---------------------------------------------------------------------------
// Projects + members + roles + invitations
// ---------------------------------------------------------------------------

class DemoProjectsRepository implements ProjectsRepository {
  DemoProjectsRepository(this._s);
  final DemoStore _s;

  @override
  Future<Result<List<Project>, AppFailure>> listProjects() async {
    await _tick();
    return Ok(List.unmodifiable(_s.projects));
  }

  @override
  Future<Result<Project, AppFailure>> getProject(String id) async {
    await _tick();
    final p = _s.projects.where((p) => p.id == id).firstOrNull;
    if (p == null) return const Err(NotFoundFailure());
    return Ok(p);
  }

  @override
  Future<Result<Project, AppFailure>> createProject(
    CreateProjectRequest body,
  ) async {
    await _tick();
    final id = _s.nextId('prj');
    final project = Project(
      id: id,
      slug: body.slug ?? body.name.toLowerCase().replaceAll(' ', '-'),
      name: body.name,
      description: body.description,
      ownerId: _s.currentUser.id,
      visibility: body.visibility ?? ProjectVisibility.private,
      kanbanEnabled: true,
      backlogEnabled: true,
      wikiEnabled: true,
      epicsEnabled: true,
      createdAt: DateTime.now().toUtc(),
    );
    _s.projects.add(project);
    _s.permissionsByProject[id] = Permission.values.toSet();
    _s.taxonomyByProject[id] = const [];
    _s.labelsByProject[id] = const [];
    _s.componentsByProject[id] = const [];
    // The creator must show up as an admin member, otherwise
    // ProjectDetailCubit.load resolves their permissions via the empty
    // member→role chain and returns an empty set — which then hides every
    // FAB and empty-state CTA on the project's sub-pages.
    final adminRole = Role(
      id: '$id-role-admin',
      projectId: id,
      slug: 'admin',
      name: 'Administrator',
      order: 0,
      isAdmin: true,
      permissions: Permission.values.toSet(),
    );
    _s.rolesByProject[id] = [adminRole];
    _s.membersByProject[id] = [
      Membership(
        id: '$id-mbr-creator',
        projectId: id,
        userId: _s.currentUser.id,
        roleId: adminRole.id,
        roleSlug: adminRole.slug,
        createdAt: DateTime.now().toUtc(),
      ),
    ];
    _s.invitationsByProject[id] = const [];
    return Ok(project);
  }

  @override
  Future<Result<Project, AppFailure>> updateProject(
    String id,
    UpdateProjectRequest body,
  ) async {
    await _tick();
    final patch = body.toJson();
    final i = _s.projects.indexWhere((p) => p.id == id);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = _s.projects[i];
    final updated = Project(
      id: cur.id,
      slug: cur.slug,
      name: (patch['name'] as String?) ?? cur.name,
      description: (patch['description'] as String?) ?? cur.description,
      ownerId: cur.ownerId,
      visibility: patch.containsKey('visibility')
          ? ProjectVisibility.fromWire(patch['visibility'] as String)
          : cur.visibility,
      issuePrefix: (patch['issue_prefix'] as String?) ?? cur.issuePrefix,
      color: (patch['color'] as String?) ?? cur.color,
      iconImageKind: cur.iconImageKind,
      iconImageUpdatedAt: cur.iconImageUpdatedAt,
      kanbanEnabled: (patch['kanban_enabled'] as bool?) ?? cur.kanbanEnabled,
      backlogEnabled: (patch['backlog_enabled'] as bool?) ?? cur.backlogEnabled,
      wikiEnabled: (patch['wiki_enabled'] as bool?) ?? cur.wikiEnabled,
      epicsEnabled: (patch['epics_enabled'] as bool?) ?? cur.epicsEnabled,
      epicBoard: cur.epicBoard,
      createdAt: cur.createdAt,
    );
    _s.projects[i] = updated;
    return Ok(updated);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteProject(String id) async {
    await _tick();
    _s.projects.removeWhere((p) => p.id == id);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<int, AppFailure>> purgeIssues(String projectId) async {
    await _tick();
    final n = _s.issues.where((i) => i.projectId == projectId).length;
    _s.issues.removeWhere((i) => i.projectId == projectId);
    return Ok(n);
  }

  @override
  Future<Result<int, AppFailure>> purgeEpics(String projectId) async {
    await _tick();
    final n = _s.epics.where((e) => e.projectId == projectId).length;
    _s.epics.removeWhere((e) => e.projectId == projectId);
    return Ok(n);
  }

  @override
  Future<Result<Project, AppFailure>> uploadProjectIcon(
    String projectId, {
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) async => _setIconKind(projectId, 'image');

  @override
  Future<Result<Project, AppFailure>> deleteProjectIcon(
    String projectId,
  ) async => _setIconKind(projectId, 'none');

  Future<Result<Project, AppFailure>> _setIconKind(
    String projectId,
    String kind,
  ) async {
    await _tick();
    final i = _s.projects.indexWhere((p) => p.id == projectId);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = _s.projects[i];
    final updated = Project(
      id: cur.id,
      slug: cur.slug,
      name: cur.name,
      description: cur.description,
      ownerId: cur.ownerId,
      visibility: cur.visibility,
      issuePrefix: cur.issuePrefix,
      color: cur.color,
      iconImageKind: kind,
      iconImageUpdatedAt: DateTime(2024),
      kanbanEnabled: cur.kanbanEnabled,
      backlogEnabled: cur.backlogEnabled,
      wikiEnabled: cur.wikiEnabled,
      epicsEnabled: cur.epicsEnabled,
      epicBoard: cur.epicBoard,
      createdAt: cur.createdAt,
    );
    _s.projects[i] = updated;
    return Ok(updated);
  }

  @override
  Future<Result<List<Role>, AppFailure>> listRoles(String projectId) async {
    await _tick();
    return Ok(List.unmodifiable(_s.rolesByProject[projectId] ?? const []));
  }

  @override
  Future<Result<Role, AppFailure>> createRole(
    String projectId,
    CreateRoleRequest body,
  ) async {
    await _tick();
    final id = _s.nextId('role');
    final json = body.toJson();
    final perms = (json['permissions'] as List<dynamic>? ?? const [])
        .map((w) => Permission.fromWire(w as String))
        .whereType<Permission>()
        .toSet();
    final role = Role(
      id: id,
      projectId: projectId,
      slug: (json['slug'] as String?) ?? body.name.toLowerCase(),
      name: body.name,
      order: (json['order'] as num?)?.toInt() ?? 100,
      isAdmin: (json['is_admin'] as bool?) ?? false,
      permissions: perms,
    );
    _s.rolesByProject.putIfAbsent(projectId, () => []);
    _s.rolesByProject[projectId] = [..._s.rolesByProject[projectId]!, role];
    return Ok(role);
  }

  @override
  Future<Result<Role, AppFailure>> updateRole(
    String projectId,
    String roleId,
    UpdateRoleRequest body,
  ) async {
    await _tick();
    final roles = _s.rolesByProject[projectId] ?? const <Role>[];
    final i = roles.indexWhere((r) => r.id == roleId);
    if (i < 0) return const Err(NotFoundFailure());
    final json = body.toJson();
    final cur = roles[i];
    final perms = json.containsKey('permissions')
        ? ((json['permissions'] as List<dynamic>)
              .map((w) => Permission.fromWire(w as String))
              .whereType<Permission>()
              .toSet())
        : cur.permissions;
    final updated = Role(
      id: cur.id,
      projectId: cur.projectId,
      slug: cur.slug,
      name: (json['name'] as String?) ?? cur.name,
      order: (json['order'] as num?)?.toInt() ?? cur.order,
      isAdmin: (json['is_admin'] as bool?) ?? cur.isAdmin,
      permissions: perms,
    );
    final next = [...roles];
    next[i] = updated;
    _s.rolesByProject[projectId] = next;
    return Ok(updated);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteRole(
    String projectId,
    String roleId,
  ) async {
    await _tick();
    final roles = _s.rolesByProject[projectId] ?? const <Role>[];
    _s.rolesByProject[projectId] = roles.where((r) => r.id != roleId).toList();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<List<Membership>, AppFailure>> listMembers(
    String projectId,
  ) async {
    await _tick();
    return Ok(
      List.unmodifiable(_s.membersByProject[projectId] ?? const <Membership>[]),
    );
  }

  @override
  Future<Result<Unit, AppFailure>> changeMemberRole(
    String projectId,
    String userId,
    String roleSlug,
  ) async {
    await _tick();
    final members = _s.membersByProject[projectId] ?? const <Membership>[];
    final i = members.indexWhere((m) => m.userId == userId);
    if (i < 0) return const Err(NotFoundFailure());
    final role = (_s.rolesByProject[projectId] ?? const <Role>[])
        .where((r) => r.slug == roleSlug)
        .firstOrNull;
    if (role == null) return const Err(NotFoundFailure());
    final cur = members[i];
    final updated = Membership(
      id: cur.id,
      projectId: cur.projectId,
      userId: cur.userId,
      roleId: role.id,
      roleSlug: role.slug,
      createdAt: cur.createdAt,
    );
    final next = [...members];
    next[i] = updated;
    _s.membersByProject[projectId] = next;
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<Unit, AppFailure>> removeMember(
    String projectId,
    String userId,
  ) async {
    await _tick();
    final members = _s.membersByProject[projectId] ?? const <Membership>[];
    _s.membersByProject[projectId] = members
        .where((m) => m.userId != userId)
        .toList();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<Unit, AppFailure>> addMember(
    String projectId, {
    required String roleSlug,
    String? userId,
    String? identifier,
  }) async {
    await _tick();
    final ident = identifier?.trim();
    final user = userId != null
        ? _s.users.where((u) => u.id == userId).firstOrNull
        : _s.users
              .where(
                (u) => u.email == ident?.toLowerCase() || u.username == ident,
              )
              .firstOrNull;
    if (user == null) return const Err(NotFoundFailure());
    final roles = _s.rolesByProject[projectId] ?? const <Role>[];
    final role = roles.where((r) => r.slug == roleSlug).firstOrNull;
    if (role == null) return const Err(UnknownFailure());
    final members = _s.membersByProject[projectId] ?? const <Membership>[];
    if (members.any((m) => m.userId == user.id)) {
      return const Err(ConflictFailure());
    }
    _s.membersByProject[projectId] = [
      ...members,
      Membership(
        id: _s.nextId('mbr'),
        projectId: projectId,
        userId: user.id,
        roleId: role.id,
        roleSlug: role.slug,
        createdAt: DateTime.now().toUtc(),
      ),
    ];
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<List<Invitation>, AppFailure>> listInvitations(
    String projectId,
  ) async {
    await _tick();
    return Ok(
      List.unmodifiable(
        _s.invitationsByProject[projectId] ?? const <Invitation>[],
      ),
    );
  }

  @override
  Future<Result<InviteResponse, AppFailure>> invite(
    String projectId,
    InviteRequest body,
  ) async {
    await _tick();
    final id = _s.nextId('inv');
    final json = body.toJson();
    final inv = Invitation(
      id: id,
      projectId: projectId,
      email: json['email'] as String,
      roleId: (json['role_id'] as String?) ?? 'role-reader',
      createdAt: DateTime.now().toUtc(),
    );
    _s.invitationsByProject.putIfAbsent(projectId, () => []);
    _s.invitationsByProject[projectId] = [
      ..._s.invitationsByProject[projectId]!,
      inv,
    ];
    return Ok(InviteResponse(invitationId: id, inviteToken: 'demo-token-$id'));
  }

  @override
  Future<Result<String, AppFailure>> acceptInvitation(String token) async {
    await _tick();
    // Pretend the invite points at the seeded demo project.
    return Ok(_s.projects.first.id);
  }
}

// ---------------------------------------------------------------------------
// Catalog
// ---------------------------------------------------------------------------

class DemoCatalogRepository implements CatalogRepository {
  DemoCatalogRepository(this._s);
  final DemoStore _s;

  @override
  Future<Result<List<TaxonomyItem>, AppFailure>> listTaxonomy(
    String projectId,
    TaxonomyKind kind,
  ) async {
    await _tick();
    final items =
        (_s.taxonomyByProject[projectId] ?? const <TaxonomyItem>[])
            .where((i) => i.kind == kind)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return Ok(items);
  }

  @override
  Future<Result<TaxonomyItem, AppFailure>> createTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    CreateTaxonomyItemRequest body,
  ) async {
    await _tick();
    final id = _s.nextId('tx');
    final orderMax = (_s.taxonomyByProject[projectId] ?? const <TaxonomyItem>[])
        .where((i) => i.kind == kind)
        .fold<double>(0, (m, i) => i.order > m ? i.order : m);
    final item = TaxonomyItem(
      id: id,
      projectId: projectId,
      kind: kind,
      name: body.name,
      slug: body.slug,
      color: body.color,
      order: orderMax + 1,
      isClosed: body.isClosed,
      value: body.value,
      createdAt: DateTime.now().toUtc(),
    );
    _s.taxonomyByProject.putIfAbsent(projectId, () => []);
    _s.taxonomyByProject[projectId] = [
      ..._s.taxonomyByProject[projectId]!,
      item,
    ];
    return Ok(item);
  }

  @override
  Future<Result<TaxonomyItem, AppFailure>> updateTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    String itemId,
    UpdateTaxonomyItemRequest body,
  ) async {
    await _tick();
    final patch = body.toJson();
    final list = _s.taxonomyByProject[projectId] ?? const <TaxonomyItem>[];
    final i = list.indexWhere((x) => x.id == itemId);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = list[i];
    final updated = TaxonomyItem(
      id: cur.id,
      projectId: cur.projectId,
      kind: cur.kind,
      name: (patch['name'] as String?) ?? cur.name,
      slug: cur.slug,
      color: (patch['color'] as String?) ?? cur.color,
      order: cur.order,
      isClosed: patch.containsKey('is_closed')
          ? patch['is_closed'] as bool?
          : cur.isClosed,
      value: patch.containsKey('value')
          ? (patch['value'] as num?)?.toDouble()
          : cur.value,
      createdAt: cur.createdAt,
    );
    final next = [...list];
    next[i] = updated;
    _s.taxonomyByProject[projectId] = next;
    return Ok(updated);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    String itemId,
  ) async {
    await _tick();
    final list = _s.taxonomyByProject[projectId] ?? const <TaxonomyItem>[];
    _s.taxonomyByProject[projectId] = list
        .where((x) => x.id != itemId)
        .toList();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<Unit, AppFailure>> moveTaxonomyItem(
    String projectId,
    TaxonomyKind kind,
    String itemId,
    MoveTaxonomyItemRequest body,
  ) async {
    await _tick();
    // Recompute order by placing the moved item between before/after siblings.
    final all = [..._s.taxonomyByProject[projectId] ?? const <TaxonomyItem>[]];
    final moved = all.firstWhere((x) => x.id == itemId, orElse: () => all[0]);
    final sameKind = all.where((x) => x.kind == kind).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    sameKind.removeWhere((x) => x.id == itemId);
    final beforeIdx = body.beforeId == null
        ? -1
        : sameKind.indexWhere((x) => x.id == body.beforeId);
    final afterIdx = body.afterId == null
        ? sameKind.length
        : sameKind.indexWhere((x) => x.id == body.afterId);
    final insertAt = body.beforeId != null ? beforeIdx + 1 : afterIdx;
    sameKind.insert(insertAt.clamp(0, sameKind.length), moved);
    for (var idx = 0; idx < sameKind.length; idx++) {
      final reordered = sameKind[idx];
      final j = all.indexWhere((x) => x.id == reordered.id);
      all[j] = TaxonomyItem(
        id: reordered.id,
        projectId: reordered.projectId,
        kind: reordered.kind,
        name: reordered.name,
        slug: reordered.slug,
        color: reordered.color,
        order: (idx + 1).toDouble(),
        isClosed: reordered.isClosed,
        value: reordered.value,
        createdAt: reordered.createdAt,
      );
    }
    _s.taxonomyByProject[projectId] = all;
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<List<Label>, AppFailure>> listLabels(String projectId) async {
    await _tick();
    return Ok(List.unmodifiable(_s.labelsByProject[projectId] ?? const []));
  }

  @override
  Future<Result<Label, AppFailure>> createLabel(
    String projectId,
    CreateLabelRequest body,
  ) async {
    await _tick();
    final label = Label(
      id: _s.nextId('lbl'),
      projectId: projectId,
      name: body.name,
      color: body.color,
      createdAt: DateTime.now().toUtc(),
    );
    _s.labelsByProject.putIfAbsent(projectId, () => []);
    _s.labelsByProject[projectId] = [..._s.labelsByProject[projectId]!, label];
    return Ok(label);
  }

  @override
  Future<Result<Label, AppFailure>> updateLabel(
    String projectId,
    String labelId,
    UpdateLabelRequest body,
  ) async {
    await _tick();
    final list = _s.labelsByProject[projectId] ?? const <Label>[];
    final i = list.indexWhere((l) => l.id == labelId);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = list[i];
    final next = [...list];
    next[i] = Label(
      id: cur.id,
      projectId: cur.projectId,
      name: body.name ?? cur.name,
      color: body.color ?? cur.color,
      createdAt: cur.createdAt,
    );
    _s.labelsByProject[projectId] = next;
    return Ok(next[i]);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteLabel(
    String projectId,
    String labelId,
  ) async {
    await _tick();
    final list = _s.labelsByProject[projectId] ?? const <Label>[];
    _s.labelsByProject[projectId] = list.where((l) => l.id != labelId).toList();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<List<Component>, AppFailure>> listComponents(
    String projectId,
  ) async {
    await _tick();
    return Ok(
      List.unmodifiable(
        _s.componentsByProject[projectId] ?? const <Component>[],
      ),
    );
  }

  @override
  Future<Result<Component, AppFailure>> createComponent(
    String projectId,
    CreateComponentRequest body,
  ) async {
    await _tick();
    final c = Component(
      id: _s.nextId('cmp'),
      projectId: projectId,
      name: body.name,
      color: body.color,
      createdAt: DateTime.now().toUtc(),
    );
    _s.componentsByProject.putIfAbsent(projectId, () => []);
    _s.componentsByProject[projectId] = [
      ..._s.componentsByProject[projectId]!,
      c,
    ];
    return Ok(c);
  }

  @override
  Future<Result<Component, AppFailure>> updateComponent(
    String projectId,
    String componentId,
    UpdateComponentRequest body,
  ) async {
    await _tick();
    final patch = body.toJson();
    final list = _s.componentsByProject[projectId] ?? const <Component>[];
    final i = list.indexWhere((c) => c.id == componentId);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = list[i];
    final next = [...list];
    next[i] = Component(
      id: cur.id,
      projectId: cur.projectId,
      name: (patch['name'] as String?) ?? cur.name,
      color: (patch['color'] as String?) ?? cur.color,
      createdAt: cur.createdAt,
    );
    _s.componentsByProject[projectId] = next;
    return Ok(next[i]);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteComponent(
    String projectId,
    String componentId,
  ) async {
    await _tick();
    final list = _s.componentsByProject[projectId] ?? const <Component>[];
    _s.componentsByProject[projectId] = list
        .where((c) => c.id != componentId)
        .toList();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  // ---- git: SSH keys, repositories, component links (demo stubs) ----

  @override
  Future<Result<List<SshKey>, AppFailure>> listSshKeys(
    String projectId,
  ) async {
    await _tick();
    return const Ok(<SshKey>[]);
  }

  @override
  Future<Result<SshKey, AppFailure>> createSshKey(
    String projectId,
    CreateSshKeyRequest body,
  ) async {
    await _tick();
    return Ok(
      SshKey(
        id: _s.nextId('key'),
        projectId: projectId,
        name: body.name,
        readOnly: body.readOnly,
        keyType: 'ed25519',
        publicKey: 'ssh-ed25519 AAAADEMOKEY ${body.name}',
        fingerprint: 'SHA256:demo',
        usedByRepoCount: 0,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<Result<SshKey, AppFailure>> updateSshKey(
    String projectId,
    String keyId,
    UpdateSshKeyRequest body,
  ) async {
    await _tick();
    return const Err(NotFoundFailure());
  }

  @override
  Future<Result<Unit, AppFailure>> deleteSshKey(
    String projectId,
    String keyId,
  ) async {
    await _tick();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<List<Repository>, AppFailure>> listRepositories(
    String projectId,
  ) async {
    await _tick();
    return const Ok(<Repository>[]);
  }

  @override
  Future<Result<Repository, AppFailure>> createRepository(
    String projectId,
    CreateRepositoryRequest body,
  ) async {
    await _tick();
    return Ok(
      Repository(
        id: _s.nextId('repo'),
        projectId: projectId,
        name: body.name,
        sshUrl: body.sshUrl,
        sshKeyId: body.sshKeyId,
        defaultBranch: body.defaultBranch,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<Result<Repository, AppFailure>> updateRepository(
    String projectId,
    String repositoryId,
    UpdateRepositoryRequest body,
  ) async {
    await _tick();
    return const Err(NotFoundFailure());
  }

  @override
  Future<Result<Unit, AppFailure>> deleteRepository(
    String projectId,
    String repositoryId,
  ) async {
    await _tick();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<RemoteBranches, AppFailure>> previewBranches(
    String projectId,
    String sshUrl,
    String sshKeyId,
  ) async {
    await _tick();
    return const Ok(
      RemoteBranches(branches: ['main', 'develop'], defaultBranch: 'main'),
    );
  }

  @override
  Future<Result<RemoteBranches, AppFailure>> repositoryBranches(
    String projectId,
    String repositoryId,
  ) async {
    await _tick();
    return const Ok(
      RemoteBranches(branches: ['main', 'develop'], defaultBranch: 'main'),
    );
  }

  @override
  Future<Result<List<ComponentRepositoryLink>, AppFailure>>
  listComponentRepositories(String projectId, String componentId) async {
    await _tick();
    return const Ok(<ComponentRepositoryLink>[]);
  }

  @override
  Future<Result<ComponentRepositoryLink, AppFailure>> linkComponentRepository(
    String projectId,
    String componentId,
    String repositoryId,
    String branch,
  ) async {
    await _tick();
    return Ok(
      ComponentRepositoryLink(
        componentId: componentId,
        repositoryId: repositoryId,
        repositoryName: 'demo',
        sshUrl: 'git@demo:repo.git',
        branch: branch,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<Result<ComponentRepositoryLink, AppFailure>>
  updateComponentRepositoryBranch(
    String projectId,
    String componentId,
    String repositoryId,
    String branch,
  ) async {
    await _tick();
    return const Err(NotFoundFailure());
  }

  @override
  Future<Result<Unit, AppFailure>> unlinkComponentRepository(
    String projectId,
    String componentId,
    String repositoryId,
  ) async {
    await _tick();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  // ---- customers ----

  @override
  Future<Result<List<Customer>, AppFailure>> listCustomers(
    String projectId,
  ) async {
    await _tick();
    return Ok(_s.customersByProject[projectId] ?? const []);
  }

  @override
  Future<Result<Customer, AppFailure>> createCustomer(
    String projectId,
    CreateCustomerRequest body,
  ) async {
    await _tick();
    final created = Customer(
      id: _s.nextId('cust'),
      projectId: projectId,
      name: body.name,
      companyName: body.companyName,
      contactEmail: body.contactEmail,
      phone: body.phone,
      notes: body.notes,
      createdAt: DateTime.now().toUtc(),
    );
    (_s.customersByProject[projectId] ??= []).add(created);
    return Ok(created);
  }

  @override
  Future<Result<Customer, AppFailure>> updateCustomer(
    String projectId,
    String customerId,
    UpdateCustomerRequest body,
  ) async {
    await _tick();
    final list = _s.customersByProject[projectId] ?? const [];
    final i = list.indexWhere((c) => c.id == customerId);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = list[i];
    final next = Customer(
      id: cur.id,
      projectId: cur.projectId,
      name: body.name ?? cur.name,
      companyName: body.companyName ?? cur.companyName,
      contactEmail: body.contactEmail ?? cur.contactEmail,
      phone: body.phone ?? cur.phone,
      notes: body.notes ?? cur.notes,
      createdAt: cur.createdAt,
    );
    _s.customersByProject[projectId]![i] = next;
    return Ok(next);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteCustomer(
    String projectId,
    String customerId,
  ) async {
    await _tick();
    _s.customersByProject[projectId]?.removeWhere((c) => c.id == customerId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  // ---- releases + versions ----

  @override
  Future<Result<List<Release>, AppFailure>> listReleases(
    String projectId,
  ) async {
    await _tick();
    return Ok(_s.releasesByProject[projectId] ?? const []);
  }

  @override
  Future<Result<Release, AppFailure>> createRelease(
    String projectId,
    CreateReleaseRequest body,
  ) async {
    await _tick();
    final created = Release(
      id: _s.nextId('rel'),
      projectId: projectId,
      name: body.name,
      description: body.description,
      createdAt: DateTime.now().toUtc(),
    );
    (_s.releasesByProject[projectId] ??= []).add(created);
    return Ok(created);
  }

  @override
  Future<Result<Release, AppFailure>> updateRelease(
    String projectId,
    String releaseId,
    UpdateReleaseRequest body,
  ) async {
    await _tick();
    final list = _s.releasesByProject[projectId] ?? const [];
    final i = list.indexWhere((r) => r.id == releaseId);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = list[i];
    final next = Release(
      id: cur.id,
      projectId: cur.projectId,
      name: body.name ?? cur.name,
      description: body.description ?? cur.description,
      createdAt: cur.createdAt,
    );
    _s.releasesByProject[projectId]![i] = next;
    return Ok(next);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteRelease(
    String projectId,
    String releaseId,
  ) async {
    await _tick();
    _s.releasesByProject[projectId]?.removeWhere((r) => r.id == releaseId);
    _s.versionsByRelease.remove(releaseId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<List<ReleaseVersion>, AppFailure>> listReleaseVersions(
    String projectId,
    String releaseId,
  ) async {
    await _tick();
    return Ok(_s.versionsByRelease[releaseId] ?? const []);
  }

  @override
  Future<Result<ReleaseVersion, AppFailure>> createReleaseVersion(
    String projectId,
    String releaseId,
    CreateReleaseVersionRequest body,
  ) async {
    await _tick();
    final created = ReleaseVersion(
      id: _s.nextId('rv'),
      releaseId: releaseId,
      version: body.version,
      status: body.status,
      notes: body.notes ?? '',
      targetDate: body.targetDate,
      releasedAt: body.releasedAt,
      repositoryId: body.repositoryId,
      gitTag: body.gitTag,
      createdAt: DateTime.now().toUtc(),
    );
    (_s.versionsByRelease[releaseId] ??= []).add(created);
    return Ok(created);
  }

  @override
  Future<Result<ReleaseVersion, AppFailure>> updateReleaseVersion(
    String projectId,
    String releaseId,
    String versionId,
    UpdateReleaseVersionRequest body,
  ) async {
    await _tick();
    final list = _s.versionsByRelease[releaseId] ?? const [];
    final i = list.indexWhere((v) => v.id == versionId);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = list[i];
    final patch = body.toJson();
    final next = ReleaseVersion(
      id: cur.id,
      releaseId: cur.releaseId,
      version: body.version ?? cur.version,
      status: body.status ?? cur.status,
      notes: body.notes ?? cur.notes,
      targetDate: patch.containsKey('target_date')
          ? patch['target_date'] as String?
          : cur.targetDate,
      releasedAt: patch.containsKey('released_at')
          ? patch['released_at'] as String?
          : cur.releasedAt,
      repositoryId: patch.containsKey('repository_id')
          ? patch['repository_id'] as String?
          : cur.repositoryId,
      gitTag: patch.containsKey('git_tag')
          ? patch['git_tag'] as String?
          : cur.gitTag,
      createdAt: cur.createdAt,
    );
    _s.versionsByRelease[releaseId]![i] = next;
    return Ok(next);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteReleaseVersion(
    String projectId,
    String releaseId,
    String versionId,
  ) async {
    await _tick();
    _s.versionsByRelease[releaseId]?.removeWhere((v) => v.id == versionId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  // ---- component <-> release links ----

  @override
  Future<Result<List<ComponentReleaseLink>, AppFailure>> listComponentReleases(
    String projectId,
    String componentId,
  ) async {
    await _tick();
    return Ok(_s.componentReleases[componentId] ?? const []);
  }

  @override
  Future<Result<ComponentReleaseLink, AppFailure>> linkComponentRelease(
    String projectId,
    String componentId,
    String releaseId,
  ) async {
    await _tick();
    final release = (_s.releasesByProject[projectId] ?? const [])
        .where((r) => r.id == releaseId)
        .firstOrNull;
    final link = ComponentReleaseLink(
      componentId: componentId,
      releaseId: releaseId,
      releaseName: release?.name ?? releaseId,
      createdAt: DateTime.now().toUtc(),
    );
    (_s.componentReleases[componentId] ??= []).add(link);
    return Ok(link);
  }

  @override
  Future<Result<Unit, AppFailure>> unlinkComponentRelease(
    String projectId,
    String componentId,
    String releaseId,
  ) async {
    await _tick();
    _s.componentReleases[componentId]?.removeWhere(
      (l) => l.releaseId == releaseId,
    );
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<List<ReleaseVersionRef>, AppFailure>> versionsForComponents(
    String projectId,
    List<String> componentIds,
  ) async {
    await _tick();
    final releaseIds = <String>{};
    for (final cid in componentIds) {
      for (final l
          in _s.componentReleases[cid] ?? const <ComponentReleaseLink>[]) {
        releaseIds.add(l.releaseId);
      }
    }
    final releasesById = {
      for (final r in _s.releasesByProject[projectId] ?? const <Release>[])
        r.id: r,
    };
    final out = <ReleaseVersionRef>[];
    for (final rid in releaseIds) {
      for (final v in _s.versionsByRelease[rid] ?? const <ReleaseVersion>[]) {
        out.add(
          ReleaseVersionRef(
            id: v.id,
            releaseId: rid,
            releaseName: releasesById[rid]?.name ?? rid,
            version: v.version,
            status: v.status,
          ),
        );
      }
    }
    return Ok(out);
  }

  // ---- issue relationships ----

  @override
  Future<Result<List<IssueLink>, AppFailure>> listIssueLinks(
    String projectId,
    String issueId,
  ) async {
    await _tick();
    return Ok(_s.issueLinks[issueId] ?? const []);
  }

  @override
  Future<Result<IssueLink, AppFailure>> createIssueLink(
    String projectId,
    String issueId,
    String targetIssueId,
    String linkType,
  ) async {
    await _tick();
    final target = _s.issues.where((i) => i.id == targetIssueId).firstOrNull;
    if (target == null) return const Err(NotFoundFailure());
    final link = IssueLink(
      id: _s.nextId('ilink'),
      otherIssueId: targetIssueId,
      otherRef: target.reference,
      otherSubject: target.subject,
      linkType: linkType,
      direction: 'outgoing',
      createdAt: DateTime.now().toUtc(),
    );
    (_s.issueLinks[issueId] ??= []).add(link);
    return Ok(link);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteIssueLink(
    String projectId,
    String issueId,
    String linkId,
  ) async {
    await _tick();
    _s.issueLinks[issueId]?.removeWhere((l) => l.id == linkId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  // ---- issue watchers ----

  @override
  Future<Result<List<String>, AppFailure>> listWatchers(
    String projectId,
    String issueId,
  ) async {
    await _tick();
    return Ok(_s.watchersByIssue[issueId] ?? const []);
  }

  @override
  Future<Result<Unit, AppFailure>> addWatcher(
    String projectId,
    String issueId, {
    String? userId,
  }) async {
    await _tick();
    final uid = userId ?? _s.currentUser.id;
    final list = _s.watchersByIssue[issueId] ??= [];
    if (!list.contains(uid)) list.add(uid);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<Unit, AppFailure>> removeWatcher(
    String projectId,
    String issueId,
    String userId,
  ) async {
    await _tick();
    _s.watchersByIssue[issueId]?.remove(userId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  // ---- kanban board views (per user) ----

  final Map<String, List<BoardView>> _boardViews = {};
  final Map<String, Map<String, dynamic>> _lastBoard = {};
  int _boardViewSeq = 0;

  @override
  Future<Result<List<BoardView>, AppFailure>> listBoardViews(
    String projectId,
  ) async {
    await _tick();
    return Ok(List.unmodifiable(_boardViews[projectId] ?? const []));
  }

  @override
  Future<Result<BoardView, AppFailure>> createBoardView(
    String projectId,
    String name,
    Map<String, dynamic> config,
  ) async {
    await _tick();
    final view = BoardView(
      id: 'bv-${_boardViewSeq++}',
      projectId: projectId,
      userId: 'demo-user',
      name: name,
      config: config,
    );
    (_boardViews[projectId] ??= []).add(view);
    return Ok(view);
  }

  @override
  Future<Result<BoardView, AppFailure>> updateBoardView(
    String projectId,
    String viewId,
    String name,
    Map<String, dynamic> config,
  ) async {
    await _tick();
    final list = _boardViews[projectId] ?? [];
    final i = list.indexWhere((v) => v.id == viewId);
    if (i < 0) return const Err(NotFoundFailure());
    final updated = BoardView(
      id: viewId,
      projectId: projectId,
      userId: 'demo-user',
      name: name,
      config: config,
    );
    list[i] = updated;
    return Ok(updated);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteBoardView(
    String projectId,
    String viewId,
  ) async {
    await _tick();
    _boardViews[projectId]?.removeWhere((v) => v.id == viewId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<Map<String, dynamic>?, AppFailure>> getLastUsedBoard(
    String projectId,
  ) async {
    await _tick();
    return Ok(_lastBoard[projectId]);
  }

  @override
  Future<Result<Unit, AppFailure>> setLastUsedBoard(
    String projectId,
    Map<String, dynamic> config,
  ) async {
    await _tick();
    _lastBoard[projectId] = config;
    return const Ok<Unit, AppFailure>(Unit.instance);
  }
}

// ---------------------------------------------------------------------------
// Backlog
// ---------------------------------------------------------------------------

class DemoBacklogRepository implements BacklogRepository {
  DemoBacklogRepository(this._s);
  final DemoStore _s;

  // Internal helpers for ETag round-tripping.
  Epic _bumpEpic(Epic e, {required Epic next}) {
    final v = e.version + 1;
    return Epic(
      id: next.id,
      projectId: next.projectId,
      reference: next.reference,
      subject: next.subject,
      description: next.description,
      statusId: next.statusId,
      color: next.color,
      ownerId: next.ownerId,
      assignedTo: next.assignedTo,
      order: next.order,
      version: v,
      createdAt: next.createdAt,
      modifiedAt: DateTime.now().toUtc(),
      etag: _s.etagOf(next.id, v),
    );
  }

  Issue _bumpIssue(Issue cur, {required Issue next}) {
    final v = cur.version + 1;
    return Issue(
      id: next.id,
      projectId: next.projectId,
      reference: next.reference,
      subject: next.subject,
      description: next.description,
      statusId: next.statusId,
      typeId: next.typeId,
      priorityId: next.priorityId,
      sizeId: next.sizeId,
      epicId: next.epicId,
      parentId: next.parentId,
      milestoneId: next.milestoneId,
      ownerId: next.ownerId,
      assignedTo: next.assignedTo,
      category: next.category,
      customerIds: next.customerIds,
      startDate: next.startDate,
      dueDate: next.dueDate,
      resolution: next.resolution,
      resolvedAt: next.resolvedAt,
      releaseVersionId: next.releaseVersionId,
      releaseText: next.releaseText,
      labels: next.labels,
      components: next.components,
      watchers: next.watchers,
      order: next.order,
      version: v,
      createdAt: next.createdAt,
      modifiedAt: DateTime.now().toUtc(),
      etag: _s.etagOf(next.id, v),
    );
  }

  // ---- epics ----

  @override
  Future<Result<List<Epic>, AppFailure>> listEpics(String projectId) async {
    await _tick();
    final list = _s.epics.where((e) => e.projectId == projectId).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return Ok(list);
  }

  @override
  Future<Result<Epic, AppFailure>> getEpic(String projectId, String id) async {
    await _tick();
    final e = _s.epics
        .where((e) => e.id == id && e.projectId == projectId)
        .firstOrNull;
    if (e == null) return const Err(NotFoundFailure());
    return Ok(e);
  }

  @override
  Future<Result<Epic, AppFailure>> createEpic(
    String projectId,
    CreateEpicRequest body,
  ) async {
    await _tick();
    final id = _s.nextId('ep');
    final maxRef = _s.epics
        .where((e) => e.projectId == projectId)
        .fold<int>(0, (m, e) => e.reference > m ? e.reference : m);
    final maxOrder = _s.epics
        .where((e) => e.projectId == projectId)
        .fold<double>(0, (m, e) => e.order > m ? e.order : m);
    final created = Epic(
      id: id,
      projectId: projectId,
      reference: maxRef + 1,
      subject: body.subject,
      description: body.description,
      statusId: body.statusId,
      color: body.color,
      assignedTo: body.assignedTo,
      order: maxOrder + 1,
      version: 1,
      createdAt: DateTime.now().toUtc(),
      modifiedAt: DateTime.now().toUtc(),
      etag: _s.etagOf(id, 1),
    );
    _s.epics.add(created);
    return Ok(created);
  }

  @override
  Future<Result<Epic, AppFailure>> updateEpic(
    String projectId,
    String id, {
    required UpdateEpicRequest body,
    required String etag,
  }) async {
    await _tick();
    final i = _s.epics.indexWhere(
      (e) => e.id == id && e.projectId == projectId,
    );
    if (i < 0) return const Err(NotFoundFailure());
    final cur = _s.epics[i];
    if (cur.etag != etag) return const Err(ConflictFailure());
    final patch = body.toJson();
    final next = Epic(
      id: cur.id,
      projectId: cur.projectId,
      reference: cur.reference,
      subject: (patch['subject'] as String?) ?? cur.subject,
      description: (patch['description'] as String?) ?? cur.description,
      statusId: patch.containsKey('status_id')
          ? patch['status_id'] as String?
          : cur.statusId,
      color: (patch['color'] as String?) ?? cur.color,
      ownerId: patch.containsKey('owner_id')
          ? patch['owner_id'] as String?
          : cur.ownerId,
      assignedTo: patch.containsKey('assigned_to')
          ? patch['assigned_to'] as String?
          : cur.assignedTo,
      order: cur.order,
      version: cur.version,
      createdAt: cur.createdAt,
      modifiedAt: cur.modifiedAt,
    );
    final bumped = _bumpEpic(cur, next: next);
    _s.epics[i] = bumped;
    return Ok(bumped);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteEpic(
    String projectId,
    String id, {
    required String etag,
  }) async {
    await _tick();
    _s.epics.removeWhere((e) => e.id == id && e.projectId == projectId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<Unit, AppFailure>> moveEpic(
    String projectId,
    String id,
    ReorderRequest body,
  ) async {
    await _tick();
    // Order is recomputed naively — good enough for the demo.
    final ep = _s.epics.where((e) => e.id == id).firstOrNull;
    if (ep == null) return const Err(NotFoundFailure());
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<Epic, AppFailure>> uploadEpicCover(
    String projectId,
    String id, {
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) async {
    await _tick();
    final ep = _s.epics.where((e) => e.id == id).firstOrNull;
    if (ep == null) return const Err(NotFoundFailure());
    return Ok(ep);
  }

  @override
  Future<Result<Epic, AppFailure>> deleteEpicCover(
    String projectId,
    String id,
  ) async {
    await _tick();
    final ep = _s.epics.where((e) => e.id == id).firstOrNull;
    if (ep == null) return const Err(NotFoundFailure());
    return Ok(ep);
  }

  // ---- issues ----

  @override
  Future<Result<List<Issue>, AppFailure>> listIssues(String projectId) async {
    await _tick();
    final list = _s.issues.where((i) => i.projectId == projectId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return Ok(list);
  }

  @override
  Future<Result<Issue, AppFailure>> getIssue(
    String projectId,
    String id,
  ) async {
    await _tick();
    final iss = _s.issues
        .where((i) => i.id == id && i.projectId == projectId)
        .firstOrNull;
    if (iss == null) return const Err(NotFoundFailure());
    return Ok(iss);
  }

  @override
  Future<Result<Issue, AppFailure>> getIssueByRef(
    String projectId,
    int ref,
  ) async {
    await _tick();
    final iss = _s.issues
        .where((i) => i.reference == ref && i.projectId == projectId)
        .firstOrNull;
    if (iss == null) return const Err(NotFoundFailure());
    return Ok(iss);
  }

  @override
  Future<Result<IssuePage, AppFailure>> listIssuesPaged(
    String projectId, {
    Map<String, dynamic> filter = const {},
    int? limit,
    int offset = 0,
  }) async {
    await _tick();
    final f = WorkItemFilter.fromJson(Map<String, dynamic>.from(filter));
    final items =
        _s.issues
            .where(
              (i) =>
                  i.projectId == projectId &&
                  f.matches(i, closedStatusIds: const {}),
            )
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final total = items.length;
    final start = offset.clamp(0, total);
    final end = limit == null ? total : (start + limit).clamp(0, total);
    return Ok(
      IssuePage(
        items: items.sublist(start, end),
        total: total,
        limit: limit,
        offset: offset,
      ),
    );
  }

  @override
  Future<Result<Issue, AppFailure>> createIssue(
    String projectId,
    CreateIssueRequest body,
  ) async {
    await _tick();
    final id = _s.nextId('iss');
    final maxRef = _s.issues
        .where((i) => i.projectId == projectId)
        .fold<int>(200, (m, i) => i.reference > m ? i.reference : m);
    final maxOrder = _s.issues
        .where((i) => i.projectId == projectId)
        .fold<double>(0, (m, i) => i.order > m ? i.order : m);
    final issue = Issue(
      id: id,
      projectId: projectId,
      reference: maxRef + 1,
      subject: body.subject,
      description: body.description,
      statusId: body.statusId,
      typeId: body.typeId,
      priorityId: body.priorityId,
      sizeId: body.sizeId,
      epicId: body.epicId,
      parentId: body.parentId,
      milestoneId: body.milestoneId,
      assignedTo: body.assignedTo,
      category: body.category,
      customerIds: body.customerIds,
      startDate: body.startDate,
      dueDate: body.dueDate,
      resolution: body.resolution,
      releaseVersionId: body.releaseVersionId,
      releaseText: body.releaseText,
      labels: body.labels,
      components: body.components,
      order: maxOrder + 1,
      version: 1,
      createdAt: DateTime.now().toUtc(),
      modifiedAt: DateTime.now().toUtc(),
      etag: _s.etagOf(id, 1),
    );
    _s.issues.add(issue);
    return Ok(issue);
  }

  @override
  Future<Result<Unit, AppFailure>> moveIssue(
    String projectId,
    String id,
    ReorderRequest body,
  ) async {
    await _tick();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<List<Issue>, AppFailure>> bulkCreateIssues(
    String projectId,
    BulkCreateIssuesRequest body,
  ) async {
    final out = <Issue>[];
    for (final item in body.items) {
      final r = await createIssue(projectId, item);
      final v = r.valueOrNull;
      if (v != null) out.add(v);
    }
    return Ok(out);
  }

  @override
  Future<Result<Issue, AppFailure>> updateIssue(
    String projectId,
    String id, {
    required UpdateIssueRequest body,
    required String etag,
  }) async {
    await _tick();
    final i = _s.issues.indexWhere(
      (i) => i.id == id && i.projectId == projectId,
    );
    if (i < 0) return const Err(NotFoundFailure());
    final cur = _s.issues[i];
    if (cur.etag != etag) return const Err(ConflictFailure());
    final patch = body.toJson();
    final next = Issue(
      id: cur.id,
      projectId: cur.projectId,
      reference: cur.reference,
      subject: (patch['subject'] as String?) ?? cur.subject,
      description: (patch['description'] as String?) ?? cur.description,
      statusId: patch.containsKey('status_id')
          ? patch['status_id'] as String?
          : cur.statusId,
      typeId: patch.containsKey('type_id')
          ? patch['type_id'] as String?
          : cur.typeId,
      priorityId: patch.containsKey('priority_id')
          ? patch['priority_id'] as String?
          : cur.priorityId,
      sizeId: patch.containsKey('size_id')
          ? patch['size_id'] as String?
          : cur.sizeId,
      epicId: patch.containsKey('epic_id')
          ? patch['epic_id'] as String?
          : cur.epicId,
      parentId: patch.containsKey('parent_id')
          ? patch['parent_id'] as String?
          : cur.parentId,
      milestoneId: patch.containsKey('milestone_id')
          ? patch['milestone_id'] as String?
          : cur.milestoneId,
      ownerId: patch.containsKey('owner_id')
          ? patch['owner_id'] as String?
          : cur.ownerId,
      assignedTo: patch.containsKey('assigned_to')
          ? patch['assigned_to'] as String?
          : cur.assignedTo,
      category: patch.containsKey('category')
          ? patch['category'] as String?
          : cur.category,
      customerIds: patch.containsKey('customer_ids')
          ? (patch['customer_ids'] as List<dynamic>)
                .map((e) => e as String)
                .toList()
          : cur.customerIds,
      startDate: patch.containsKey('start_date')
          ? patch['start_date'] as String?
          : cur.startDate,
      dueDate: patch.containsKey('due_date')
          ? patch['due_date'] as String?
          : cur.dueDate,
      resolution: patch.containsKey('resolution')
          ? patch['resolution'] as String?
          : cur.resolution,
      resolvedAt: cur.resolvedAt,
      releaseVersionId: patch.containsKey('release_version_id')
          ? patch['release_version_id'] as String?
          : cur.releaseVersionId,
      releaseText: patch.containsKey('release_text')
          ? patch['release_text'] as String?
          : cur.releaseText,
      watchers: cur.watchers,
      labels: patch.containsKey('labels')
          ? (patch['labels'] as List<dynamic>).cast<String>()
          : cur.labels,
      components: patch.containsKey('components')
          ? (patch['components'] as List<dynamic>).cast<String>()
          : cur.components,
      order: cur.order,
      version: cur.version,
      createdAt: cur.createdAt,
      modifiedAt: cur.modifiedAt,
    );
    final bumped = _bumpIssue(cur, next: next);
    _s.issues[i] = bumped;
    return Ok(bumped);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteIssue(
    String projectId,
    String id, {
    required String etag,
  }) async {
    await _tick();
    _s.issues.removeWhere((i) => i.id == id && i.projectId == projectId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  // ---- ref resolver ----

  @override
  Future<Result<ResolvedRef, AppFailure>> resolveRef(
    String projectId,
    int reference,
  ) async {
    await _tick();
    for (final e in _s.epics) {
      if (e.projectId == projectId && e.reference == reference) {
        return Ok(ResolvedRef(kind: 'epic', id: e.id, ref: reference));
      }
    }
    for (final i in _s.issues) {
      if (i.projectId == projectId && i.reference == reference) {
        return Ok(ResolvedRef(kind: 'issue', id: i.id, ref: reference));
      }
    }
    return const Err(NotFoundFailure());
  }
}

// ---------------------------------------------------------------------------
// Activity (comments + history + attachments)
// ---------------------------------------------------------------------------

class DemoActivityRepository implements ActivityRepository {
  DemoActivityRepository(this._s);
  final DemoStore _s;

  @override
  Future<Result<List<Comment>, AppFailure>> listComments(
    String projectId,
    EntityKind kind,
    String entityId,
  ) async {
    await _tick();
    final out = _s.comments
        .where((c) => c.targetType == kind.wire && c.targetId == entityId)
        .toList();
    return Ok(out);
  }

  @override
  Future<Result<Comment, AppFailure>> createComment(
    String projectId,
    EntityKind kind,
    String entityId,
    CreateCommentRequest body,
  ) async {
    await _tick();
    final c = Comment(
      id: _s.nextId('cm'),
      targetType: kind.wire,
      targetId: entityId,
      authorId: _s.currentUser.id,
      body: body.body,
      bodyHtml: body.body,
      createdAt: DateTime.now().toUtc(),
    );
    _s.comments.add(c);
    return Ok(c);
  }

  @override
  Future<Result<Comment, AppFailure>> updateComment(
    String projectId,
    EntityKind kind,
    String entityId,
    String commentId,
    UpdateCommentRequest body,
  ) async {
    await _tick();
    final i = _s.comments.indexWhere((c) => c.id == commentId);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = _s.comments[i];
    final next = Comment(
      id: cur.id,
      targetType: cur.targetType,
      targetId: cur.targetId,
      authorId: cur.authorId,
      body: body.body,
      bodyHtml: body.body,
      editedAt: DateTime.now().toUtc(),
      createdAt: cur.createdAt,
    );
    _s.comments[i] = next;
    return Ok(next);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteComment(
    String projectId,
    EntityKind kind,
    String entityId,
    String commentId,
  ) async {
    await _tick();
    _s.comments.removeWhere((c) => c.id == commentId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<List<HistoryEvent>, AppFailure>> listHistory(
    String projectId,
    EntityKind kind,
    String entityId,
  ) async {
    await _tick();
    return Ok(_s.historyEvents.toList());
  }

  @override
  Future<Result<List<Attachment>, AppFailure>> listAttachments(
    String projectId,
    EntityKind kind,
    String entityId,
  ) async {
    await _tick();
    final out = _s.attachments
        .where(
          (a) =>
              a.projectId == projectId &&
              a.targetType == kind.wire &&
              a.targetId == entityId,
        )
        .toList();
    return Ok(out);
  }

  @override
  Future<Result<Attachment, AppFailure>> uploadAttachment(
    String projectId,
    EntityKind kind,
    String entityId, {
    required String filename,
    required Uint8List bytes,
    String? contentType,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    // Mimic two progress ticks so the UI's progress bar actually moves.
    onSendProgress?.call(bytes.length ~/ 2, bytes.length);
    await _tick();
    onSendProgress?.call(bytes.length, bytes.length);
    final att = Attachment(
      id: _s.nextId('att'),
      projectId: projectId,
      targetType: kind.wire,
      targetId: entityId,
      uploaderId: _s.currentUser.id,
      filename: filename,
      contentType: contentType ?? 'application/octet-stream',
      sizeBytes: bytes.length,
      sha256: 'demo-sha-${bytes.length}',
      createdAt: DateTime.now().toUtc(),
    );
    _s.attachments.add(att);
    return Ok(att);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteAttachment(
    String projectId,
    String attachmentId,
  ) async {
    await _tick();
    _s.attachments.removeWhere((a) => a.id == attachmentId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<SignedDownload, AppFailure>> signAttachmentUrl(
    String projectId,
    String attachmentId,
  ) async {
    await _tick();
    final a = _s.attachments.where((a) => a.id == attachmentId).firstOrNull;
    if (a == null) return const Err(NotFoundFailure());
    return Ok(
      SignedDownload(
        url: 'about:blank#demo-${a.filename}',
        expiresAt:
            DateTime.now()
                .add(const Duration(minutes: 15))
                .millisecondsSinceEpoch ~/
            1000,
        filename: a.filename,
      ),
    );
  }

  @override
  Future<Result<List<Attachment>, AppFailure>> listCommentAttachments(
    String projectId,
    String commentId,
  ) async {
    await _tick();
    return Ok(
      _s.attachments
          .where((a) => a.targetType == 'comment' && a.targetId == commentId)
          .toList(),
    );
  }

  @override
  Future<Result<Attachment, AppFailure>> uploadCommentAttachment(
    String projectId,
    String commentId, {
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) async {
    await _tick();
    final att = Attachment(
      id: _s.nextId('att'),
      projectId: projectId,
      targetType: 'comment',
      targetId: commentId,
      uploaderId: _s.currentUser.id,
      filename: filename,
      contentType: contentType ?? 'application/octet-stream',
      sizeBytes: bytes.length,
      sha256: 'demo-sha-${bytes.length}',
      createdAt: DateTime.now().toUtc(),
    );
    _s.attachments.add(att);
    return Ok(att);
  }
}

// ---------------------------------------------------------------------------
// Milestones + Board
// ---------------------------------------------------------------------------

class DemoMilestonesRepository implements MilestonesRepository {
  DemoMilestonesRepository(this._s);
  final DemoStore _s;

  @override
  Future<Result<List<Milestone>, AppFailure>> list(String projectId) async {
    await _tick();
    return Ok(
      _s.milestones.where((m) => m.projectId == projectId).toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
    );
  }

  @override
  Future<Result<Milestone, AppFailure>> get(String projectId, String id) async {
    await _tick();
    final m = _s.milestones
        .where((m) => m.id == id && m.projectId == projectId)
        .firstOrNull;
    if (m == null) return const Err(NotFoundFailure());
    return Ok(m);
  }

  @override
  Future<Result<Milestone, AppFailure>> create(
    String projectId,
    CreateMilestoneRequest body,
  ) async {
    await _tick();
    final id = _s.nextId('ms');
    final order =
        _s.milestones.where((m) => m.projectId == projectId).length + 1;
    final ms = Milestone(
      id: id,
      projectId: projectId,
      name: body.name,
      slug: body.slug ?? body.name.toLowerCase().replaceAll(' ', '-'),
      startDate: body.startDate,
      endDate: body.endDate,
      closed: false,
      order: order.toDouble(),
      version: 1,
      createdAt: DateTime.now().toUtc(),
      modifiedAt: DateTime.now().toUtc(),
    );
    _s.milestones.add(ms);
    return Ok(ms);
  }

  @override
  Future<Result<Milestone, AppFailure>> update(
    String projectId,
    String id, {
    required UpdateMilestoneRequest body,
  }) async {
    await _tick();
    final i = _s.milestones.indexWhere(
      (m) => m.id == id && m.projectId == projectId,
    );
    if (i < 0) return const Err(NotFoundFailure());
    final cur = _s.milestones[i];
    final patch = body.toJson();
    final next = Milestone(
      id: cur.id,
      projectId: cur.projectId,
      name: (patch['name'] as String?) ?? cur.name,
      slug: cur.slug,
      startDate: patch.containsKey('start_date')
          ? (patch['start_date'] == null
                ? null
                : DateTime.tryParse(patch['start_date'] as String))
          : cur.startDate,
      endDate: patch.containsKey('end_date')
          ? (patch['end_date'] == null
                ? null
                : DateTime.tryParse(patch['end_date'] as String))
          : cur.endDate,
      closed: cur.closed,
      closedAt: cur.closedAt,
      order: cur.order,
      version: cur.version + 1,
      createdAt: cur.createdAt,
      modifiedAt: DateTime.now().toUtc(),
    );
    _s.milestones[i] = next;
    return Ok(next);
  }

  @override
  Future<Result<Unit, AppFailure>> delete(String projectId, String id) async {
    await _tick();
    _s.milestones.removeWhere((m) => m.id == id && m.projectId == projectId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<Unit, AppFailure>> close(String projectId, String id) async {
    await _tick();
    final i = _s.milestones.indexWhere(
      (m) => m.id == id && m.projectId == projectId,
    );
    if (i < 0) return const Err(NotFoundFailure());
    final cur = _s.milestones[i];
    _s.milestones[i] = Milestone(
      id: cur.id,
      projectId: cur.projectId,
      name: cur.name,
      slug: cur.slug,
      startDate: cur.startDate,
      endDate: cur.endDate,
      closed: true,
      closedAt: DateTime.now().toUtc(),
      order: cur.order,
      version: cur.version + 1,
      createdAt: cur.createdAt,
      modifiedAt: DateTime.now().toUtc(),
    );
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<MilestoneStats, AppFailure>> stats(
    String projectId,
    String id,
  ) async {
    await _tick();
    final issues = _s.issues
        .where((u) => u.projectId == projectId && u.milestoneId == id)
        .toList();
    final taxonomy = _s.taxonomyByProject[projectId] ?? const <TaxonomyItem>[];
    final statusById = {for (final t in taxonomy) t.id: t};

    var totalPoints = 0.0;
    var donePoints = 0.0;
    var doneCount = 0;
    for (final s in issues) {
      final pt = s.sizeId == null ? null : statusById[s.sizeId!]?.value;
      final closed =
          s.statusId != null && (statusById[s.statusId]?.isClosed ?? false);
      totalPoints += pt ?? 0;
      if (closed) {
        donePoints += pt ?? 0;
        doneCount++;
      }
    }
    return Ok(
      MilestoneStats(
        totalPoints: totalPoints,
        completedPoints: donePoints,
        totalTasks: issues.length,
        completedTasks: doneCount,
      ),
    );
  }

  @override
  Future<Result<Unit, AppFailure>> setEpics(
    String projectId,
    String milestoneId,
    List<String> epicIds,
  ) async {
    await _tick();
    return const Ok<Unit, AppFailure>(Unit.instance);
  }
}

class DemoBoardRepository implements BoardRepository {
  DemoBoardRepository(this._s);
  final DemoStore _s;

  @override
  Future<Result<BoardSnapshot, AppFailure>> load(
    String projectId,
    String milestoneId,
  ) async {
    await _tick();
    final statuses =
        (_s.taxonomyByProject[projectId] ?? const <TaxonomyItem>[])
            .where((t) => t.kind == TaxonomyKind.issueStatus)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    final issues = _s.issues
        .where(
          (u) =>
              u.projectId == projectId &&
              u.milestoneId == milestoneId &&
              u.parentId == null,
        )
        .toList();
    final columns = <BoardColumn>[
      for (final s in statuses)
        BoardColumn(
          status: s,
          issues: issues.where((u) => u.statusId == s.id).map(_card).toList(),
        ),
      // Trailing no-status column.
      BoardColumn(
        status: null,
        issues: issues.where((u) => u.statusId == null).map(_card).toList(),
      ),
    ];
    return Ok(BoardSnapshot(milestoneId: milestoneId, columns: columns));
  }

  BoardCard _card(Issue u) => BoardCard(
    issue: u,
    subtasks: _s.issues.where((t) => t.parentId == u.id).toList()
      ..sort((a, b) => a.order.compareTo(b.order)),
  );
}

// ---------------------------------------------------------------------------
// Wiki
// ---------------------------------------------------------------------------

class DemoWikiRepository implements WikiRepository {
  DemoWikiRepository(this._s);
  final DemoStore _s;

  @override
  Future<Result<List<WikiPage>, AppFailure>> list(String projectId) async {
    await _tick();
    return Ok(_s.wikiPages.where((p) => p.projectId == projectId).toList());
  }

  @override
  Future<Result<WikiPage, AppFailure>> get(
    String projectId,
    String pageId,
  ) async {
    await _tick();
    final p = _s.wikiPages
        .where((p) => p.id == pageId && p.projectId == projectId)
        .firstOrNull;
    if (p == null) return const Err(NotFoundFailure());
    return Ok(p);
  }

  @override
  Future<Result<WikiPage, AppFailure>> create(
    String projectId,
    CreateWikiPageRequest body,
  ) async {
    await _tick();
    final id = _s.nextId('wp');
    final page = WikiPage(
      id: id,
      projectId: projectId,
      slug: body.slug ?? body.title.toLowerCase().replaceAll(' ', '-'),
      title: body.title,
      body: body.body,
      bodyHtml: body.body,
      version: 1,
      editorId: _s.currentUser.id,
      createdAt: DateTime.now().toUtc(),
      modifiedAt: DateTime.now().toUtc(),
      etag: _s.etagOf(id, 1),
    );
    _s.wikiPages.add(page);
    _s.revisionsByPage[id] = [
      WikiRevision(
        id: _s.nextId('wpr'),
        pageId: id,
        rev: 1,
        title: page.title,
        body: page.body,
        editorId: _s.currentUser.id,
        createdAt: page.createdAt,
      ),
    ];
    return Ok(page);
  }

  @override
  Future<Result<WikiPage, AppFailure>> update(
    String projectId,
    String pageId, {
    required UpdateWikiPageRequest body,
    required String etag,
  }) async {
    await _tick();
    final i = _s.wikiPages.indexWhere(
      (p) => p.id == pageId && p.projectId == projectId,
    );
    if (i < 0) return const Err(NotFoundFailure());
    final cur = _s.wikiPages[i];
    if (cur.etag != etag) return const Err(ConflictFailure());
    final v = cur.version + 1;
    final next = WikiPage(
      id: cur.id,
      projectId: cur.projectId,
      slug: cur.slug,
      title: body.title ?? cur.title,
      body: body.body ?? cur.body,
      bodyHtml: body.body ?? cur.body,
      version: v,
      editorId: _s.currentUser.id,
      createdAt: cur.createdAt,
      modifiedAt: DateTime.now().toUtc(),
      etag: _s.etagOf(cur.id, v),
    );
    _s.wikiPages[i] = next;
    _s.revisionsByPage.putIfAbsent(cur.id, () => []);
    _s.revisionsByPage[cur.id] = [
      ..._s.revisionsByPage[cur.id]!,
      WikiRevision(
        id: _s.nextId('wpr'),
        pageId: cur.id,
        rev: v,
        title: next.title,
        body: next.body,
        editorId: _s.currentUser.id,
        createdAt: DateTime.now().toUtc(),
      ),
    ];
    return Ok(next);
  }

  @override
  Future<Result<Unit, AppFailure>> delete(
    String projectId,
    String pageId, {
    required String etag,
  }) async {
    await _tick();
    _s.wikiPages.removeWhere((p) => p.id == pageId);
    _s.revisionsByPage.remove(pageId);
    return const Ok<Unit, AppFailure>(Unit.instance);
  }

  @override
  Future<Result<List<WikiRevision>, AppFailure>> listRevisions(
    String projectId,
    String pageId,
  ) async {
    await _tick();
    return Ok(List.of(_s.revisionsByPage[pageId] ?? const <WikiRevision>[]));
  }

  @override
  Future<Result<WikiRevision, AppFailure>> getRevision(
    String projectId,
    String pageId,
    int rev,
  ) async {
    await _tick();
    final r = (_s.revisionsByPage[pageId] ?? const <WikiRevision>[])
        .where((x) => x.rev == rev)
        .firstOrNull;
    if (r == null) return const Err(NotFoundFailure());
    return Ok(r);
  }

  @override
  Future<Result<WikiDiff, AppFailure>> diff(
    String projectId,
    String pageId,
    int from, {
    int? to,
  }) async {
    await _tick();
    final revs = _s.revisionsByPage[pageId] ?? const <WikiRevision>[];
    final fromBody = revs.where((r) => r.rev == from).firstOrNull?.body ?? '';
    final toBody = to == null
        ? (_s.wikiPages.where((p) => p.id == pageId).firstOrNull?.body ?? '')
        : revs.where((r) => r.rev == to).firstOrNull?.body ?? '';
    // Tiny line-mode synthetic diff so the diff tab has something to show.
    final fromLines = fromBody.split('\n');
    final toLines = toBody.split('\n');
    final sb = StringBuffer('@@ demo diff @@\n');
    for (final l in fromLines) {
      if (!toLines.contains(l)) sb.writeln('-$l');
    }
    for (final l in toLines) {
      if (!fromLines.contains(l)) sb.writeln('+$l');
    }
    return Ok(WikiDiff(from: from, to: to, diff: sb.toString()));
  }

  @override
  Future<Result<WikiPage, AppFailure>> restore(
    String projectId,
    String pageId,
    int rev,
  ) async {
    await _tick();
    final r = (_s.revisionsByPage[pageId] ?? const <WikiRevision>[])
        .where((x) => x.rev == rev)
        .firstOrNull;
    if (r == null) return const Err(NotFoundFailure());
    final cur = _s.wikiPages.firstWhere((p) => p.id == pageId);
    return update(
      projectId,
      pageId,
      body: UpdateWikiPageRequest(title: r.title, body: r.body ?? ''),
      etag: cur.etag!,
    );
  }
}

class DemoLinksRepository implements LinksRepository {
  DemoLinksRepository(this._s);
  final DemoStore _s;

  @override
  Future<Result<List<EntityLink>, AppFailure>> listFor(
    String projectId,
    EntityKind kind,
    String entityId,
  ) async {
    await _tick();
    final out = _s.links
        .where(
          (l) =>
              l.projectId == projectId &&
              ((l.sourceKind == kind && l.sourceId == entityId) ||
                  (l.targetKind == kind && l.targetId == entityId)),
        )
        .toList();
    return Ok(out);
  }

  @override
  Future<Result<EntityLink, AppFailure>> create(
    String projectId,
    CreateLinkRequest body,
  ) async {
    await _tick();
    // Reject self-links and exact duplicates so the demo behaves like a
    // sane backend would.
    if (body.sourceKind == body.targetKind && body.sourceId == body.targetId) {
      return const Err(
        ValidationFailure(
          fieldErrors: [FieldError(field: 'target_id', code: 'self_link')],
        ),
      );
    }
    final duplicate = _s.links.any(
      (l) =>
          l.projectId == projectId &&
          l.type == body.type &&
          l.sourceKind == body.sourceKind &&
          l.sourceId == body.sourceId &&
          l.targetKind == body.targetKind &&
          l.targetId == body.targetId,
    );
    if (duplicate) {
      return const Err(ConflictFailure());
    }
    final link = EntityLink(
      id: _s.nextId('lnk'),
      projectId: projectId,
      sourceKind: body.sourceKind,
      sourceId: body.sourceId,
      targetKind: body.targetKind,
      targetId: body.targetId,
      type: body.type,
      createdAt: DateTime.now().toUtc(),
    );
    _s.links.add(link);
    return Ok(link);
  }

  @override
  Future<Result<Unit, AppFailure>> delete(
    String projectId,
    String linkId,
  ) async {
    await _tick();
    final i = _s.links.indexWhere(
      (l) => l.id == linkId && l.projectId == projectId,
    );
    if (i < 0) return const Err(NotFoundFailure());
    _s.links.removeAt(i);
    return const Ok(Unit.instance);
  }
}

// ---------------------------------------------------------------------------
// Platform admin (V011) — stub so the /admin/* pages don't crash demo mode.
// Reads pull from DemoStore.users; invitations + settings live in private
// fields here (the demo doesn't persist them across reloads).
// ---------------------------------------------------------------------------

class DemoAdminRepository implements AdminRepository {
  DemoAdminRepository(this._s);

  final DemoStore _s;
  final List<PendingInvitation> _invitations = [];
  PlatformSettings _settings = PlatformSettings(
    openRegistration: false,
    updatedAt: DateTime.now().toUtc(),
  );

  @override
  Future<Result<AdminUserList, AppFailure>> listUsers({
    String? q,
    int limit = 50,
    int offset = 0,
  }) async {
    await _tick();
    final needle = q?.trim().toLowerCase();
    Iterable<UserProfile> filtered = _s.users;
    if (needle != null && needle.isNotEmpty) {
      filtered = filtered.where(
        (u) =>
            u.email.toLowerCase().contains(needle) ||
            u.username.toLowerCase().contains(needle) ||
            u.fullName.toLowerCase().contains(needle),
      );
    }
    final all = filtered.toList(growable: false);
    final page = all.skip(offset).take(limit).toList(growable: false);
    return Ok(
      AdminUserList(
        items: page,
        total: all.length,
        limit: limit,
        offset: offset,
      ),
    );
  }

  @override
  Future<Result<ActivityList, AppFailure>> listActivity({
    String? action,
    int limit = 50,
    int offset = 0,
  }) async {
    await _tick();
    return Ok(
      ActivityList(items: const [], total: 0, limit: limit, offset: offset),
    );
  }

  @override
  Future<Result<CreateUserResponse, AppFailure>> createUser(
    CreateUserRequest body,
  ) async {
    await _tick();
    final emailLower = body.email.trim().toLowerCase();
    final dupe = _s.users.any((u) => u.email.toLowerCase() == emailLower);
    if (dupe) return const Err(ConflictFailure());
    final user = UserProfile(
      id: _s.nextId('user'),
      email: body.email,
      username: body.username,
      fullName: body.fullName,
      lang: 'en',
      timezone: 'UTC',
      isActive: true,
      isSuperadmin: body.isSuperadmin,
      mustChangePassword: body.password == null,
      createdAt: DateTime.now().toUtc(),
    );
    _s.users.add(user);
    return Ok(
      CreateUserResponse(
        user: user,
        generatedPassword: body.password == null
            ? 'demo-generated-password'
            : null,
      ),
    );
  }

  @override
  Future<Result<UserProfile, AppFailure>> updateUser(
    String id,
    UpdateUserRequest patch,
  ) async {
    await _tick();
    final i = _s.users.indexWhere((u) => u.id == id);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = _s.users[i];
    final next = UserProfile(
      id: cur.id,
      email: cur.email,
      username: cur.username,
      fullName: patch.fullName ?? cur.fullName,
      lang: cur.lang,
      timezone: cur.timezone,
      isActive: patch.isActive ?? cur.isActive,
      isSuperadmin: patch.isSuperadmin ?? cur.isSuperadmin,
      mustChangePassword: cur.mustChangePassword,
      createdAt: cur.createdAt,
    );
    _s.users[i] = next;
    return Ok(next);
  }

  @override
  Future<Result<Unit, AppFailure>> deleteUser(String id) async {
    await _tick();
    final i = _s.users.indexWhere((u) => u.id == id);
    if (i < 0) return const Err(NotFoundFailure());
    _s.users.removeAt(i);
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<PasswordResetIssued, AppFailure>> resetPassword(
    String id,
  ) async {
    await _tick();
    if (!_s.users.any((u) => u.id == id)) {
      return const Err(NotFoundFailure());
    }
    return Ok(
      PasswordResetIssued(
        resetToken: 'demo-reset-token',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
      ),
    );
  }

  @override
  Future<Result<CreateInvitationResponse, AppFailure>> createInvitation(
    CreateInvitationRequest body,
  ) async {
    await _tick();
    final id = _s.nextId('inv');
    final now = DateTime.now().toUtc();
    final expires = now.add(const Duration(days: 7));
    _invitations.add(
      PendingInvitation(
        id: id,
        email: body.email,
        role: body.role,
        invitedBy: _s.currentUser.id,
        expiresAt: expires,
        createdAt: now,
      ),
    );
    return Ok(
      CreateInvitationResponse(
        invitationId: id,
        email: body.email,
        role: body.role,
        expiresAt: expires,
        inviteToken: 'demo-invite-token-$id',
      ),
    );
  }

  @override
  Future<Result<List<PendingInvitation>, AppFailure>> listInvitations() async {
    await _tick();
    return Ok(List.unmodifiable(_invitations));
  }

  @override
  Future<Result<Unit, AppFailure>> revokeInvitation(String id) async {
    await _tick();
    final i = _invitations.indexWhere((inv) => inv.id == id);
    if (i < 0) return const Err(NotFoundFailure());
    _invitations.removeAt(i);
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<PlatformSettings, AppFailure>> getSettings() async {
    await _tick();
    return Ok(_settings);
  }

  @override
  Future<Result<PlatformSettings, AppFailure>> updateOpenRegistration(
    bool value,
  ) async {
    await _tick();
    _settings = _copySettings(openRegistration: value);
    return Ok(_settings);
  }

  /// Rebuilds [_settings] preserving the unspecified fields (PlatformSettings
  /// is immutable and has no copyWith). `clearName`/`clearMessage`/`clearIcon`
  /// force the corresponding field back to its default.
  PlatformSettings _copySettings({
    bool? openRegistration,
    String? appName,
    String? appMessage,
    bool clearName = false,
    bool clearMessage = false,
    bool? hasCustomIcon,
  }) {
    return PlatformSettings(
      openRegistration: openRegistration ?? _settings.openRegistration,
      updatedAt: DateTime.now().toUtc(),
      updatedBy: _s.currentUser.id,
      appName: clearName ? null : (appName ?? _settings.appName),
      appMessage: clearMessage ? null : (appMessage ?? _settings.appMessage),
      hasCustomIcon: hasCustomIcon ?? _settings.hasCustomIcon,
      appIconUpdatedAt: (hasCustomIcon ?? _settings.hasCustomIcon)
          ? DateTime.now().toUtc().toIso8601String()
          : null,
    );
  }

  @override
  Future<Result<PlatformSettings, AppFailure>> updateBranding({
    String? appName,
    String? appMessage,
  }) async {
    await _tick();
    final name = appName?.trim();
    final message = appMessage?.trim();
    _settings = _copySettings(
      appName: name,
      appMessage: message,
      clearName: name == null || name.isEmpty,
      clearMessage: message == null || message.isEmpty,
    );
    return Ok(_settings);
  }

  @override
  Future<Result<PlatformSettings, AppFailure>> uploadBrandingIcon({
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) async {
    await _tick();
    _settings = _copySettings(hasCustomIcon: true);
    return Ok(_settings);
  }

  @override
  Future<Result<PlatformSettings, AppFailure>> deleteBrandingIcon() async {
    await _tick();
    _settings = _copySettings(hasCustomIcon: false);
    return Ok(_settings);
  }

  LdapSettings _ldap = LdapSettings(
    enabled: false,
    serverUrl: '',
    useStartTls: false,
    skipTlsVerify: false,
    baseDn: '',
    defaultDomain: '',
    bindDnFormat: '%s',
    userSearchFilter: '(sAMAccountName=%s)',
    superadminGroup: '',
    attrEmail: 'mail',
    attrDisplayName: 'displayName',
    attrUsername: 'sAMAccountName',
    connectionTimeoutSecs: 10,
    updatedAt: DateTime(2026),
  );

  @override
  Future<Result<LdapSettings, AppFailure>> getLdapSettings() async {
    await _tick();
    return Ok(_ldap);
  }

  @override
  Future<Result<LdapSettings, AppFailure>> updateLdapSettings(
    UpdateLdapSettingsRequest req,
  ) async {
    await _tick();
    _ldap = LdapSettings(
      enabled: req.enabled,
      serverUrl: req.serverUrl,
      useStartTls: req.useStartTls,
      skipTlsVerify: req.skipTlsVerify,
      baseDn: req.baseDn,
      defaultDomain: req.defaultDomain,
      bindDnFormat: req.bindDnFormat,
      userSearchFilter: req.userSearchFilter,
      superadminGroup: req.superadminGroup,
      attrEmail: req.attrEmail,
      attrDisplayName: req.attrDisplayName,
      attrUsername: req.attrUsername,
      connectionTimeoutSecs: req.connectionTimeoutSecs,
      updatedAt: DateTime.now().toUtc(),
      updatedBy: _s.currentUser.id,
    );
    return Ok(_ldap);
  }

  @override
  Future<Result<LdapTestResult, AppFailure>> testLdapSettings({
    required UpdateLdapSettingsRequest settings,
    required String username,
    required String password,
  }) async {
    await _tick();
    // Demo mode has no directory — report a clear, harmless failure.
    return const Ok(
      LdapTestResult(
        ok: false,
        message: 'Demo mode: no directory is configured.',
      ),
    );
  }

  NotificationSettings _notif = const NotificationSettings(
    mailEnabled: false,
    mailProvider: 'smtp',
    mailFromAddress: '',
    mailFromName: 'IntelliPilot',
    smtpHost: '',
    smtpPort: 587,
    smtpUsername: '',
    smtpPasswordSet: false,
    smtpUseStarttls: true,
    smtpSkipTlsVerify: false,
    mailgunApiKeySet: false,
    mailgunDomain: '',
    mailgunBaseUrl: 'https://api.mailgun.net',
    matrixEnabled: false,
    matrixHomeserver: '',
    matrixRoomId: '',
    matrixAccessTokenSet: false,
    telegramEnabled: false,
    telegramBotTokenSet: false,
    telegramChatId: '',
    mailOnLogin: false,
    mailOnIssueCreated: false,
    mailOnIssueResolved: false,
    mailOnDailyReport: false,
    msgOnLogin: false,
    msgOnIssueCreated: false,
    msgOnIssueResolved: false,
    msgOnDailyReport: false,
  );

  @override
  Future<Result<NotificationSettings, AppFailure>>
  getNotificationSettings() async {
    await _tick();
    return Ok(_notif);
  }

  @override
  Future<Result<NotificationSettings, AppFailure>> updateNotificationSettings(
    NotificationSettingsUpdate req,
  ) async {
    await _tick();
    _notif = NotificationSettings(
      mailEnabled: req.mailEnabled,
      mailProvider: req.mailProvider,
      mailFromAddress: req.mailFromAddress,
      mailFromName: req.mailFromName,
      smtpHost: req.smtpHost,
      smtpPort: req.smtpPort,
      smtpUsername: req.smtpUsername,
      smtpPasswordSet: req.smtpPassword.isNotEmpty || _notif.smtpPasswordSet,
      smtpUseStarttls: req.smtpUseStarttls,
      smtpSkipTlsVerify: req.smtpSkipTlsVerify,
      mailgunApiKeySet: req.mailgunApiKey.isNotEmpty || _notif.mailgunApiKeySet,
      mailgunDomain: req.mailgunDomain,
      mailgunBaseUrl: req.mailgunBaseUrl,
      matrixEnabled: req.matrixEnabled,
      matrixHomeserver: req.matrixHomeserver,
      matrixRoomId: req.matrixRoomId,
      matrixAccessTokenSet:
          req.matrixAccessToken.isNotEmpty || _notif.matrixAccessTokenSet,
      telegramEnabled: req.telegramEnabled,
      telegramBotTokenSet:
          req.telegramBotToken.isNotEmpty || _notif.telegramBotTokenSet,
      telegramChatId: req.telegramChatId,
      mailOnLogin: req.mailOnLogin,
      mailOnIssueCreated: req.mailOnIssueCreated,
      mailOnIssueResolved: req.mailOnIssueResolved,
      mailOnDailyReport: req.mailOnDailyReport,
      msgOnLogin: req.msgOnLogin,
      msgOnIssueCreated: req.msgOnIssueCreated,
      msgOnIssueResolved: req.msgOnIssueResolved,
      msgOnDailyReport: req.msgOnDailyReport,
    );
    return Ok(_notif);
  }

  @override
  Future<Result<NotificationTestResult, AppFailure>> testNotification({
    required String channel,
    String? to,
  }) async {
    await _tick();
    return const Ok(
      NotificationTestResult(
        ok: false,
        message: 'Demo mode: no transport is configured.',
      ),
    );
  }

  final List<AppTokenDto> _appTokens = [];

  @override
  Future<Result<List<AppTokenDto>, AppFailure>> listAppTokens() async {
    await _tick();
    return Ok(List.unmodifiable(_appTokens));
  }

  @override
  Future<Result<CreateAppTokenResult, AppFailure>> createAppToken(
    CreateAppTokenRequest body,
  ) async {
    await _tick();
    const secret = 'ipat_demoDEMOdemoDEMOdemoDEMOdemo01';
    final token = AppTokenDto(
      id: 'demo-${_appTokens.length + 1}',
      name: body.name,
      prefix: secret.substring(0, 11),
      last4: secret.substring(secret.length - 4),
      permissions: body.permissions,
      projectIds: body.projectIds,
      createdBy: null,
      expiresAt: body.expiresAt,
      revokedAt: null,
      lastUsedAt: null,
      createdAt: DateTime.now(),
    );
    _appTokens.insert(0, token);
    return Ok(CreateAppTokenResult(token: token, secret: secret));
  }

  @override
  Future<Result<AppTokenDto, AppFailure>> updateAppToken(
    String id,
    UpdateAppTokenRequest body,
  ) async {
    await _tick();
    final i = _appTokens.indexWhere((tok) => tok.id == id);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = _appTokens[i];
    final next = AppTokenDto(
      id: cur.id,
      name: body.name ?? cur.name,
      prefix: cur.prefix,
      last4: cur.last4,
      permissions: body.permissions ?? cur.permissions,
      projectIds: body.projectIds ?? cur.projectIds,
      createdBy: cur.createdBy,
      expiresAt: cur.expiresAt,
      revokedAt: cur.revokedAt,
      lastUsedAt: cur.lastUsedAt,
      createdAt: cur.createdAt,
    );
    _appTokens[i] = next;
    return Ok(next);
  }

  @override
  Future<Result<Unit, AppFailure>> revokeAppToken(String id) async {
    await _tick();
    final i = _appTokens.indexWhere((tok) => tok.id == id);
    if (i < 0) return const Err(NotFoundFailure());
    final cur = _appTokens[i];
    _appTokens[i] = AppTokenDto(
      id: cur.id,
      name: cur.name,
      prefix: cur.prefix,
      last4: cur.last4,
      permissions: cur.permissions,
      projectIds: cur.projectIds,
      createdBy: cur.createdBy,
      expiresAt: cur.expiresAt,
      revokedAt: DateTime.now(),
      lastUsedAt: cur.lastUsedAt,
      createdAt: cur.createdAt,
    );
    return const Ok(Unit.instance);
  }
}
