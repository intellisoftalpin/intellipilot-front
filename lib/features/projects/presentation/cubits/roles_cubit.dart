// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

sealed class RolesState extends Equatable {
  const RolesState();
  @override
  List<Object?> get props => const [];
}

final class RolesLoading extends RolesState {
  const RolesLoading();
}

final class RolesLoaded extends RolesState {
  const RolesLoaded({required this.roles, this.busy = false, this.lastError});
  final List<Role> roles;
  final bool busy;
  final AppFailure? lastError;

  RolesLoaded copyWith({
    List<Role>? roles,
    bool? busy,
    AppFailure? lastError,
  }) => RolesLoaded(
    roles: roles ?? this.roles,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [roles.map((r) => r.id).toList(), busy, lastError];
}

final class RolesFailed extends RolesState {
  const RolesFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class RolesCubit extends Cubit<RolesState> {
  RolesCubit({required ProjectsRepository repo, required this.projectId})
    : _repo = repo,
      super(const RolesLoading());

  final ProjectsRepository _repo;
  final String projectId;

  Future<void> load() async {
    emit(const RolesLoading());
    final res = await _repo.listRoles(projectId);
    res.when(
      ok: (rs) => emit(RolesLoaded(roles: rs)),
      err: (f) => emit(RolesFailed(f)),
    );
  }

  Future<void> create({
    required String name,
    required String slug,
    required Set<Permission> permissions,
  }) async {
    final s = state;
    if (s is! RolesLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createRole(
      projectId,
      CreateRoleRequest(name: name, slug: slug, permissions: permissions),
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> updatePermissions(
    String roleId,
    Set<Permission> permissions, {
    String? name,
  }) async {
    final s = state;
    if (s is! RolesLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.updateRole(
      projectId,
      roleId,
      UpdateRoleRequest(name: name, permissions: permissions),
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> delete(String roleId) async {
    final s = state;
    if (s is! RolesLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.deleteRole(projectId, roleId);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
