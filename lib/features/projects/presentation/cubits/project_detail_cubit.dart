// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
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

    // Resolve the caller's permissions inside this project. If they lack
    // member.view they can still view the project (project.view is enough)
    // so we degrade gracefully — empty permission set rather than failure.
    final members = await _repo.listMembers(projectId);
    final roles = await _repo.listRoles(projectId);
    var perms = <Permission>{};
    var admin = false;
    Membership? myMembership;
    for (final m in members.valueOrNull ?? const <Membership>[]) {
      if (m.userId == currentUserId) {
        myMembership = m;
        break;
      }
    }
    if (myMembership != null) {
      for (final r in roles.valueOrNull ?? const <Role>[]) {
        if (r.id == myMembership.roleId) {
          perms = Set.from(r.permissions);
          admin = r.isAdmin;
          break;
        }
      }
    }

    emit(
      ProjectDetailLoaded(
        project: project,
        myPermissions: perms,
        isAdmin: admin,
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
