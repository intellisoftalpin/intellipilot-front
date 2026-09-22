// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/core/result/result.dart';
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
  });
  final Project project;
  final Set<Permission> myPermissions;

  /// Caller's role has `is_admin = true` (implicit holder of every
  /// permission, including future ones).
  final bool isAdmin;

  bool has(Permission p) => isAdmin || myPermissions.contains(p);

  /// True if the caller holds any of [perms] (or is an admin). Used to decide
  /// whether to surface a management UI gated by a group of create/modify/
  /// delete permissions.
  bool hasAny(Iterable<Permission> perms) => isAdmin || perms.any(has);

  @override
  List<Object?> get props => [project.id, myPermissions, isAdmin];
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
  }) : _repo = repo,
       super(const ProjectDetailLoading());

  final ProjectsRepository _repo;
  final String projectId;
  final String currentUserId;

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
    );

    emit(
      ProjectDetailLoaded(
        project: project,
        myPermissions: access.permissions,
        isAdmin: access.isAdmin,
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
        ),
      );
    }
  }
}

/// The caller's permissions inside one project, as their role grants them.
class ProjectAccess {
  const ProjectAccess({required this.permissions, required this.isAdmin});

  /// No membership, or the roster could not be read.
  static const ProjectAccess none = ProjectAccess(
    permissions: <Permission>{},
    isAdmin: false,
  );

  final Set<Permission> permissions;

  /// Role has `is_admin = true` — implicit holder of every permission.
  final bool isAdmin;

  bool has(Permission p) => isAdmin || permissions.contains(p);
}

/// Resolve [userId]'s role permissions in [projectId] from the member and
/// role lists.
///
/// Degrades to [ProjectAccess.none] rather than failing: someone without
/// `member.view` can still view the project (`project.view` is enough), so an
/// unreadable roster means "no known permissions", not an error.
Future<ProjectAccess> resolveProjectAccess(
  ProjectsRepository repo, {
  required String projectId,
  required String userId,
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
  if (mine == null) return ProjectAccess.none;
  final role = roles.where((r) => r.id == mine.roleId).firstOrNull;
  if (role == null) return ProjectAccess.none;
  return ProjectAccess(
    permissions: Set.of(role.permissions),
    isAdmin: role.isAdmin,
  );
}
