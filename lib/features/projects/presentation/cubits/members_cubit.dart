// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

sealed class MembersState extends Equatable {
  const MembersState();
  @override
  List<Object?> get props => const [];
}

final class MembersLoading extends MembersState {
  const MembersLoading();
}

final class MembersLoaded extends MembersState {
  const MembersLoaded({
    required this.members,
    required this.roles,
    this.busy = false,
    this.lastError,
  });
  final List<Membership> members;
  final List<Role> roles;
  final bool busy;
  final AppFailure? lastError;

  MembersLoaded copyWith({
    List<Membership>? members,
    List<Role>? roles,
    bool? busy,
    AppFailure? lastError,
  }) => MembersLoaded(
    members: members ?? this.members,
    roles: roles ?? this.roles,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [
    members.map((m) => m.id).toList(),
    roles.map((r) => r.id).toList(),
    busy,
    lastError,
  ];
}

final class MembersFailed extends MembersState {
  const MembersFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class MembersCubit extends Cubit<MembersState> {
  MembersCubit({
    required ProjectsRepository repo,
    required this.projectId,
  }) : _repo = repo,
       super(const MembersLoading());

  final ProjectsRepository _repo;
  final String projectId;

  Future<void> load() async {
    emit(const MembersLoading());
    final m = await _repo.listMembers(projectId);
    final r = await _repo.listRoles(projectId);
    final mFail = m.failureOrNull;
    final rFail = r.failureOrNull;
    if (mFail != null) {
      emit(MembersFailed(mFail));
      return;
    }
    if (rFail != null) {
      emit(MembersFailed(rFail));
      return;
    }
    emit(
      MembersLoaded(members: m.valueOrNull!, roles: r.valueOrNull!),
    );
  }

  Future<void> changeRole(String userId, String newRoleSlug) async {
    final s = state;
    if (s is! MembersLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.changeMemberRole(projectId, userId, newRoleSlug);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  Future<void> remove(String userId) async {
    final s = state;
    if (s is! MembersLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.removeMember(projectId, userId);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }

  /// Add an existing user (by id from the picker, or by exact email/username).
  /// Returns the failure on error (so the dialog can surface "no such user"),
  /// or `null` on success.
  Future<AppFailure?> addMember({
    required String roleSlug,
    String? userId,
    String? identifier,
  }) async {
    final s = state;
    if (s is! MembersLoaded) return null;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.addMember(
      projectId,
      userId: userId,
      identifier: identifier,
      roleSlug: roleSlug,
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return res.failureOrNull;
    }
    await load();
    return null;
  }
}
