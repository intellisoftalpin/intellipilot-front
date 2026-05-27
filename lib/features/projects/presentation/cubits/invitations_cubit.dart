// Underscore-prefixed fields are clearer than `{required this._repo}` in
// the public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/projects/data/dtos/project_dtos.dart';
import 'package:intellipilot/features/projects/domain/projects_repository.dart';

sealed class InvitationsState extends Equatable {
  const InvitationsState();
  @override
  List<Object?> get props => const [];
}

final class InvitationsLoading extends InvitationsState {
  const InvitationsLoading();
}

final class InvitationsLoaded extends InvitationsState {
  const InvitationsLoaded({
    required this.invitations,
    this.busy = false,
    this.lastInviteToken,
    this.lastError,
  });
  final List<Invitation> invitations;
  final bool busy;

  /// Dev-only raw token from the most recent `invite()` call, surfaced once
  /// so the UI can show a copy/share affordance when no mailer is configured.
  final String? lastInviteToken;
  final AppFailure? lastError;

  InvitationsLoaded copyWith({
    List<Invitation>? invitations,
    bool? busy,
    String? lastInviteToken,
    AppFailure? lastError,
  }) => InvitationsLoaded(
    invitations: invitations ?? this.invitations,
    busy: busy ?? this.busy,
    lastInviteToken: lastInviteToken,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [
    invitations.map((i) => i.id).toList(),
    busy,
    lastInviteToken,
    lastError,
  ];
}

final class InvitationsFailed extends InvitationsState {
  const InvitationsFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class InvitationsCubit extends Cubit<InvitationsState> {
  InvitationsCubit({
    required ProjectsRepository repo,
    required this.projectId,
  }) : _repo = repo,
       super(const InvitationsLoading());

  final ProjectsRepository _repo;
  final String projectId;

  Future<void> load() async {
    emit(const InvitationsLoading());
    final res = await _repo.listInvitations(projectId);
    res.when(
      ok: (invs) => emit(InvitationsLoaded(invitations: invs)),
      err: (f) => emit(InvitationsFailed(f)),
    );
  }

  Future<void> invite({required String email, required String roleSlug}) async {
    final s = state;
    if (s is! InvitationsLoaded) return;
    emit(s.copyWith(busy: true, lastError: null, lastInviteToken: null));
    final res = await _repo.invite(
      projectId,
      InviteRequest(email: email, role: roleSlug),
    );
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    final token = res.valueOrNull?.inviteToken;
    // Refresh to pull in the new pending invitation, then re-attach token.
    final fresh = await _repo.listInvitations(projectId);
    fresh.when(
      ok: (invs) => emit(
        InvitationsLoaded(invitations: invs, lastInviteToken: token),
      ),
      err: (f) => emit(InvitationsFailed(f)),
    );
  }
}
