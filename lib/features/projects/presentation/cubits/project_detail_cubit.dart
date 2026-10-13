// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
import 'package:intellipilot/features/meetings/domain/project_access_cache.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

sealed class ProjectDetailState extends Equatable {
  const ProjectDetailState();
  @override
  List<Object?> get props => const [];
}

final class ProjectDetailLoading extends ProjectDetailState {
  const ProjectDetailLoading();
}

final class ProjectDetailLoaded extends ProjectDetailState {
  const ProjectDetailLoaded({
    required this.project,
    required this.myPermissions,
    required this.isAdmin,
    this.readAll = false,
    this.isMember = true,
  });
  final Project project;
  final Set<Permission> myPermissions;

  /// Caller's role has `is_admin = true` (implicit holder of every
  /// permission, including future ones).
  final bool isAdmin;

  /// Platform superadmin: holds every read permission on top of his role.
  final bool readAll;

  /// Caller belongs to the project.
  final bool isMember;

  /// A superadmin reading a project he is not a member of — he may add
  /// himself, and nothing else.
  bool get canJoin => readAll && !isMember;

  bool has(Permission p) =>
      isAdmin || myPermissions.contains(p) || (readAll && p.isRead);

  /// True if the caller holds any of [perms] (or is an admin). Used to decide
  /// whether to surface a management UI gated by a group of create/modify/
  /// delete permissions.
  bool hasAny(Iterable<Permission> perms) => isAdmin || perms.any(has);

  @override
  List<Object?> get props => [
    project.id,
    myPermissions,
    isAdmin,
    readAll,
    isMember,
  ];
}

final class ProjectDetailFailed extends ProjectDetailState {
  const ProjectDetailFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class ProjectDetailCubit extends Cubit<ProjectDetailState> {
  ProjectDetailCubit({
    required ProjectsRepository repo,
    required this.projectId,
    required this.currentUserId,
    this.isSuperadmin = false,
    Listenable? accessChanges,
  }) : _repo = repo,
       _accessChanges =
           accessChanges ??
           (getIt.isRegistered<ProjectAccessCache>()
               ? getIt<ProjectAccessCache>()
               : null),
       super(const ProjectDetailLoading()) {
    _accessChanges?.addListener(_onAccessChanged);
  }

  final ProjectsRepository _repo;
  final String projectId;
  final String currentUserId;

  /// Platform superadmin: reads every project, writes only as a member.
  final bool isSuperadmin;

  /// Fires when someone's membership changed — a superadmin joining from the
  /// banner or the Members tab — so every open page picks up its new rights.
  final Listenable? _accessChanges;

  void _onAccessChanged() => unawaited(refreshAccess());

  /// Re-resolve the caller's permissions without blanking the page.
  Future<void> refreshAccess() async {
    if (state is! ProjectDetailLoaded) return;
    final access = await resolveProjectAccess(
      _repo,
      projectId: projectId,
      userId: currentUserId,
      isSuperadmin: isSuperadmin,
    );
    final s = state;
    if (isClosed || s is! ProjectDetailLoaded) return;
    emit(
      ProjectDetailLoaded(
        project: s.project,
        myPermissions: access.permissions,
        isAdmin: access.isAdmin,
        readAll: access.readAll,
        isMember: access.isMember,
      ),
    );
  }

  @override
  Future<void> close() {
    _accessChanges?.removeListener(_onAccessChanged);
    return super.close();
  }

  Future<void> load() async {
    emit(const ProjectDetailLoading());
    final p = await _repo.getProject(projectId);
    final pFail = p.failureOrNull;
    if (pFail != null) {
      emit(ProjectDetailFailed(pFail));
      return;
    }
    final project = p.valueOrNull!;

    final access = await resolveProjectAccess(
      _repo,
      projectId: projectId,
      userId: currentUserId,
      isSuperadmin: isSuperadmin,
    );

    emit(
      ProjectDetailLoaded(
        project: project,
        myPermissions: access.permissions,
        isAdmin: access.isAdmin,
        readAll: access.readAll,
        isMember: access.isMember,
      ),
    );
  }

  void replace(Project updated) {
    final s = state;
    if (s is ProjectDetailLoaded && s.project.id == updated.id) {
      emit(
        ProjectDetailLoaded(
          project: updated,
          myPermissions: s.myPermissions,
          isAdmin: s.isAdmin,
          readAll: s.readAll,
          isMember: s.isMember,
        ),
      );
    }
  }
}

/// The caller's permissions inside one project, as their role grants them
/// (plus every read for a platform superadmin).
class ProjectAccess {
  const ProjectAccess({
    required this.permissions,
    required this.isAdmin,
    this.readAll = false,
    this.isMember = false,
  });

  /// No membership, or the roster could not be read.
  static const ProjectAccess none = ProjectAccess(
    permissions: <Permission>{},
    isAdmin: false,
  );

  final Set<Permission> permissions;

  /// Role has `is_admin = true` — implicit holder of every permission.
  final bool isAdmin;

  /// Platform superadmin: holds every read permission on top of the role.
  final bool readAll;

  /// The caller belongs to the project.
  final bool isMember;

  bool has(Permission p) =>
      isAdmin || permissions.contains(p) || (readAll && p.isRead);
}

/// Resolve [userId]'s role permissions in [projectId] from the member and
/// role lists. A superadmin ([isSuperadmin]) additionally reads everything —
/// member or not — but writes only as his role allows, as the backend does.
///
/// Degrades to [ProjectAccess.none] rather than failing: someone without
/// `member.view` can still view the project (`project.view` is enough), so an
/// unreadable roster means "no known permissions", not an error.
Future<ProjectAccess> resolveProjectAccess(
  ProjectsRepository repo, {
  required String projectId,
  required String userId,
  bool isSuperadmin = false,
}) async {
  final results = await Future.wait<dynamic>([
    repo.listMembers(projectId),
    repo.listRoles(projectId),
  ]);
  final members =
      (results[0] as Result<List<Membership>, AppFailure>).valueOrNull ??
      const <Membership>[];
  final roles =
      (results[1] as Result<List<Role>, AppFailure>).valueOrNull ??
      const <Role>[];
  final mine = members.where((m) => m.userId == userId).firstOrNull;
  final role = mine == null
      ? null
      : roles.where((r) => r.id == mine.roleId).firstOrNull;
  return ProjectAccess(
    permissions: role == null ? <Permission>{} : Set.of(role.permissions),
    isAdmin: role?.isAdmin ?? false,
    readAll: isSuperadmin,
    isMember: mine != null,
  );
}
